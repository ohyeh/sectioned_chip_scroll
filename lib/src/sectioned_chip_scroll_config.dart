import 'package:flutter/foundation.dart';

/// How screen readers expose a chip.
///
/// On iOS and Android, Flutter 3.38 sends only the selected flag and the label
/// to the platform for both values; the difference is visible on the web and
/// in the semantics tree.
enum ChipSemantics {
  /// Each chip is a tab.
  tab,

  /// Each chip is a link, and the chip bar is a navigation landmark. This is
  /// the usual scroll-spy pattern: a chip moves to a section, it does not
  /// switch a panel.
  link,
}

/// What happens for screen reader users after a chip jump or a category
/// switch completes.
enum FocusAfterNavigate {
  /// Focus stays on the activated chip or tab; only its selected state
  /// changes.
  preserve,

  /// Like [preserve], and the name of the new section or category is
  /// announced once, on platforms that support announcements.
  announce,
}

/// Switches for behavior that differs between products.
///
/// Every field has a default, so `const SectionedChipScrollConfig()` works.
@immutable
class SectionedChipScrollConfig {
  /// Creates a configuration.
  ///
  /// [maxTextScale], when not null, must be a positive finite number.
  const SectionedChipScrollConfig({
    this.chipSemantics = ChipSemantics.link,
    this.showExpandButton = true,
    this.showSectionChevron = false,
    this.showEmptySections = false,
    this.showChipFade = true,
    this.maxTextScale,
    this.focusAfterNavigate = FocusAfterNavigate.preserve,
  }) : assert(
         maxTextScale == null ||
             (maxTextScale > 0 && maxTextScale < double.infinity),
         'maxTextScale must be a positive finite number',
       );

  /// How screen readers expose each chip.
  final ChipSemantics chipSemantics;

  /// Shows the button at the end of the chip bar that opens a picker with
  /// every section.
  final bool showExpandButton;

  /// Shows a chevron after each section title.
  ///
  /// This only changes the look. A title is tappable only when
  /// `SectionedChipScrollView.onSectionTap` is set; a chevron without an
  /// action can make users expect one.
  final bool showSectionChevron;

  /// Shows sections whose `items` list is empty, as a chip and a title.
  ///
  /// When false, empty sections are left out of the chip bar, the picker and
  /// the list.
  final bool showEmptySections;

  /// Fades the trailing edge of the chip bar to show that it scrolls.
  final bool showChipFade;

  /// Upper limit for the text scale inside the view and its picker.
  ///
  /// Null leaves the inherited `TextScaler` unchanged.
  final double? maxTextScale;

  /// What happens after a chip jump completes. `CategorizedChipScrollView`
  /// uses the same value for category switches.
  final FocusAfterNavigate focusAfterNavigate;

  /// Returns a copy with the given fields replaced.
  ///
  /// [maxTextScale] takes a getter so that it can be cleared:
  /// `copyWith(maxTextScale: () => null)`.
  SectionedChipScrollConfig copyWith({
    ChipSemantics? chipSemantics,
    bool? showExpandButton,
    bool? showSectionChevron,
    bool? showEmptySections,
    bool? showChipFade,
    ValueGetter<double?>? maxTextScale,
    FocusAfterNavigate? focusAfterNavigate,
  }) => SectionedChipScrollConfig(
    chipSemantics: chipSemantics ?? this.chipSemantics,
    showExpandButton: showExpandButton ?? this.showExpandButton,
    showSectionChevron: showSectionChevron ?? this.showSectionChevron,
    showEmptySections: showEmptySections ?? this.showEmptySections,
    showChipFade: showChipFade ?? this.showChipFade,
    maxTextScale: maxTextScale != null ? maxTextScale() : this.maxTextScale,
    focusAfterNavigate: focusAfterNavigate ?? this.focusAfterNavigate,
  );

  @override
  bool operator ==(Object other) =>
      other is SectionedChipScrollConfig &&
      other.chipSemantics == chipSemantics &&
      other.showExpandButton == showExpandButton &&
      other.showSectionChevron == showSectionChevron &&
      other.showEmptySections == showEmptySections &&
      other.showChipFade == showChipFade &&
      other.maxTextScale == maxTextScale &&
      other.focusAfterNavigate == focusAfterNavigate;

  @override
  int get hashCode => Object.hash(
    chipSemantics,
    showExpandButton,
    showSectionChevron,
    showEmptySections,
    showChipFade,
    maxTextScale,
    focusAfterNavigate,
  );
}

/// Where the category tabs go when a side rail does not fit.
enum CategoryFallbackLayout {
  /// One button with the current category name; it opens a category picker.
  picker,

  /// A horizontal row of category tabs above the chip bar.
  topTabs,

  /// Keep the side rail; category names wrap.
  rail,
}

/// Switches for `CategorizedChipScrollView`.
@immutable
class CategorizedChipScrollConfig {
  /// Creates a configuration.
  ///
  /// [railWidth], when not null, must be positive.
  const CategorizedChipScrollConfig({
    this.sectionConfig = const SectionedChipScrollConfig(),
    this.showRailWhenSingle = false,
    this.railWidth,
    this.railLargeTextLayout = CategoryFallbackLayout.picker,
    this.keepCategoryState = true,
  }) : assert(railWidth == null || railWidth > 0, 'railWidth must be positive');

  /// Configuration of the sections view of each category.
  final SectionedChipScrollConfig sectionConfig;

  /// Shows the category tabs when there is only one category.
  final bool showRailWhenSingle;

  /// Width of the side rail. When null, it follows the text scale.
  final double? railWidth;

  /// Layout used when the side rail would leave too little width for the
  /// content, for example at large text sizes on a narrow screen.
  final CategoryFallbackLayout railLargeTextLayout;

  /// When true, coming back to a category restores its selected section and
  /// scroll position. When false, it starts at the first section.
  final bool keepCategoryState;

  /// Returns a copy with the given fields replaced.
  ///
  /// [railWidth] takes a getter so that it can be cleared.
  CategorizedChipScrollConfig copyWith({
    SectionedChipScrollConfig? sectionConfig,
    bool? showRailWhenSingle,
    ValueGetter<double?>? railWidth,
    CategoryFallbackLayout? railLargeTextLayout,
    bool? keepCategoryState,
  }) => CategorizedChipScrollConfig(
    sectionConfig: sectionConfig ?? this.sectionConfig,
    showRailWhenSingle: showRailWhenSingle ?? this.showRailWhenSingle,
    railWidth: railWidth != null ? railWidth() : this.railWidth,
    railLargeTextLayout: railLargeTextLayout ?? this.railLargeTextLayout,
    keepCategoryState: keepCategoryState ?? this.keepCategoryState,
  );

  @override
  bool operator ==(Object other) =>
      other is CategorizedChipScrollConfig &&
      other.sectionConfig == sectionConfig &&
      other.showRailWhenSingle == showRailWhenSingle &&
      other.railWidth == railWidth &&
      other.railLargeTextLayout == railLargeTextLayout &&
      other.keepCategoryState == keepCategoryState;

  @override
  int get hashCode => Object.hash(
    sectionConfig,
    showRailWhenSingle,
    railWidth,
    railLargeTextLayout,
    keepCategoryState,
  );
}

/// Builds the screen reader label of a chip.
///
/// [oneBasedIndex] runs from 1 to [count].
typedef SectionPositionLabel =
    String Function(String label, int oneBasedIndex, int count);

/// The default [SectionPositionLabel]: `'Fruit, 2 of 5'`.
String defaultSectionPositionLabel(
  String label,
  int oneBasedIndex,
  int count,
) => '$label, $oneBasedIndex of $count';

/// Text that the view shows or reads out. Defaults are English.
@immutable
class SectionedChipScrollLabels {
  /// Creates labels.
  const SectionedChipScrollLabels({
    this.expand = 'Show all sections',
    this.collapse = 'Close',
    this.barrier = 'Dismiss section picker',
    this.panelTitle = 'Sections',
    this.position = defaultSectionPositionLabel,
    this.changeCategory = 'Change category',
    this.categoryPanelTitle = 'Categories',
    this.categoryBarrier = 'Dismiss category picker',
  });

  /// Screen reader hint of the current-category button.
  final String changeCategory;

  /// Title of the category picker.
  final String categoryPanelTitle;

  /// Screen reader label of the dimmed area behind the category picker.
  final String categoryBarrier;

  /// Tooltip and screen reader label of the button that opens the picker.
  final String expand;

  /// Tooltip and screen reader label of the button that closes the picker.
  final String collapse;

  /// Screen reader label of the dimmed area behind the picker.
  final String barrier;

  /// Title of the picker.
  final String panelTitle;

  /// Screen reader label of each chip, with its position.
  final SectionPositionLabel position;
}
