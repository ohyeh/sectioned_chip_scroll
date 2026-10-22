import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sectioned_chip_scroll/src/application/sectioned_chip_scroll_config.dart';
import 'package:sectioned_chip_scroll/src/domain/chip_section.dart';
import 'package:sectioned_chip_scroll/src/domain/section_geometry.dart';
import 'package:sectioned_chip_scroll/src/presentation/chrome.dart';
import 'package:sectioned_chip_scroll/src/presentation/motion.dart';
import 'package:sectioned_chip_scroll/src/presentation/picker.dart';
import 'package:sectioned_chip_scroll/src/presentation/sectioned_chip_scroll_style.dart';
import 'package:sectioned_chip_scroll/src/presentation/sectioned_layout.dart';

/// A chip bar above a list of sections, with scroll-spy.
///
/// - Scrolling selects the chip of the section in view.
/// - Tapping a chip scrolls its section to just below the bar.
/// - The optional expand button opens a picker with every section.
///
/// The view is a scroll view: give it bounded height, for example as the
/// body of a `Scaffold` or inside `Expanded`.
///
/// Sections are shown in the given order. The view does not sort, merge or
/// remove duplicates; give it clean data with unique, stable
/// [ChipSection.id]s. Loading, error and empty screens belong to the caller:
/// with no sections to show, the view builds nothing.
class SectionedChipScrollView<T> extends StatefulWidget {
  /// Creates the view.
  const SectionedChipScrollView({
    super.key,
    required this.sections,
    required this.itemBuilder,
    this.layout = const SectionedLayout.list(),
    this.style = const SectionedChipScrollStyle.outlined(),
    this.sectionDecoration,
    this.config = const SectionedChipScrollConfig(),
    this.labels = const SectionedChipScrollLabels(),
    this.initialSectionId,
    this.onSectionTap,
    this.onSectionSelected,
    this.columnsBuilder,
    this.chipTextStyle,
    this.selectedChipTextStyle,
    this.sectionTitleStyle,
    this.panelTitleStyle,
  }) : assert(
         columnsBuilder == null ||
             (layout is SectionedGridLayout && layout is! SectionedListLayout),
         'columnsBuilder cannot be set when layout is a custom or list layout ($layout)',
       );

  /// The sections, in display order.
  final List<ChipSection<T>> sections;

  /// Section selected when the view is first built, instead of the first one.
  ///
  /// It does not scroll; pair it with a restored scroll position (for
  /// example a `PageStorageKey` on the view). At the bottom of the list it
  /// stays selected while visible, like a section the user jumped to.
  /// Ignored when no visible section has this id, and after the first build.
  final String? initialSectionId;

  /// Builds one item cell. Taps and navigation inside the cell are up to the
  /// caller.
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Section geometry and sliver renderer.
  final SectionedLayout layout;

  /// Visual values, separate from the layout rules.
  final SectionedChipScrollStyle style;

  /// Paints each section; decoration padding enters the layout table.
  final Decoration? sectionDecoration;

  /// Product switches. See [SectionedChipScrollConfig].
  final SectionedChipScrollConfig config;

  /// Visible and spoken text. See [SectionedChipScrollLabels].
  final SectionedChipScrollLabels labels;

  /// Called when a section title is tapped.
  ///
  /// When null, titles are plain headers: no tap target and no button
  /// semantics.
  final ValueChanged<ChipSection<T>>? onSectionTap;

  /// Called when the selected section changes, by a chip tap, the picker,
  /// scrolling, or a data update that removes the selected section.
  final ValueChanged<ChipSection<T>>? onSectionSelected;

  /// Picks the number of item columns. When null, [defaultColumns] is used.
  final SectionColumnsBuilder? columnsBuilder;

  /// Style of an unselected chip label, merged over `textTheme.labelLarge`.
  final TextStyle? chipTextStyle;

  /// Style of the selected chip label, merged over the unselected style.
  final TextStyle? selectedChipTextStyle;

  /// Style of section titles, merged over `textTheme.titleMedium`.
  final TextStyle? sectionTitleStyle;

  /// Style of the picker title, merged over `textTheme.titleMedium`.
  final TextStyle? panelTitleStyle;

  /// Three columns, two at twice the default text size or more, and fewer
  /// when a cell would be narrower than 72 logical pixels.
  static int defaultColumns(double maxWidth, TextScaler textScaler) {
    return SectionedGridLayout.defaultColumns(maxWidth, textScaler);
  }

  @override
  State<SectionedChipScrollView<T>> createState() =>
      SectionedChipScrollViewState<T>();
}

/// State of [SectionedChipScrollView]. Not part of the supported API; it is
/// public only for behavior tests and geometry inspection.
class SectionedChipScrollViewState<T> extends State<SectionedChipScrollView<T>>
    with SingleTickerProviderStateMixin {
  final _scroll = _IndexedScrollController();
  final _originId = ValueNotifier<String?>(null);
  bool _restoredOrigin = false;
  bool _restoring = false;
  // The chip bar position follows the selection; it must not take the list's
  // PageStorage slot.
  final _chipScroll = ScrollController(keepScrollOffset: false);
  final _chipBarKey = GlobalKey();
  final _sliverKeys = <String, GlobalKey>{};
  final _headerKeys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};

  List<ChipSection<T>> _sections = const [];
  String? _selectedId;
  int _jumpToken = 0;
  String? _targetId;
  bool _moving = false;
  Route<void>? _panelRoute;
  final _cacheExtent = ValueNotifier<double?>(null);
  late final AnimationController _motion =
      AnimationController.unbounded(vsync: this)..addListener(() {
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            _motion.value.clamp(
              _scroll.position.minScrollExtent,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
      });
  String? _endPick;
  // The list reads only widget data, so a selection change (setState) reuses
  // it and rebuilds just the chip bar. Cleared when its inputs change.
  _LayoutContent<T>? _listCache;
  int? _listColumns;
  SectionedGeometry? _geometry;

  /// Current immutable snapshot, including explicitly unknown row extents.
  SectionedGeometry? get geometry => _geometry;

  /// Active transaction phase, exposed for deterministic cancellation tests.
  @visibleForTesting
  String? get navigationPhase => _targetId == null
      ? null
      : _moving
      ? 'moving'
      : 'preparing';

  @override
  void initState() {
    super.initState();
    _motion;
    _scroll.addListener(_spy);
    _sections = _visibleSections();
    final initial = widget.initialSectionId;
    if (_sections.any((s) => s.id == initial)) {
      _selectedId = initial;
      _endPick = initial;
    } else {
      _selectedId = _sections.firstOrNull?.id;
    }
    // A restored scroll offset sends no scroll notification, so observe once
    // to match the selection to what is on screen, and show its chip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _spy();
      final id = _selectedId;
      if (id != null) _revealChip(id);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredOrigin) return;
    _restoredOrigin = true;
    final saved = PageStorage.maybeOf(context)?.readState(context);
    if (saved is (String, int, double) && _sections.isNotEmpty) {
      _restoring = true;
      final id = _sections.any((s) => s.id == saved.$1)
          ? saved.$1
          : _sections[saved.$2.clamp(0, _sections.length - 1)].id;
      _originId.value = id;
      _scroll.origin = saved.$3;
    }
  }

  @override
  void didUpdateWidget(SectionedChipScrollView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _sections;
    _sections = _visibleSections();
    final same = _sameSections(previous, _sections);
    if (widget.layout is! SectionedGridLayout ||
        !_sections.any((s) => s.id == _originId.value)) {
      final hadOrigin = _originId.value != null;
      _originId.value = null;
      _scroll.origin = 0;
      _scroll.leadingBound = null;
      _scroll.trailingBound = null;
      if (hadOrigin) {
        _geometry = null;
        _endPick = null;
        PageStorage.maybeOf(context)?.writeState(context, null);
        if (_scroll.hasClients) {
          (_scroll.position as _IndexedScrollPosition).resetOrigin();
        }
      }
    }
    final w = widget;
    final rangeChanged =
        !same ||
        w.layout != oldWidget.layout ||
        w.sectionDecoration != oldWidget.sectionDecoration ||
        w.sectionTitleStyle != oldWidget.sectionTitleStyle ||
        (w.onSectionTap == null) != (oldWidget.onSectionTap == null) ||
        w.config.showSectionChevron != oldWidget.config.showSectionChevron ||
        w.config.showEmptySections != oldWidget.config.showEmptySections;
    if (rangeChanged) {
      _cancelJump();
    }
    if (rangeChanged ||
        w.itemBuilder != oldWidget.itemBuilder ||
        w.style != oldWidget.style ||
        w.config != oldWidget.config) {
      _listCache = null;
    }
    // Parents often rebuild with an equal new list; only changed sections are
    // a data update that stops a jump and closes the (now stale) picker.
    if (same) return;
    _cancelJump();
    final panel = _panelRoute;
    if (panel != null) {
      // Removing a route during build is not allowed; do it after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (panel.isActive) panel.navigator?.removeRoute(panel);
      });
    }
    if (_sections.any((s) => s.id == _selectedId)) return;
    _selectedId = _sections.firstOrNull?.id;
    final selected = _selectedSection;
    if (selected != null && widget.onSectionSelected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedId == selected.id) {
          widget.onSectionSelected?.call(selected);
        }
      });
    }
  }

  @override
  void dispose() {
    _jumpToken++;
    _motion.dispose();
    _cacheExtent.dispose();
    _originId.dispose();
    _scroll.dispose();
    _chipScroll.dispose();
    super.dispose();
  }

  List<ChipSection<T>> _visibleSections() {
    final all = widget.sections;
    assert(
      uniqueIds(all.map((s) => s.id)),
      'ChipSection ids must be non-empty and unique.',
    );
    return widget.config.showEmptySections
        ? List.unmodifiable(all)
        : List.unmodifiable(all.where((s) => s.items.isNotEmpty));
  }

  static bool _sameSections<S>(List<ChipSection<S>> a, List<ChipSection<S>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].label != b[i].label ||
          !listEquals(a[i].items, b[i].items)) {
        return false;
      }
    }
    return true;
  }

  ChipSection<T>? get _selectedSection {
    for (final s in _sections) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  GlobalKey _key(Map<String, GlobalKey> keys, String id) =>
      keys.putIfAbsent(id, GlobalKey.new);

  /// Selects [id]; returns whether the selection changed.
  bool _select(String id) {
    if (_selectedId == id) return false;
    setState(() => _selectedId = id);
    final selected = _selectedSection;
    if (selected != null) widget.onSectionSelected?.call(selected);
    return true;
  }

  void _revealChip(String id) {
    final ctx = _chipKeys[id]?.currentContext;
    final chip = ctx?.findRenderObject();
    if (ctx == null || chip == null || !chip.attached) return;
    final position = _chipScroll.position;
    if (id == _sections.first.id) {
      position.jumpTo(position.minScrollExtent);
      return;
    }
    final box = chip as RenderBox;
    final start = RenderAbstractViewport.of(
      chip,
    ).getOffsetToReveal(chip, 0).offset;
    // Keep the chip clear of both edge fades (fade width = leading inset)
    // when the scroll range allows; otherwise keep it fully visible.
    final fade = widget.style.chipBarLeadingInset;
    final room = position.viewportDimension - box.size.width;
    final margin = room >= fade * 2
        ? (room - fade).clamp(fade, math.max(fade, 48.0))
        : room.clamp(0.0, fade);
    position.jumpTo(
      (start - margin).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Stops the running jump and gives scroll-spy back, for a jump that no
  /// new jump replaces (a drag or a data update).
  void _cancelJump() {
    _restoring = false;
    _jumpToken++;
    _targetId = null;
    _moving = false;
    _motion.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _targetId != null) return;
      _cacheExtent.value = null;
    });
  }

  Future<void> _jumpTo(String id) async {
    if (widget.layout is SectionedGridLayout &&
        (_originId.value != null ||
            _geometry?.sections.where((s) => s.id == id).firstOrNull?.top ==
                null)) {
      await _jumpIndexed(id);
      return;
    }
    _cancelJump();
    final token = ++_jumpToken;
    _targetId = id;
    _select(id);
    _revealChip(id);
    bool valid() => mounted && token == _jumpToken;
    try {
      // Move toward the measured prefix while the real renderer measures ahead.
      double? top;
      double preparedEnd = 0;
      double? movingTarget;
      while (valid()) {
        final geometry = _geometry;
        top = geometry?.sections.where((s) => s.id == id).firstOrNull?.top;
        preparedEnd = 0;
        if (geometry != null) {
          for (final section in geometry.sections) {
            if (section.top == null) break;
            preparedEnd =
                section.top! + section.insets.top + section.headerExtent;
            for (final row in section.rowExtents) {
              if (row == null) break;
              preparedEnd += row;
            }
            if (section.extent == null) break;
            preparedEnd = section.top! + section.extent!;
          }
        }
        final viewport = _scroll.position.viewportDimension;
        if (top != null &&
            (preparedEnd >= top + viewport || geometry?.extent != null)) {
          break;
        }
        final nextTarget = top == null
            ? preparedEnd
            : top + geometry!.sections.firstWhere((s) => s.id == id).insets.top;
        if (!mounted) return;
        if (!MediaQuery.disableAnimationsOf(context) &&
            nextTarget != movingTarget) {
          movingTarget = nextTarget;
          final velocity = _motion.isAnimating ? _motion.velocity : 0.0;
          _motion.value = _scroll.offset;
          _motion.animateWith(
            ScrollSpringSimulation(
              widget.style.spring(),
              _scroll.offset,
              nextTarget,
              velocity,
              tolerance: const Tolerance(distance: 0.1, velocity: 1),
            ),
          );
        }
        _cacheExtent.value = _scroll.offset.abs() + preparedEnd + viewport;
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return;
        // Row measurements enter the shared snapshot on the next frame.
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted || !valid() || top == null) return;
      // Retarget while earlier rows settle (slow devices / late height changes);
      // a one-shot spring to a stale top leaves the bar selected and the list
      // short or past the section (A1/A2). Stop growing cacheExtent so prepare
      // does not measure an unrelated suffix.
      _moving = true;
      _cacheExtent.value = null;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      var stableFrames = 0;
      while (valid()) {
        final geometry = _geometry;
        final section = geometry?.sections.where((s) => s.id == id).firstOrNull;
        final liveTop = section?.top;
        if (geometry == null || section == null || liveTop == null) {
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        preparedEnd = 0;
        for (final s in geometry.sections) {
          if (s.top == null) break;
          preparedEnd = s.top! + s.insets.top + s.headerExtent;
          for (final row in s.rowExtents) {
            if (row == null) break;
            preparedEnd += row;
          }
          if (s.extent == null) break;
          preparedEnd = s.top! + s.extent!;
        }
        final viewport = _scroll.position.viewportDimension;
        final maxScroll = (geometry.extent ?? preparedEnd) - viewport < 0
            ? 0.0
            : (geometry.extent ?? preparedEnd) - viewport;
        final target = (liveTop + section.insets.top).clamp(0.0, maxScroll);
        if (reduceMotion) {
          _scroll.jumpTo(target);
          break;
        }
        if (movingTarget != target) {
          movingTarget = target;
          stableFrames = 0;
          final velocity = _motion.isAnimating ? _motion.velocity : 0.0;
          _motion.value = _scroll.offset;
          _motion.animateWith(
            ScrollSpringSimulation(
              widget.style.spring(),
              _scroll.offset,
              target,
              velocity,
              tolerance: const Tolerance(distance: 0.1, velocity: 1),
            ),
          );
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return;
        final atRest =
            !_motion.isAnimating && (_scroll.offset - target).abs() < 0.5;
        if (atRest) {
          stableFrames++;
          if (stableFrames >= 2) break;
        } else {
          stableFrames = 0;
        }
      }
      if (!mounted || !valid()) return;
      _endPick = id;
      _targetId = null;
      _moving = false;
      _select(id);
      _revealChip(id);
      if (!mounted || !valid()) return;
      final section = _selectedSection;
      if (widget.config.focusAfterNavigate == FocusAfterNavigate.announce &&
          section != null) {
        announce(context, section.label);
      }
    } on TickerCanceled {
      // A new pointer, category or data revision owns navigation now.
    } finally {
      // A newer jump owns the paused scroll-spy; only the current one resumes.
      if (mounted && token == _jumpToken) {
        _cacheExtent.value = null;
        _targetId = null;
        _moving = false;
      }
    }
  }

  Future<void> _jumpIndexed(String id) async {
    _cancelJump();
    final token = ++_jumpToken;
    _targetId = id;
    final currentId = _geometry?.sectionAtOffset(_scroll.offset) ?? _selectedId;
    final currentIndex = _sections.indexWhere((s) => s.id == currentId);
    final targetIndex = _sections.indexWhere((s) => s.id == id);
    final direction = targetIndex < currentIndex ? -1.0 : 1.0;
    _select(id);
    _revealChip(id);
    bool valid() => mounted && token == _jumpToken;
    try {
      final viewport = _scroll.position.viewportDimension;
      final known = _geometry?.sections.where((s) => s.id == id).firstOrNull;
      if (known?.top == null) {
        // Rebase at the known index, so only the last viewport is traversed.
        _scroll.origin = _scroll.offset + direction * viewport * 2;
        _scroll.leadingBound = null;
        _scroll.trailingBound = null;
        _geometry = null;
        _originId.value = id;
        PageStorage.maybeOf(context)?.writeState(context, (
          id,
          _sections.indexWhere((s) => s.id == id),
          _scroll.origin,
        ));
        _scroll.jumpTo(_scroll.origin - direction * viewport);
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return;
      }
      _moving = true;
      double? movingTarget;
      var stableFrames = 0;
      while (valid()) {
        final section = _geometry?.sections
            .where((s) => s.id == id)
            .firstOrNull;
        final top = section?.top;
        if (top == null) {
          await WidgetsBinding.instance.endOfFrame;
          continue;
        }
        final target = (top + section!.insets.top).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );
        if (!mounted) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
          break;
        }
        if (movingTarget != target) {
          movingTarget = target;
          stableFrames = 0;
          final velocity = _motion.isAnimating ? _motion.velocity : 0.0;
          _motion.value = _scroll.offset;
          _motion.animateWith(
            ScrollSpringSimulation(
              widget.style.spring(),
              _scroll.offset,
              target,
              velocity,
              tolerance: const Tolerance(distance: 0.1, velocity: 1),
            ),
          );
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return;
        if (!_motion.isAnimating && (_scroll.offset - target).abs() < .5) {
          if (++stableFrames >= 2) break;
        } else {
          stableFrames = 0;
        }
      }
      if (!mounted || !valid()) return;
      _endPick = id;
      _targetId = null;
      _moving = false;
      _revealChip(id);
      final section = _selectedSection;
      if (widget.config.focusAfterNavigate == FocusAfterNavigate.announce &&
          section != null) {
        announce(context, section.label);
      }
    } on TickerCanceled {
      // A pointer, category or data revision owns navigation now.
    } finally {
      if (mounted && token == _jumpToken) {
        _targetId = null;
        _moving = false;
      }
    }
  }

  void _spy() {
    if (!mounted || _targetId != null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (_restoring) {
      // Restored short tails need the suffix dimensions before end selection.
      if (position.pixels < _scroll.origin && _scroll.trailingBound == null) {
        return;
      }
      if (_scroll.trailingBound != null &&
          (position.maxScrollExtent - _scroll.trailingBound!).abs() > .5) {
        return;
      }
      _restoring = false;
    }
    final scrollable =
        position.maxScrollExtent - position.minScrollExtent > 0.5;
    if (!scrollable) return;
    final atEnd =
        scrollable && position.pixels >= position.maxScrollExtent - 0.5;
    final current = _geometry?.sectionAtOffset(position.pixels);
    if (!atEnd && current != null) {
      _endPick = null;
      if (_select(current)) _revealChip(current);
      return;
    }
    final visible = [
      for (final s in _sections)
        if (_geometry?.sections
                .where((g) => g.id == s.id)
                .any(
                  (g) =>
                      g.top != null &&
                      g.top! < position.pixels + position.viewportDimension &&
                      g.top! + g.measuredExtent > position.pixels,
                ) ??
            false)
          s.id,
    ];
    if (visible.isEmpty) return;
    final String pick;
    if (!atEnd) {
      _endPick = null;
      pick = _geometry?.sectionAtOffset(position.pixels) ?? visible.first;
    } else {
      // At the end, a short section never reaches the top. A section the user
      // jumped to stays selected while visible; otherwise the last one wins.
      pick = visible.contains(_endPick) ? _endPick! : visible.last;
    }
    if (_select(pick)) _revealChip(pick);
  }

  // Any touch or wheel on the view takes over from a running jump: during the
  // jump animation Flutter ignores taps on the content, so a tap means "stop".
  // A chip tap cancels first and then starts its own jump.
  void _onPointerDown(PointerDownEvent _) => _cancelJump();

  void _onPointerSignal(PointerSignalEvent _) => _cancelJump();

  Future<void> _openPanel() async {
    _cancelJump();
    final sections = _sections;
    final selectedId = _selectedId;
    final route = pickerRoute(
      context,
      barrierLabel: widget.labels.barrier,
      maxTextScale: widget.config.maxTextScale,
      style: widget.style,
      anchor: () => _chipBarKey.currentContext == null
          ? null
          : pickerAnchor(_chipBarKey.currentContext!),
      bottomInset: widget.config.panelBottomInset,
      builder: (ctx) => _Panel<T>(
        sections: sections,
        selectedId: selectedId,
        labels: widget.labels,
        semantics: widget.config.chipSemantics,
        style: widget.style,
        chipTextStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
        selectedChipTextStyle:
            widget.selectedChipTextStyle ?? widget.style.selectedChipTextStyle,
        titleStyle: widget.panelTitleStyle ?? widget.style.panelTitleStyle,
        onPick: (id) {
          Navigator.of(ctx).pop();
          _jumpTo(id);
        },
      ),
    );
    _panelRoute = route;
    await Navigator.of(context).push(route);
    await route.completed;
    if (_panelRoute == route) _panelRoute = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_sections.isEmpty) return const SizedBox.shrink();
    final config = widget.config;
    // The chip bar sits outside the scroll view: Scrollable ignores pointers
    // on its content while it animates, which would swallow a chip tap that
    // arrives during a jump.
    final view = Listener(
      onPointerDown: _onPointerDown,
      onPointerSignal: _onPointerSignal,
      child: Column(
        children: [
          _chipBar(context),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _cachedList(config),
                AnimatedBuilder(
                  animation: _scroll,
                  builder: (context, _) =>
                      _scroll.hasClients &&
                          _scroll.offset > 0 &&
                          !MediaQuery.highContrastOf(context)
                      ? Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          // Keep the fade within the title's top padding.
                          height: widget.style.edgeFadeExtent.clamp(
                            0.0,
                            _SectionHeader.padding.top,
                          ),
                          child: IgnorePointer(
                            child: ClipRect(
                              child: ShaderMask(
                                blendMode: BlendMode.dstIn,
                                shaderCallback: (rect) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.black, Colors.transparent],
                                ).createShader(rect),
                                child: HeaderMaterial(
                                  style: widget.style,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return clampTextScale(config.maxTextScale, view);
  }

  Widget _cachedList(SectionedChipScrollConfig config) {
    final layout = widget.layout;
    if (layout is! SectionedGridLayout || layout is SectionedListLayout) {
      return _listCache ??= _list(config);
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width =
            box.maxWidth -
            (widget.sectionDecoration?.padding
                    .resolve(Directionality.of(context))
                    .horizontal ??
                0);
        final scaler = MediaQuery.textScalerOf(context);
        final columns =
            (widget.columnsBuilder ??
            layout.columnsBuilder ??
            SectionedGridLayout.defaultColumns)(width, scaler);
        final cachedLayout = _listCache?.layout;
        // A cached rule may differ at a new width even if the count is unchanged.
        if (_listColumns != columns ||
            (cachedLayout is SectionedGridLayout &&
                (cachedLayout.columnsBuilder ??
                        SectionedGridLayout.defaultColumns)(width, scaler) !=
                    columns)) {
          _listCache = null;
        }
        _listColumns = columns;
        return _listCache ??= _list(config);
      },
    );
  }

  _LayoutContent<T> _list(SectionedChipScrollConfig config) => _LayoutContent(
    sections: _sections,
    layout: widget.columnsBuilder == null
        ? widget.layout
        : switch (widget.layout) {
            SectionedGridLayout grid when grid is! SectionedListLayout =>
              grid.copyWith(columnsBuilder: widget.columnsBuilder),
            final layout => layout,
          },
    itemBuilder: widget.itemBuilder,
    headerStyle: widget.sectionTitleStyle ?? widget.style.sectionTitleStyle,
    showChevron: config.showSectionChevron,
    tappableHeader: widget.onSectionTap != null,
    sectionDecoration: widget.sectionDecoration,
    throughSectionId: () => _targetId,
    onRevision: _cancelJump,
    preparation: _cacheExtent,
    originId: _originId,
    controller: _scroll,
    onGeometry: (geometry) {
      _geometry = geometry;
      if (_originId.value != null) {
        _scroll.leadingBound = geometry.sections.first.top;
        final last = geometry.sections.last;
        _scroll.trailingBound = last.top == null || last.extent == null
            ? null
            : last.top! + last.extent! - _scroll.position.viewportDimension;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _spy());
    },
    sliverKey: (id) => _key(_sliverKeys, id),
    headerBuilder: (context, s) => _SectionHeader(
      key: _key(_headerKeys, s.id),
      label: s.label,
      showChevron: config.showSectionChevron,
      style: widget.sectionTitleStyle ?? widget.style.sectionTitleStyle,
      onTap: widget.onSectionTap == null ? null : () => widget.onSectionTap!(s),
    ),
    scrollBuilder: (slivers) => AnimatedBuilder(
      animation: Listenable.merge([_cacheExtent, _originId]),
      builder: (context, _) => CustomScrollView(
        key: const PageStorageKey<String>('sectioned_chip_scroll.list'),
        controller: _scroll,
        center: _originId.value == null
            ? null
            : ValueKey<String>(_originId.value!),
        cacheExtent: _cacheExtent.value,
        slivers: widget.layout is! SectionedGridLayout
            ? slivers
            : [
                for (var i = 0; i < slivers.length; i++)
                  _SectionOrigin(
                    key: ValueKey(_sections[i].id),
                    origin: _scroll.origin,
                    sliver: slivers[i],
                  ),
              ],
      ),
    ),
  );

  Widget _chipBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final config = widget.config;
        final count = _sections.length;
        final widths = [
          for (final section in _sections)
            [
              for (final selected in [false, true])
                chipNaturalWidth(
                  context,
                  section.label,
                  selected: selected,
                  style: widget.style,
                  textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
                  selectedTextStyle:
                      widget.selectedChipTextStyle ??
                      widget.style.selectedChipTextStyle,
                ),
            ].reduce((a, b) => a > b ? a : b),
        ];
        final fits =
            widths.fold<double>(0, (a, b) => a + b) + (count - 1) * 8 <=
            box.maxWidth - widget.style.chipBarLeadingInset;
        final showExpand = config.showExpandButton && !fits;
        final buttonSize = pickerButtonSize(
          context,
          chipMinimumHeight(
            context,
            widget.style,
            textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
            selectedTextStyle:
                widget.selectedChipTextStyle ??
                widget.style.selectedChipTextStyle,
          ),
        );
        final chipWidth = box.maxWidth - (showExpand ? buttonSize.width : 0);
        Widget chips = SingleChildScrollView(
          controller: _chipScroll,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.only(
            start: widget.style.chipBarLeadingInset,
          ),
          child: Row(
            spacing: 8,
            children: [
              for (var i = 0; i < count; i++)
                ChipControl(
                  maxWidth: (chipWidth - widget.style.chipBarLeadingInset)
                      .clamp(0.0, double.infinity),
                  key: _key(_chipKeys, _sections[i].id),
                  label: _sections[i].label,
                  semanticsLabel: widget.labels.position(
                    _sections[i].label,
                    i + 1,
                    count,
                  ),
                  selected: _sections[i].id == _selectedId,
                  semantics: config.chipSemantics,
                  style: widget.style,
                  textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
                  selectedTextStyle:
                      widget.selectedChipTextStyle ??
                      widget.style.selectedChipTextStyle,
                  onTap: () => _jumpTo(_sections[i].id),
                ),
            ],
          ),
        );
        if (config.chipSemantics == ChipSemantics.link) {
          chips = _navigation(chips);
        }
        if (config.showChipFade) {
          final direction = Directionality.of(context);
          chips = AnimatedBuilder(
            animation: _chipScroll,
            child: chips,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                // A replaced scroll view detaches after this frame's paint.
                final position = _chipScroll.positions.last;
                final fade = widget.style.chipBarLeadingInset;
                final t = rect.width <= 0
                    ? 0.0
                    : (fade / rect.width).clamp(0.0, 0.5);
                return LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [
                    position.pixels > 0 ? Colors.transparent : Colors.black,
                    Colors.black,
                    Colors.black,
                    position.extentAfter > 0
                        ? Colors.transparent
                        : Colors.black,
                  ],
                  stops: [0, t, 1 - t, 1],
                ).createShader(rect, textDirection: direction);
              },
              child: child,
            ),
          );
        }
        return HeaderMaterial(
          key: _chipBarKey,
          style: widget.style,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: chips,
                ),
              ),
              if (showExpand)
                SizedBox(
                  width: buttonSize.width,
                  height: buttonSize.height,
                  child: PressFeedback(
                    style: widget.style,
                    child: IconButton(
                      style: plainPickerButtonStyle,
                      iconSize: 16 * pickerChevronScale(context),
                      tooltip: widget.labels.expand,
                      icon: PickerChevron(
                        Icons.expand_more,
                        color: widget.style.pickerChevronColor,
                      ),
                      onPressed: _openPanel,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Widget _navigation(Widget child) => Semantics(
  role: SemanticsRole.navigation,
  container: true,
  explicitChildNodes: true,
  child: child,
);

/// Shared content-width chip used by section and category pickers.
class ChipControl extends StatelessWidget {
  /// Creates a bounded chip without outer spacing.
  const ChipControl({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.semantics,
    required this.onTap,
    this.textStyle,
    this.selectedTextStyle,
    required this.maxWidth,
    this.style = const SectionedChipScrollStyle.outlined(),
  });

  /// Visible label.
  final String label;

  /// Spoken label and position.
  final String semanticsLabel;

  /// Current selection.
  final bool selected;

  /// Accessible role.
  final ChipSemantics semantics;

  /// Activation callback.
  final VoidCallback onTap;

  /// Base label style.
  final TextStyle? textStyle;

  /// Selected label style.
  final TextStyle? selectedTextStyle;

  /// Available content width.
  final double maxWidth;

  /// Appearance values.
  final SectionedChipScrollStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = chipLabelStyle(
      theme,
      selected: selected,
      textStyle: textStyle,
      selectedTextStyle: selectedTextStyle,
    );
    return MergeSemantics(
      child: Semantics(
        role: semantics == ChipSemantics.tab ? SemanticsRole.tab : null,
        link: semantics == ChipSemantics.link,
        selected: selected,
        label: semanticsLabel,
        excludeSemantics: true,
        // A tab must have a tap action (asserted by Flutter 3.38), selected
        // or not.
        onTap: onTap,
        child: PressFeedback(
          style: style,
          child: SpringValue(
            value: selected ? 1 : 0,
            style: style,
            builder: (context, selection) {
              final surface = Theme.of(context).colorScheme.surface;
              final fill =
                  style.selectedChipBackground ??
                  Color.alphaBlend(
                    style.accentColor.withValues(
                      alpha: style.selectedFillOpacity,
                    ),
                    surface,
                  );
              final foreground = style.selectedForeground(fill);
              return Material(
                animationDuration: Duration.zero,
                color: Color.lerp(style.chipBackground, fill, selection),
                shape: style.chipShape.copyWith(
                  side: BorderSide(
                    width: style.selectedChipBorder?.width ?? 1,
                    color: Color.lerp(
                      theme.colorScheme.outlineVariant,
                      style.selectedChipBorder?.color ?? foreground,
                      selection,
                    )!,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: style.chipMinHeight,
                      maxWidth: maxWidth,
                    ),
                    child: Padding(
                      padding: style.chipPadding,
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: selected
                              ? labelStyle.copyWith(
                                  color: selectedTextStyle?.color ?? foreground,
                                )
                              : labelStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Natural width of a chip before the viewport cap is applied.
double chipNaturalWidth(
  BuildContext context,
  String label, {
  required bool selected,
  required SectionedChipScrollStyle style,
  TextStyle? textStyle,
  TextStyle? selectedTextStyle,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: chipLabelStyle(
        Theme.of(context),
        selected: selected,
        textStyle: textStyle,
        selectedTextStyle: selectedTextStyle,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width =
      painter.width +
      style.chipPadding.resolve(Directionality.of(context)).horizontal;
  painter.dispose();
  return width;
}

class _SectionHeader extends StatelessWidget {
  static const padding = EdgeInsetsDirectional.fromSTEB(12, 12, 12, 4);
  const _SectionHeader({
    super.key,
    required this.label,
    required this.showChevron,
    this.style,
    this.onTap,
  });

  final String label;
  final bool showChevron;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = scaledTitleStyle(
      context,
      (theme.textTheme.titleMedium ?? const TextStyle()).merge(style),
    );
    Widget content = Padding(
      padding: padding,
      child: Row(
        children: [
          Flexible(child: Text(label, style: textStyle)),
          if (showChevron)
            Icon(Icons.chevron_right, size: textStyle.fontSize ?? 16),
        ],
      ),
    );
    if (onTap != null) content = InkWell(onTap: onTap, child: content);
    if (onTap != null) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: content,
      );
    }
    // The chevron is decoration: excluded so the title is read once.
    return Semantics(
      container: true,
      header: true,
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: content,
    );
  }
}

class _IndexedScrollController extends ScrollController {
  double origin = 0;
  double? leadingBound;
  double? trailingBound;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _IndexedScrollPosition(this, physics, context, oldPosition);
}

class _IndexedScrollPosition extends ScrollPositionWithSingleContext {
  _IndexedScrollPosition(
    this.owner,
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) : super(physics: physics, context: context, oldPosition: oldPosition);
  final _IndexedScrollController owner;

  void resetOrigin() {
    // Build will replace the center sliver; old pixels use another coordinate system.
    correctPixels(0);
    saveScrollOffset();
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // The viewport reports dimensions relative to its center sliver.
    final min = owner.leadingBound ?? minScrollExtent + owner.origin;
    final max = owner.trailingBound ?? maxScrollExtent + owner.origin;
    return super.applyContentDimensions(min, max < min ? min : max);
  }
}

class _SectionOrigin extends SingleChildRenderObjectWidget {
  const _SectionOrigin({
    super.key,
    required this.origin,
    required Widget sliver,
  }) : super(child: sliver);
  final double origin;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSectionOrigin(origin);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSectionOrigin renderObject,
  ) {
    if (renderObject.origin != origin) {
      renderObject.origin = origin;
      renderObject.markNeedsLayout();
    }
  }
}

class _RenderSectionOrigin extends RenderProxySliver {
  _RenderSectionOrigin(this.origin);
  double origin;
  @override
  double get centerOffsetAdjustment => -origin;
}

// A navigation origin gives exact forward tops and exact backward suffixes,
// even when rows farther away from that origin have never been built.
class _AnchoredGeometry extends SectionedGeometry {
  _AnchoredGeometry(SectionedGeometry source, int index, double origin)
    : _source = source,
      _index = index,
      _origin = origin,
      super(_sections(source, index, origin));
  final SectionedGeometry _source;
  final int _index;
  final double _origin;

  static List<SectionedSectionGeometry> _sections(
    SectionedGeometry source,
    int index,
    double origin,
  ) {
    final tops = List<double?>.filled(source.sections.length, null);
    double? top = origin;
    for (var i = index; i < tops.length; i++) {
      tops[i] = top;
      final extent = source.sections[i].extent;
      top = top == null || extent == null ? null : top + extent;
    }
    top = origin;
    for (var i = index - 1; i >= 0; i--) {
      final extent = source.sections[i].extent;
      top = top == null || extent == null ? null : top - extent;
      tops[i] = top;
    }
    return [
      for (var i = 0; i < tops.length; i++)
        SectionedSectionGeometry(
          id: source.sections[i].id,
          top: tops[i],
          headerExtent: source.sections[i].headerExtent,
          rowExtents: source.sections[i].rowExtents,
          insets: source.sections[i].insets,
          columns: source.sections[i].columns,
        ),
    ];
  }

  @override
  String? sectionAtOffset(double offset) {
    if (!offset.isFinite) return null;
    if (offset >= _origin) return super.sectionAtOffset(offset);
    var end = _origin;
    for (var i = _index - 1; i >= 0; i--) {
      final section = _source.sections[i];
      var start = end - section.insets.bottom;
      for (final row in section.rowExtents.reversed) {
        if (row == null) {
          return offset >= start && offset < end ? section.id : null;
        }
        start -= row;
      }
      start -= section.headerExtent + section.insets.top;
      if (offset >= start && offset < end) return section.id;
      end = start;
    }
    return null;
  }
}

class _LayoutContent<T> extends StatefulWidget {
  const _LayoutContent({
    required this.sections,
    required this.layout,
    required this.itemBuilder,
    required this.headerBuilder,
    required this.headerStyle,
    required this.showChevron,
    required this.tappableHeader,
    required this.sectionDecoration,
    required this.sliverKey,
    required this.scrollBuilder,
    required this.onGeometry,
    required this.onRevision,
    required this.throughSectionId,
    required this.preparation,
    required this.controller,
    required this.originId,
  });

  final List<ChipSection<T>> sections;
  final SectionedLayout layout;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget Function(BuildContext, ChipSection<T>) headerBuilder;
  final TextStyle? headerStyle;
  final bool showChevron;
  final bool tappableHeader;
  final Decoration? sectionDecoration;
  final Key? Function(String) sliverKey;
  final Widget Function(List<Widget>) scrollBuilder;
  final ValueChanged<SectionedGeometry> onGeometry;
  final VoidCallback onRevision;
  final String? Function() throughSectionId;
  final ValueListenable<double?> preparation;
  final ScrollController controller;
  final ValueListenable<String?> originId;

  @override
  State<_LayoutContent<T>> createState() => _LayoutContentState<T>();
}

class _LayoutContentState<T> extends State<_LayoutContent<T>> {
  SectionedMeasurementHost? _host;
  (double, TextScaler, TextDirection, TextStyle, int?)? _dimensions;
  bool _scheduled = false;

  @override
  void didUpdateWidget(covariant _LayoutContent<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rangeChanged =
        !SectionedChipScrollViewState._sameSections(
          oldWidget.sections,
          widget.sections,
        ) ||
        oldWidget.layout != widget.layout ||
        oldWidget.sectionDecoration != widget.sectionDecoration ||
        oldWidget.showChevron != widget.showChevron ||
        oldWidget.tappableHeader != widget.tappableHeader ||
        oldWidget.headerStyle != widget.headerStyle;
    if (rangeChanged) {
      widget.onRevision();
      _host = null;
    }
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.preparation, widget.originId]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final headerStyle = scaledTitleStyle(
          context,
          (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).merge(
            widget.headerStyle,
          ),
        );
        final layout = widget.layout;
        final columns = layout is SectionedGridLayout
            ? (layout.columnsBuilder ?? SectionedGridLayout.defaultColumns)(
                box.maxWidth -
                    (widget.sectionDecoration?.padding
                            .resolve(direction)
                            .horizontal ??
                        0),
                scaler,
              )
            : null;
        final dimensions = (
          box.maxWidth,
          scaler,
          direction,
          headerStyle,
          columns,
        );
        if (_dimensions != dimensions) {
          if (_dimensions != null) widget.onRevision();
          _host = null;
        }
        _dimensions = dimensions;
        // Row height settles (fonts/images) must not cancel an in-flight jump:
        // on slow devices that left the bar selected while the list never moved.
        final host = _host ??= SectionedMeasurementHost(
          onChanged: _changed,
          onInvalidated: () {
            if (widget.throughSectionId() == null) widget.onRevision();
          },
        );
        final input = SectionedLayoutInput<T>(
          sections: widget.sections,
          crossAxisWidth: box.maxWidth,
          textScaler: scaler,
          textDirection: direction,
          headerStyle: headerStyle,
          showChevron: widget.showChevron,
          tappableHeader: widget.tappableHeader,
          itemBuilder: widget.itemBuilder,
          headerBuilder: widget.headerBuilder,
          sectionDecoration: widget.sectionDecoration,
          sliverKey: widget.sliverKey,
          measurementViewportStart:
              widget.preparation.value == null || !widget.controller.hasClients
              ? null
              : widget.controller.offset,
          measurementViewportExtent: box.maxHeight,
        );
        var geometry = widget.layout.prepare(
          input,
          host,
          throughSectionId: widget.throughSectionId(),
        );
        final originId = widget.originId.value;
        if (originId != null) {
          final origin = (widget.controller as _IndexedScrollController).origin;
          final index = geometry.sections.indexWhere((s) => s.id == originId);
          if (index >= 0) geometry = _AnchoredGeometry(geometry, index, origin);
        }
        widget.onGeometry(geometry);
        return widget.scrollBuilder(
          widget.layout.buildSlivers(context, input, geometry, host),
        );
      },
    ),
  );
}

class _Panel<T> extends StatelessWidget {
  const _Panel({
    required this.sections,
    required this.selectedId,
    required this.labels,
    required this.semantics,
    required this.onPick,
    this.chipTextStyle,
    this.selectedChipTextStyle,
    this.titleStyle,
    required this.style,
  });

  final List<ChipSection<T>> sections;
  final String? selectedId;
  final SectionedChipScrollLabels labels;
  final ChipSemantics semantics;
  final ValueChanged<String> onPick;
  final TextStyle? chipTextStyle;
  final TextStyle? selectedChipTextStyle;
  final TextStyle? titleStyle;
  final SectionedChipScrollStyle style;

  @override
  Widget build(BuildContext context) {
    final count = sections.length;
    final rowHeight = chipMinimumHeight(
      context,
      style,
      textStyle: chipTextStyle,
      selectedTextStyle: selectedChipTextStyle,
    );
    return PickerPanel(
      style: style,
      minimumBodyHeight: rowHeight + 16,
      buttonSize: pickerButtonSize(context, rowHeight),
      triggerRowHeight: (rowHeight + 8).clamp(48.0, double.infinity),
      title: labels.panelTitle,
      titleStyle: titleStyle,
      closeLabel: labels.collapse,
      closeIcon: Icons.expand_less,
      child: LayoutBuilder(
        builder: (context, box) {
          final grid = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < count; i++)
                ChipControl(
                  maxWidth: box.maxWidth,
                  label: sections[i].label,
                  semanticsLabel: labels.position(
                    sections[i].label,
                    i + 1,
                    count,
                  ),
                  selected: sections[i].id == selectedId,
                  semantics: semantics,
                  style: style,
                  textStyle: chipTextStyle,
                  selectedTextStyle: selectedChipTextStyle,
                  onTap: () => onPick(sections[i].id),
                ),
            ],
          );
          return semantics == ChipSemantics.link ? _navigation(grid) : grid;
        },
      ),
    );
  }
}
