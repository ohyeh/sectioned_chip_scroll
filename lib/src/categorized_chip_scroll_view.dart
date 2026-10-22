import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sectioned_chip_scroll/src/chip_section.dart';
import 'package:sectioned_chip_scroll/src/common.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_config.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_view.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_style.dart';
import 'package:sectioned_chip_scroll/src/sectioned_layout.dart';

/// Two levels: category tabs (level 1) that switch a
/// [SectionedChipScrollView] (level 2).
///
/// - Category tabs sit in a side rail at the start edge. When the rail would
///   leave too little width for the content, they move to
///   [CategorizedChipScrollConfig.railLargeTextLayout].
/// - With one category the tabs are hidden (unless
///   [CategorizedChipScrollConfig.showRailWhenSingle]) and the view is the
///   plain sections view.
/// - Tabs switch only when activated (tap, screen reader double tap, Enter
///   or Space). Moving focus over them does not switch.
/// - Keyboard: the tab list is one Tab stop on the selected tab; arrow keys
///   move between tabs; one Tab moves on to the content.
///
/// Give it bounded width and height, for example as the body of a
/// `Scaffold`.
class CategorizedChipScrollView<T> extends StatefulWidget {
  /// Creates the view.
  const CategorizedChipScrollView({
    super.key,
    required this.categories,
    required this.itemBuilder,
    this.layout = const SectionedLayout.list(),
    this.style = const SectionedChipScrollStyle.outlined(),
    this.sectionDecoration,
    this.railItemBuilder,
    this.config = const CategorizedChipScrollConfig(),
    this.labels = const SectionedChipScrollLabels(),
    this.onCategorySelected,
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

  /// The categories, in display order.
  final List<SectionCategory<T>> categories;

  /// See [SectionedChipScrollView.itemBuilder].
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Layout passed to the selected category's sections view.
  final SectionedLayout layout;

  /// Shared rail, chip and header values.
  final SectionedChipScrollStyle style;

  /// Decoration passed to the sections view.
  final Decoration? sectionDecoration;

  /// Visual only. The package owns semantics, focus and the tap target.
  final Widget Function(BuildContext, SectionCategory<T>, bool)?
  railItemBuilder;

  /// Product switches. See [CategorizedChipScrollConfig].
  final CategorizedChipScrollConfig config;

  /// Visible and spoken text, shared with the sections view.
  final SectionedChipScrollLabels labels;

  /// Called when the selected category changes, by activation or by a data
  /// update that removes the selected category.
  final ValueChanged<SectionCategory<T>>? onCategorySelected;

  /// See [SectionedChipScrollView.onSectionTap].
  final ValueChanged<ChipSection<T>>? onSectionTap;

  /// See [SectionedChipScrollView.onSectionSelected].
  final ValueChanged<ChipSection<T>>? onSectionSelected;

  /// See [SectionedChipScrollView.columnsBuilder].
  final SectionColumnsBuilder? columnsBuilder;

  /// See [SectionedChipScrollView.chipTextStyle]; also used for category
  /// tabs.
  final TextStyle? chipTextStyle;

  /// See [SectionedChipScrollView.selectedChipTextStyle]; also used for the
  /// selected category tab.
  final TextStyle? selectedChipTextStyle;

  /// See [SectionedChipScrollView.sectionTitleStyle].
  final TextStyle? sectionTitleStyle;

  /// See [SectionedChipScrollView.panelTitleStyle]; also used for the
  /// category picker title.
  final TextStyle? panelTitleStyle;

  @override
  State<CategorizedChipScrollView<T>> createState() =>
      _CategorizedChipScrollViewState<T>();
}

class _CategorizedChipScrollViewState<T>
    extends State<CategorizedChipScrollView<T>> {
  String? _categoryId;
  final _savedSection = <String, String>{};
  // Scroll offsets of this view only, keyed by category id. Without
  // keepCategoryState a switch starts a new bucket, so nothing is restored.
  var _bucket = PageStorageBucket();
  // Keep the sections view and the tabs across layout changes (rail, top
  // tabs, picker) by reparenting them.
  final _viewKey = GlobalKey();
  final _tabsKey = GlobalKey();
  final _categoryBarKey = GlobalKey();
  Route<void>? _pickerRoute;
  int _pickerRevision = 0;
  (Size, TextScaler, TextDirection)? _pickerEnvironment;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pickerRevision++;
  }

  @override
  void dispose() {
    _pickerRevision++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _assertIds();
    _categoryId = widget.categories.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(CategorizedChipScrollView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameCategories(oldWidget.categories, widget.categories) ||
        oldWidget.layout != widget.layout ||
        oldWidget.sectionDecoration != widget.sectionDecoration ||
        oldWidget.config != widget.config) {
      _pickerRevision++;
    }
    _assertIds();
    final picker = _pickerRoute;
    if (picker != null &&
        !_sameTitles(oldWidget.categories, widget.categories)) {
      // The open picker shows old rows; removing a route during build is not
      // allowed, so do it after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (picker.isActive) picker.navigator?.removeRoute(picker);
      });
    }
    final ids = {for (final c in widget.categories) c.id};
    _savedSection.removeWhere((id, _) => !ids.contains(id));
    final previous = _categoryId;
    if (ids.contains(previous)) return;
    _categoryId = widget.categories.firstOrNull?.id;
    final selected = _category;
    // Only a removed selection is a change; the first data after an empty
    // list is the initial selection, as on a first build with data.
    if (previous != null && selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _categoryId == selected.id) {
          widget.onCategorySelected?.call(selected);
        }
      });
    }
  }

  static bool _sameTitles<S>(
    List<SectionCategory<S>> a,
    List<SectionCategory<S>> b,
  ) =>
      a.length == b.length &&
      Iterable<int>.generate(
        a.length,
      ).every((i) => a[i].id == b[i].id && a[i].label == b[i].label);

  static bool _sameCategories<S>(
    List<SectionCategory<S>> a,
    List<SectionCategory<S>> b,
  ) {
    if (!_sameTitles(a, b)) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i].sections;
      final y = b[i].sections;
      if (x.length != y.length) return false;
      for (var j = 0; j < x.length; j++) {
        if (x[j].id != y[j].id ||
            x[j].label != y[j].label ||
            !listEquals(x[j].items, y[j].items)) {
          return false;
        }
      }
    }
    return true;
  }

  void _assertIds() {
    assert(
      uniqueIds(widget.categories.map((c) => c.id)),
      'SectionCategory ids must be non-empty and unique.',
    );
  }

  SectionCategory<T>? get _category {
    for (final c in widget.categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  void _activate(String id) {
    _pickerRevision++;
    final category = widget.categories.where((c) => c.id == id).firstOrNull;
    if (category == null || id == _categoryId) return;
    final keep = widget.config.keepCategoryState;
    setState(() {
      _categoryId = id;
      if (!keep) _bucket = PageStorageBucket();
    });
    widget.onCategorySelected?.call(category);
    // The new sections view starts on its saved or first section: a change
    // of the selected section.
    final show = widget.config.sectionConfig.showEmptySections;
    final visible = category.sections.where((s) => show || s.items.isNotEmpty);
    final saved = keep ? _savedSection[id] : null;
    final section =
        visible.where((s) => s.id == saved).firstOrNull ?? visible.firstOrNull;
    if (section != null) widget.onSectionSelected?.call(section);
    if (widget.config.sectionConfig.focusAfterNavigate ==
        FocusAfterNavigate.announce) {
      announce(context, category.label);
    }
  }

  Future<void> _openPicker(BuildContext context) async {
    final revision = ++_pickerRevision;
    final categories = widget.categories;
    final selectedId = _categoryId;
    String? picked;
    final route = pickerRoute(
      context,
      barrierLabel: widget.labels.categoryBarrier,
      maxTextScale: widget.config.sectionConfig.maxTextScale,
      style: widget.style,
      anchor: () => _categoryBarKey.currentContext == null
          ? null
          : pickerAnchor(_categoryBarKey.currentContext!),
      bottomInset: widget.config.sectionConfig.panelBottomInset,
      builder: (ctx) => _CategoryPanel(
        categories: categories,
        selectedIndex: categories.indexWhere((c) => c.id == selectedId),
        labels: widget.labels,
        style: widget.style,
        textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
        selectedTextStyle:
            widget.selectedChipTextStyle ?? widget.style.selectedChipTextStyle,
        titleStyle: widget.panelTitleStyle ?? widget.style.panelTitleStyle,
        onPick: (i) {
          picked = categories[i].id;
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pickerRoute = route;
    await Navigator.of(context).push(route);
    await route.completed;
    if (_pickerRoute == route) _pickerRoute = null;
    if (mounted && revision == _pickerRevision && picked != null) {
      _activate(picked!);
    }
  }

  Widget _sectionsView(SectionCategory<T> category) {
    final keep = widget.config.keepCategoryState;
    final id = category.id;
    return KeyedSubtree(
      key: _viewKey,
      child: PageStorage(
        bucket: _bucket,
        child: SectionedChipScrollView<T>(
          // A new key per category gives it its own state and stored offset.
          key: PageStorageKey<String>(id),
          sections: category.sections,
          initialSectionId: keep ? _savedSection[id] : null,
          itemBuilder: widget.itemBuilder,
          layout: widget.layout,
          style: widget.style,
          sectionDecoration: widget.sectionDecoration,
          config: widget.config.sectionConfig,
          labels: widget.labels,
          onSectionTap: widget.onSectionTap,
          onSectionSelected: (s) {
            _savedSection[id] = s.id;
            widget.onSectionSelected?.call(s);
          },
          columnsBuilder: widget.columnsBuilder,
          chipTextStyle: widget.chipTextStyle,
          selectedChipTextStyle: widget.selectedChipTextStyle,
          sectionTitleStyle: widget.sectionTitleStyle,
          panelTitleStyle: widget.panelTitleStyle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final environment = (
      MediaQuery.sizeOf(context),
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    if (_pickerEnvironment != environment) _pickerRevision++;
    _pickerEnvironment = environment;
    final category = _category;
    if (category == null) return const SizedBox.shrink();
    final config = widget.config;
    final content = _sectionsView(category);
    if (widget.categories.length == 1 && !config.showRailWhenSingle) {
      return content;
    }
    // Keyboard order is fixed by structure, not by geometry: category tabs
    // first, then the content, whatever row the selected tab is in.
    Widget ordered(double order, Widget child) => FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: FocusTraversalGroup(child: child),
    );
    final view = LayoutBuilder(
      builder: (context, box) {
        assert(
          box.hasBoundedWidth,
          'CategorizedChipScrollView needs a bounded width.',
        );
        // Scale like text, but read the factor at body size: nonlinear
        // scalers (Android 14+) barely grow a 96 px "font size".
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        // shortcut: 96 is a placeholder base width and 40% a placeholder
        // share; measure in the example before 1.0.
        final railWidth = config.railWidth ?? 96 * scale;
        final maxRail = box.maxWidth * 0.4;
        final layout = railWidth <= maxRail
            ? CategoryFallbackLayout.rail
            : config.railLargeTextLayout;
        final selectedIndex = widget.categories.indexOf(category);
        Widget tabs(Axis axis) => ordered(
          0,
          _CategoryTabs(
            key: _tabsKey,
            categories: widget.categories,
            selectedIndex: selectedIndex,
            axis: axis,
            labels: widget.labels,
            style: widget.style,
            visualBuilder: widget.railItemBuilder == null
                ? null
                : (context, index, selected) => widget.railItemBuilder!(
                    context,
                    widget.categories[index],
                    selected,
                  ),
            textStyle: widget.chipTextStyle ?? widget.style.chipTextStyle,
            selectedTextStyle:
                widget.selectedChipTextStyle ??
                widget.style.selectedChipTextStyle,
            onActivate: (i) => _activate(widget.categories[i].id),
          ),
        );
        final body = Expanded(child: ordered(1, content));
        return switch (layout) {
          CategoryFallbackLayout.rail => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: railWidth < maxRail ? railWidth : maxRail,
                child: tabs(Axis.vertical),
              ),
              body,
            ],
          ),
          CategoryFallbackLayout.topTabs => Column(
            children: [tabs(Axis.horizontal), body],
          ),
          CategoryFallbackLayout.picker => Column(
            children: [
              ordered(
                0,
                _CategoryButton(
                  key: _categoryBarKey,
                  scrollStyle: widget.style,
                  chipTextStyle:
                      widget.chipTextStyle ?? widget.style.chipTextStyle,
                  selectedChipTextStyle:
                      widget.selectedChipTextStyle ?? widget.style.selectedChipTextStyle,
                  label: category.label,
                  semanticsLabel: widget.labels.position(
                    category.label,
                    selectedIndex + 1,
                    widget.categories.length,
                  ),
                  hint: widget.labels.changeCategory,
                  textStyle:
                      widget.selectedChipTextStyle ??
                      widget.style.categoryTextStyle,
                  onTap: () => _openPicker(context),
                ),
              ),
              body,
            ],
          ),
        };
      },
    );
    return clampTextScale(
      config.sectionConfig.maxTextScale,
      FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: view),
    );
  }
}

/// Category tabs in a rail or a row, with one Tab stop (roving focus).
class _CategoryTabs extends StatefulWidget {
  const _CategoryTabs({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.axis,
    required this.labels,
    required this.onActivate,
    this.textStyle,
    this.selectedTextStyle,
    required this.style,
    this.visualBuilder,
  });

  final List<SectionCategory<Object?>> categories;
  final int selectedIndex;
  final Axis axis;
  final SectionedChipScrollLabels labels;
  final ValueChanged<int> onActivate;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final SectionedChipScrollStyle style;
  final Widget Function(BuildContext, int, bool)? visualBuilder;

  @override
  State<_CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<_CategoryTabs> {
  final _nodes = <String, FocusNode>{};
  // Id of the tab that owns the Tab stop; null means the selected tab. An id,
  // not an index, so a reorder keeps it on the same tab.
  String? _rovingId;

  @override
  void didUpdateWidget(_CategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final c in widget.categories) c.id};
    _nodes.removeWhere((id, node) {
      if (ids.contains(id)) return false;
      node.dispose();
      return true;
    });
    if (!ids.contains(_rovingId)) _rovingId = null;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _node(String id) => _nodes.putIfAbsent(id, FocusNode.new);

  int get _rovingIndex {
    final i = widget.categories.indexWhere((c) => c.id == _rovingId);
    return i < 0 ? widget.selectedIndex : i;
  }

  void _move(int delta) {
    final n = widget.categories.length;
    final next = (_rovingIndex + delta) % n;
    setState(() => _rovingId = widget.categories[next].id);
    final node = _node(widget.categories[next].id)..requestFocus();
    final ctx = node.context;
    final box = ctx?.findRenderObject();
    if (ctx != null && box != null) {
      Scrollable.of(ctx).position.ensureVisible(box, alignment: 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roving = _rovingIndex;
    final vertical = widget.axis == Axis.vertical;
    final n = widget.categories.length;
    final theme = Theme.of(context);
    final flip = !vertical && Directionality.of(context) == TextDirection.rtl;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // Leaving the list hands the Tab stop back to the selected tab.
      onFocusChange: (has) {
        if (!has && _rovingId != null) setState(() => _rovingId = null);
      },
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(
            vertical
                ? LogicalKeyboardKey.arrowDown
                : LogicalKeyboardKey.arrowRight,
          ): () =>
              _move(flip ? -1 : 1),
          SingleActivator(
            vertical
                ? LogicalKeyboardKey.arrowUp
                : LogicalKeyboardKey.arrowLeft,
          ): () =>
              _move(flip ? 1 : -1),
        },
        child: Material(
          color: vertical
              ? theme.colorScheme.surfaceContainerLow
              : theme.colorScheme.surface,
          child: SingleChildScrollView(
            scrollDirection: widget.axis,
            // The tab bar must be the direct parent of the tab nodes, inside the
            // scroll view's own node.
            child: Semantics(
              role: SemanticsRole.tabBar,
              container: true,
              explicitChildNodes: true,
              child: Flex(
                direction: widget.axis,
                crossAxisAlignment: vertical
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < n; i++)
                    _CategoryTab(
                      key: ValueKey(widget.categories[i].id),
                      label: widget.categories[i].label,
                      semanticsLabel: widget.labels.position(
                        widget.categories[i].label,
                        i + 1,
                        n,
                      ),
                      selected: i == widget.selectedIndex,
                      style: widget.style,
                      visual: widget.visualBuilder?.call(
                        context,
                        i,
                        i == widget.selectedIndex,
                      ),
                      focusNode: _node(widget.categories[i].id)
                        ..skipTraversal = i != roving,
                      vertical: vertical,
                      textStyle: widget.textStyle,
                      selectedTextStyle: widget.selectedTextStyle,
                      onTap: () {
                        setState(() => _rovingId = null);
                        widget.onActivate(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.vertical,
    required this.onTap,
    this.focusNode,
    this.textStyle,
    this.selectedTextStyle,
    this.style = const SectionedChipScrollStyle.outlined(),
    this.visual,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final FocusNode? focusNode;

  final bool vertical;
  final VoidCallback onTap;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final SectionedChipScrollStyle style;
  final Widget? visual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: selected,
        label: semanticsLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: PressFeedback(
            style: style,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                focusNode: focusNode,
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 48,
                    maxWidth: vertical ? double.infinity : 160,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: vertical
                          ? AlignmentDirectional.centerStart
                          : Alignment.center,
                      widthFactor: vertical ? null : 1,
                      child: visual == null
                          ? Text(
                              label,
                              textAlign: vertical
                                  ? TextAlign.start
                                  : TextAlign.center,
                              style: chipLabelStyle(
                                theme,
                                selected: selected,
                                textStyle: textStyle,
                                selectedTextStyle: TextStyle(
                                  color: style.selectedForeground(
                                    theme.colorScheme.surface,
                                  ),
                                ).merge(selectedTextStyle),
                              ),
                            )
                          : ExcludeSemantics(
                              child: ExcludeFocus(
                                child: IgnorePointer(child: visual!),
                              ),
                            ),
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

/// The current category as one button; it opens the category picker.
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.hint,
    required this.onTap,
    this.textStyle,
    required this.scrollStyle,
    required this.chipTextStyle,
    required this.selectedChipTextStyle,
  });

  final String label;
  final String semanticsLabel;
  final String hint;
  final VoidCallback onTap;
  final TextStyle? textStyle;
  final SectionedChipScrollStyle scrollStyle;
  final TextStyle? chipTextStyle;
  final TextStyle? selectedChipTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = scaledTitleStyle(
      context,
      (theme.textTheme.titleSmall ?? const TextStyle()).merge(textStyle),
    );
    final buttonSize = pickerButtonSize(
      context,
      chipMinimumHeight(
        context, scrollStyle,
        textStyle: chipTextStyle,
        selectedTextStyle: selectedChipTextStyle,
      ),
    );
    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: HeaderMaterial(
        style: scrollStyle,
        child: PressFeedback(
          style: scrollStyle,
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.zero,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // A different icon from the chip bar's expand button.
                    SizedBox(
                      width: buttonSize.width,
                      height: buttonSize.height,
                      child: IconButton(
                        style: plainPickerButtonStyle,
                        tooltip: hint,
                        icon: const Icon(Icons.unfold_more),
                        onPressed: onTap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({
    required this.categories,
    required this.selectedIndex,
    required this.labels,
    required this.onPick,
    this.textStyle,
    this.selectedTextStyle,
    this.titleStyle,
    required this.style,
  });

  final List<SectionCategory<Object?>> categories;
  final int selectedIndex;
  final SectionedChipScrollLabels labels;
  final ValueChanged<int> onPick;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final TextStyle? titleStyle;
  final SectionedChipScrollStyle style;

  @override
  Widget build(BuildContext context) {
    final n = categories.length;
    final rowHeight = chipMinimumHeight(
      context, style,
      textStyle: textStyle,
      selectedTextStyle: selectedTextStyle,
    );
    return PickerPanel(
      style: style,
      minimumBodyHeight: rowHeight + 16,
      buttonSize: pickerButtonSize(context, rowHeight),
      title: labels.categoryPanelTitle,
      titleStyle: titleStyle,
      closeLabel: labels.collapse,
      closeIcon: Icons.expand_less,
      child: LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < n; i++)
              ChipControl(
                maxWidth: box.maxWidth,
                label: categories[i].label,
                semanticsLabel: labels.position(categories[i].label, i + 1, n),
                selected: i == selectedIndex,
                style: style,
                semantics: ChipSemantics.link,
                textStyle: textStyle,
                selectedTextStyle: selectedTextStyle,
                onTap: () => onPick(i),
              ),
          ],
        ),
      ),
    );
  }
}
