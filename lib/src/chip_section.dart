import 'package:flutter/foundation.dart';

/// One section: a chip in the bar and a block of items in the list.
///
/// [id] identifies the section across data updates. It must be non-empty and
/// unique within one list of sections, and it must stay the same when the
/// sections are reordered or refreshed. The view keeps the selection and its
/// internal keys by [id], never by position.
@immutable
class ChipSection<T> {
  /// Creates a section.
  const ChipSection({
    required this.id,
    required this.label,
    required this.items,
  });

  /// Stable, unique identity of the section.
  final String id;

  /// Text shown on the chip and as the section title.
  final String label;

  /// Items shown in this section, in this order.
  final List<T> items;
}

/// One level-1 category: a tab that switches the sections below it.
///
/// [id] follows the same rules as [ChipSection.id]: non-empty, unique among
/// the categories, and stable across data updates. Section ids only need to
/// be unique within one category.
@immutable
class SectionCategory<T> {
  /// Creates a category.
  const SectionCategory({
    required this.id,
    required this.label,
    required this.sections,
  });

  /// Stable, unique identity of the category.
  final String id;

  /// Text shown on the category tab.
  final String label;

  /// Sections shown when this category is selected.
  final List<ChipSection<T>> sections;
}
