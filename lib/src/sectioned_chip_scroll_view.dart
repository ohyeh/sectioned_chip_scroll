import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sectioned_chip_scroll/src/chip_section.dart';
import 'package:sectioned_chip_scroll/src/common.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_config.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_style.dart';
import 'package:sectioned_chip_scroll/src/sectioned_layout.dart';

export 'sectioned_layout.dart' show SectionColumnsBuilder;

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
    this.layout = const SectionedLayout.grid(),
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
  final _scroll = ScrollController();
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
  Widget? _listCache;
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
  void didUpdateWidget(SectionedChipScrollView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _sections;
    _sections = _visibleSections();
    final same = _sameSections(previous, _sections);
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
        w.columnsBuilder != oldWidget.columnsBuilder ||
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
    if (_targetId != null) return;
    final ctx = _chipKeys[id]?.currentContext;
    final chip = ctx?.findRenderObject();
    if (ctx == null || chip == null || !chip.attached) return;
    final position = _chipScroll.position;
    final box = chip as RenderBox;
    final start = RenderAbstractViewport.of(
      chip,
    ).getOffsetToReveal(chip, 0).offset;
    final margin = (position.viewportDimension - box.size.width).clamp(
      0.0,
      48.0,
    );
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
    _cancelJump();
    final token = ++_jumpToken;
    _targetId = id;
    bool valid() => mounted && token == _jumpToken;
    try {
      // Grow the real renderer's cache through the measured prefix. This is
      // preparation only: no scroll writes, cloned tiles or corrective moves.
      double? top;
      double preparedEnd = 0;
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
        _cacheExtent.value = _scroll.offset.abs() + preparedEnd + viewport;
        await WidgetsBinding.instance.endOfFrame;
        if (!valid()) return;
        // Row measurements enter the shared snapshot on the next frame.
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted || !valid() || top == null) return;
      final geometrySection = _geometry!.sections.firstWhere((s) => s.id == id);
      // The built-in title has 12px top padding inside the section header.
      final target = (top + geometrySection.insets.top + 12).clamp(
        0.0,
        (_geometry?.extent ?? preparedEnd) -
                    _scroll.position.viewportDimension <
                0
            ? 0.0
            : (_geometry?.extent ?? preparedEnd) -
                  _scroll.position.viewportDimension,
      );
      _cacheExtent.value = null;
      _moving = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _motion.value = _scroll.offset;
        await _motion
            .animateWith(
              ScrollSpringSimulation(
                widget.style.spring(),
                _scroll.offset,
                target,
                0,
                tolerance: const Tolerance(distance: 0.1, velocity: 1),
              ),
            )
            .orCancel;
      }
      if (!mounted || !valid()) return;
      _endPick = id;
      _targetId = null;
      _moving = false;
      _select(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && valid()) _revealChip(id);
      });
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

  void _spy() {
    if (!mounted || _targetId != null || !_scroll.hasClients) return;
    final position = _scroll.position;
    final scrollable =
        position.maxScrollExtent - position.minScrollExtent > 0.5;
    if (!scrollable) return;
    final atEnd =
        scrollable && position.pixels >= position.maxScrollExtent - 0.5;
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
    final token = _jumpToken;
    final sections = _sections;
    final selectedId = _selectedId;
    String? picked;
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
          picked = id;
          Navigator.of(ctx).pop();
        },
      ),
    );
    _panelRoute = route;
    await Navigator.of(context).push(route);
    await route.completed;
    if (_panelRoute == route) _panelRoute = null;
    if (mounted &&
        token == _jumpToken &&
        picked != null &&
        _sections.any((s) => s.id == picked)) {
      _jumpTo(picked!);
    }
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
                _listCache ??= _list(config),
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
                          height: widget.style.edgeFadeExtent,
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

  Widget _list(SectionedChipScrollConfig config) => _LayoutContent<T>(
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
    controller: _scroll,
    onGeometry: (geometry) {
      _geometry = geometry;
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
      animation: _cacheExtent,
      builder: (context, _) => CustomScrollView(
        key: const PageStorageKey<String>('sectioned_chip_scroll.list'),
        controller: _scroll,
        cacheExtent: _cacheExtent.value,
        slivers: slivers,
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
            chipNaturalWidth(
              context,
              section.label,
              selected: section.id == _selectedId,
              style: widget.style,
              textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
              selectedTextStyle:
                  widget.selectedChipTextStyle ??
                  widget.style.selectedChipTextStyle,
            ),
        ];
        final fits =
            widths.fold<double>(0, (a, b) => a + b) + (count - 1) * 8 <=
            box.maxWidth;
        final showExpand = config.showExpandButton && !fits;
        final chipWidth = box.maxWidth - (showExpand ? 48 : 0);
        Widget chips = SingleChildScrollView(
          controller: _chipScroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              for (var i = 0; i < count; i++)
                ChipControl(
                  maxWidth: chipWidth,
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
        return HeaderMaterial(
          key: _chipBarKey,
          style: widget.style,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: chips,
                ),
              ),
              if (showExpand)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: PressFeedback(
                    style: widget.style,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        splashFactory: NoSplash.splashFactory,
                      ),
                      tooltip: widget.labels.expand,
                      icon: const Icon(Icons.expand_more),
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

  @override
  State<_LayoutContent<T>> createState() => _LayoutContentState<T>();
}

class _LayoutContentState<T> extends State<_LayoutContent<T>> {
  SectionedMeasurementHost? _host;
  (double, TextScaler, TextDirection, TextStyle)? _dimensions;
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
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
    valueListenable: widget.preparation,
    builder: (context, preparation, _) => LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final headerStyle = scaledTitleStyle(
          context,
          (Theme.of(context).textTheme.titleMedium ?? const TextStyle()).merge(
            widget.headerStyle,
          ),
        );
        final dimensions = (box.maxWidth, scaler, direction, headerStyle);
        if (_dimensions != dimensions) {
          if (_dimensions != null) widget.onRevision();
          _host = null;
        }
        _dimensions = dimensions;
        final host = _host ??= SectionedMeasurementHost(
          onChanged: _changed,
          onInvalidated: widget.onRevision,
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
              preparation == null || !widget.controller.hasClients
              ? null
              : widget.controller.offset,
          measurementViewportExtent: box.maxHeight,
        );
        final geometry = widget.layout.prepare(
          input,
          host,
          throughSectionId: widget.throughSectionId(),
        );
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
    return PickerPanel(
      style: style,
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
