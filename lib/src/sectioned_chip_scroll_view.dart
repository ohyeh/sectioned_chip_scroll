import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:sectioned_chip_scroll/src/chip_section.dart';
import 'package:sectioned_chip_scroll/src/common.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_config.dart';

/// Returns the number of item columns for the given width and text scale.
///
/// The result must be at least 1.
typedef SectionColumnsBuilder =
    int Function(double maxWidth, TextScaler textScaler);

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
  });

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
    var columns = textScaler.scale(14) / 14 >= 2 ? 2 : 3;
    // shortcut: 72 is a placeholder minimum cell width; measure real cells in the example before 1.0.
    while (columns > 1 && maxWidth / columns < 72) {
      columns--;
    }
    return columns;
  }

  @override
  State<SectionedChipScrollView<T>> createState() =>
      SectionedChipScrollViewState<T>();
}

/// State of [SectionedChipScrollView]. Not part of the supported API; it is
/// public only so that tests can read [lastJumpRetries].
class SectionedChipScrollViewState<T>
    extends State<SectionedChipScrollView<T>> {
  static const _maxRetries = 3;
  static const _tolerance = 1.0;

  final _scroll = ScrollController();
  // The chip bar position follows the selection; it must not take the list's
  // PageStorage slot.
  final _chipScroll = ScrollController(keepScrollOffset: false);
  late final _observer = SliverObserverController(controller: _scroll);
  final _chipBarKey = GlobalKey();
  final _sliverKeys = <String, GlobalKey>{};
  final _headerKeys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};

  List<ChipSection<T>> _sections = const [];
  String? _selectedId;
  int _jumpToken = 0;
  Route<void>? _panelRoute;
  Future<void>? _observerOp;
  String? _endPick;
  // The list reads only widget data, so a selection change (setState) reuses
  // it and rebuilds just the chip bar. Cleared when its inputs change.
  Widget? _listCache;
  int _lastJumpRetries = 0;

  /// Number of corrective jumps the last chip or picker jump needed.
  @visibleForTesting
  int get lastJumpRetries => _lastJumpRetries;

  @override
  void initState() {
    super.initState();
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
      final ctx =
          _sliverKeys[_selectedId]?.currentContext ??
          _sliverKeys.values.map((k) => k.currentContext).nonNulls.firstOrNull;
      if (!mounted || ctx == null) return;
      _observer.dispatchOnceObserve(sliverContext: ctx, isForce: true);
      final id = _selectedId;
      if (id != null) _revealChip(id);
    });
  }

  @override
  void didUpdateWidget(SectionedChipScrollView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _sections;
    _sections = _visibleSections();
    final same = _sameSections(previous, _sections);
    final w = widget;
    if (!same ||
        w.config != oldWidget.config ||
        w.itemBuilder != oldWidget.itemBuilder ||
        w.columnsBuilder != oldWidget.columnsBuilder ||
        w.sectionTitleStyle != oldWidget.sectionTitleStyle ||
        (w.onSectionTap == null) != (oldWidget.onSectionTap == null)) {
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
    // Only the chip bar scrolls. No animation: a Scrollable ignores taps on
    // its content while it animates, which would swallow a quick second tap.
    Scrollable.of(ctx).position.ensureVisible(chip, alignment: 0.5);
  }

  /// Distance from the bottom of the chip bar to the top of the section
  /// title; null while the title is not built.
  double? _offsetError(String id) {
    final header =
        _headerKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final bar = _chipBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (header == null || !header.attached || bar == null || !bar.attached) {
      return null;
    }
    return header.localToGlobal(Offset.zero).dy -
        bar.localToGlobal(Offset(0, bar.size.height)).dy;
  }

  /// Whether scrolling can bring a title [error] pixels closer to the bar.
  /// True for a title that is not built yet (null).
  bool _canMove(double? error) {
    if (error == null) return true;
    final p = _scroll.position;
    final target = (p.pixels + error).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    return (target - p.pixels).abs() >= 0.5;
  }

  /// Stops the running jump and gives scroll-spy back, for a jump that no
  /// new jump replaces (a drag or a data update).
  void _cancelJump() {
    _jumpToken++;
    _observer.isForbidObserveCallback = false;
  }

  /// Runs one observer scroll and remembers it, so the next jump can wait for
  /// it: an observer scroll cannot be cancelled and would fight a new one.
  Future<void> _observerScroll(Future<void> Function() scroll) {
    final future = scroll();
    _observerOp = future;
    return future;
  }

  Future<void> _jumpTo(String id) async {
    final token = ++_jumpToken;
    _observer.isForbidObserveCallback = true;
    _select(id);
    _revealChip(id);
    var retries = 0;
    var done = false;
    double? error;
    double? previousExtent;
    try {
      final pending = _observerOp;
      if (pending != null) {
        await pending;
        if (!mounted || token != _jumpToken) return;
      }
      // An observer scroll completes in a post-frame callback, so a scroll
      // that does not move schedules no frame and never completes. Call the
      // observer only when the list can move toward the title.
      if (_canMove(_offsetError(id))) {
        await _observerScroll(
          () => _observer.animateTo(
            sliverContext: _sliverKeys[id]?.currentContext,
            index: 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      }
      // The observer targets an estimated extent for sections that are not
      // laid out yet, so it can stop short. Measure, then jump again.
      while (true) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || token != _jumpToken) return;
        final position = _scroll.position;
        error = _offsetError(id);
        if (error != null && error.abs() < _tolerance) {
          done = true;
          break;
        }
        final canMove = _canMove(error);
        if (!canMove && previousExtent == position.maxScrollExtent) {
          // The list cannot move further (a short section at the end) and
          // its extent is settled: a stable end.
          done = true;
          break;
        }
        previousExtent = position.maxScrollExtent;
        if (retries == _maxRetries) break;
        retries++;
        // When it cannot move, the next frame shows whether the extent settled.
        if (canMove) {
          await _observerScroll(
            () => _observer.jumpTo(
              sliverContext: _sliverKeys[id]?.currentContext,
              index: 0,
            ),
          );
          if (!mounted || token != _jumpToken) return;
        }
      }
      // At the end the last visible section would win; keep this pick.
      if (done) {
        _endPick = id;
        final section = _selectedSection;
        if (mounted &&
            widget.config.focusAfterNavigate == FocusAfterNavigate.announce &&
            section != null &&
            section.id == id) {
          announce(context, section.label);
        }
      }
      if (!done) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError(
              'SectionedChipScrollView could not align section "$id" after '
              '$retries retries (offset error: '
              '${error?.toStringAsFixed(1) ?? 'unavailable'}, max extent: '
              '${_scroll.position.maxScrollExtent.toStringAsFixed(1)}).',
            ),
            library: 'sectioned_chip_scroll',
          ),
        );
      }
    } finally {
      _lastJumpRetries = retries;
      // A newer jump owns the paused scroll-spy; only the current one resumes.
      if (mounted && token == _jumpToken) {
        _observer.isForbidObserveCallback = false;
      }
    }
  }

  void _onObserveAll(Map<BuildContext, ObserveModel> result) {
    final position = _scroll.position;
    final scrollable =
        position.maxScrollExtent - position.minScrollExtent > 0.5;
    final atEnd =
        scrollable && position.pixels >= position.maxScrollExtent - 0.5;
    final visible = [
      for (final s in _sections)
        if (result[_sliverKeys[s.id]?.currentContext]
                ?.displayingChildIndexList
                .isNotEmpty ??
            false)
          s.id,
    ];
    if (visible.isEmpty) return;
    final String pick;
    if (!atEnd) {
      _endPick = null;
      pick = visible.first;
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
    final sections = _sections;
    final selectedId = _selectedId;
    final route = pickerRoute(
      context,
      barrierLabel: widget.labels.barrier,
      maxTextScale: widget.config.maxTextScale,
      builder: (ctx) => _Panel<T>(
        sections: sections,
        selectedId: selectedId,
        labels: widget.labels,
        semantics: widget.config.chipSemantics,
        columnsBuilder:
            widget.columnsBuilder ?? SectionedChipScrollView.defaultColumns,
        chipTextStyle: widget.chipTextStyle,
        selectedChipTextStyle: widget.selectedChipTextStyle,
        titleStyle: widget.panelTitleStyle,
        onPick: (id) {
          Navigator.of(ctx).pop();
          if (mounted) _jumpTo(id);
        },
      ),
    );
    _panelRoute = route;
    await Navigator.of(context).push(route);
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
          Expanded(child: _listCache ??= _list(config)),
        ],
      ),
    );
    return clampTextScale(config.maxTextScale, view);
  }

  Widget _list(SectionedChipScrollConfig config) => SliverViewObserver(
    controller: _observer,
    sliverContexts: () => [
      for (final s in _sections) ?_sliverKeys[s.id]?.currentContext,
    ],
    onObserveAll: _onObserveAll,
    child: CustomScrollView(
      key: const PageStorageKey<String>('sectioned_chip_scroll.list'),
      controller: _scroll,
      slivers: [
        for (final s in _sections)
          SliverList(
            key: _key(_sliverKeys, s.id),
            delegate: SliverChildBuilderDelegate(
              childCount: 2,
              (ctx, i) => i == 0
                  ? _SectionHeader(
                      key: _key(_headerKeys, s.id),
                      label: s.label,
                      showChevron: config.showSectionChevron,
                      style: widget.sectionTitleStyle,
                      onTap: widget.onSectionTap == null
                          ? null
                          : () => widget.onSectionTap!(s),
                    )
                  : _ItemRows<T>(
                      items: s.items,
                      itemBuilder: widget.itemBuilder,
                      columnsBuilder:
                          widget.columnsBuilder ??
                          SectionedChipScrollView.defaultColumns,
                    ),
            ),
          ),
      ],
    ),
  );

  Widget _chipBar(BuildContext context) {
    final config = widget.config;
    final count = _sections.length;
    Widget chips = SingleChildScrollView(
      controller: _chipScroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            _Chip(
              key: _key(_chipKeys, _sections[i].id),
              label: _sections[i].label,
              semanticsLabel: widget.labels.position(
                _sections[i].label,
                i + 1,
                count,
              ),
              selected: _sections[i].id == _selectedId,
              semantics: config.chipSemantics,
              textStyle: widget.chipTextStyle,
              selectedTextStyle: widget.selectedChipTextStyle,
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
      chips = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.85, 1],
        ).createShader(rect, textDirection: direction),
        child: chips,
      );
    }
    return Material(
      key: _chipBarKey,
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(child: chips),
          if (config.showExpandButton)
            IconButton(
              tooltip: widget.labels.expand,
              icon: const Icon(Icons.expand_more),
              onPressed: _openPanel,
            ),
        ],
      ),
    );
  }
}

Widget _navigation(Widget child) => Semantics(
  role: SemanticsRole.navigation,
  container: true,
  explicitChildNodes: true,
  child: child,
);

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.semantics,
    required this.onTap,
    this.textStyle,
    this.selectedTextStyle,
    this.expand = false,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final ChipSemantics semantics;
  final VoidCallback onTap;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = chipLabelStyle(
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
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 48,
                  maxWidth: expand ? double.infinity : 160,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
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
    final textStyle = (theme.textTheme.titleMedium ?? const TextStyle()).merge(
      style,
    );
    Widget content = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 4),
      child: Row(
        children: [
          Flexible(child: Text(label, style: textStyle)),
          if (showChevron)
            Icon(Icons.chevron_right, size: textStyle.fontSize ?? 16),
        ],
      ),
    );
    if (onTap != null) content = InkWell(onTap: onTap, child: content);
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

class _ItemRows<T> extends StatelessWidget {
  const _ItemRows({
    required this.items,
    required this.itemBuilder,
    required this.columnsBuilder,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final SectionColumnsBuilder columnsBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = columnsBuilder(
        box.maxWidth,
        MediaQuery.textScalerOf(context),
      );
      assert(columns >= 1, 'columnsBuilder must return at least 1');
      return Column(
        children: [
          for (var r = 0; r < items.length; r += columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = r; i < r + columns; i++)
                  Expanded(
                    child: i < items.length
                        ? itemBuilder(context, items[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      );
    },
  );
}

class _Panel<T> extends StatelessWidget {
  const _Panel({
    required this.sections,
    required this.selectedId,
    required this.labels,
    required this.semantics,
    required this.columnsBuilder,
    required this.onPick,
    this.chipTextStyle,
    this.selectedChipTextStyle,
    this.titleStyle,
  });

  final List<ChipSection<T>> sections;
  final String? selectedId;
  final SectionedChipScrollLabels labels;
  final ChipSemantics semantics;
  final SectionColumnsBuilder columnsBuilder;
  final ValueChanged<String> onPick;
  final TextStyle? chipTextStyle;
  final TextStyle? selectedChipTextStyle;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final count = sections.length;
    return PickerPanel(
      title: labels.panelTitle,
      titleStyle: titleStyle,
      closeLabel: labels.collapse,
      closeIcon: Icons.expand_less,
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = columnsBuilder(
            box.maxWidth,
            MediaQuery.textScalerOf(context),
          );
          final grid = Wrap(
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: box.maxWidth / columns,
                  child: _Chip(
                    label: sections[i].label,
                    semanticsLabel: labels.position(
                      sections[i].label,
                      i + 1,
                      count,
                    ),
                    selected: sections[i].id == selectedId,
                    semantics: semantics,
                    textStyle: chipTextStyle,
                    selectedTextStyle: selectedChipTextStyle,
                    expand: true,
                    onTap: () => onPick(sections[i].id),
                  ),
                ),
            ],
          );
          return semantics == ChipSemantics.link ? _navigation(grid) : grid;
        },
      ),
    );
  }
}
