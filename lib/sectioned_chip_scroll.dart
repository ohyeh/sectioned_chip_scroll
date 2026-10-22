/// A scroll-spy chip bar for sectioned content.
///
/// See [SectionedChipScrollView] for the entry point.
library;

export 'src/application/sectioned_chip_scroll_config.dart';
export 'src/domain/chip_section.dart' hide uniqueIds;
export 'src/domain/section_geometry.dart';
export 'src/presentation/categorized_chip_scroll_view.dart';
export 'src/presentation/sectioned_chip_scroll_style.dart';
export 'src/presentation/sectioned_chip_scroll_view.dart'
    hide ChipControl, chipNaturalWidth;
export 'src/presentation/sectioned_layout.dart';
