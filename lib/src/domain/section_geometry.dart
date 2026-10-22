import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// One section's exact known geometry. Null means not measured yet.
@immutable
class SectionedSectionGeometry {
  /// Captures measured rows and the known prefix offset.
  SectionedSectionGeometry({
    required this.id,
    required this.top,
    required this.headerExtent,
    required List<double?> rowExtents,
    required this.insets,
    required this.columns,
  }) : rowExtents = List.unmodifiable(rowExtents);

  /// Stable section identity.
  final String id;

  /// Null when a preceding section has unknown height.
  final double? top;

  /// Header height including its padding.
  final double headerExtent;

  /// Maximum item height per row; null means unmeasured.
  final List<double?> rowExtents;

  /// Decoration padding.
  final EdgeInsets insets;

  /// Equally wide cells per row.
  final int columns;

  /// Exact measured prefix of this section, even while later rows are unknown.
  double get measuredExtent {
    var result = headerExtent + insets.top;
    for (final row in rowExtents) {
      if (row == null) return result;
      result += row;
    }
    return result + insets.bottom;
  }

  /// Header, rows and padding; null until all rows are measured.
  double? get extent => rowExtents.any((e) => e == null)
      ? null
      : headerExtent +
            insets.vertical +
            rowExtents.fold<double>(0, (sum, e) => sum + e!);
}

/// A snapshot shared by preparation and rendering. It never estimates offsets.
@immutable
class SectionedGeometry {
  /// Creates an immutable snapshot.
  SectionedGeometry(List<SectionedSectionGeometry> sections)
    : sections = List.unmodifiable(sections);

  /// Section ranges in display order.
  final List<SectionedSectionGeometry> sections;

  /// Exact content height; null while any range is unknown.
  double? get extent {
    if (sections.isEmpty) return 0;
    final last = sections.last;
    return last.top == null || last.extent == null
        ? null
        : last.top! + last.extent!;
  }

  /// Returns null for unknown ranges and offsets outside the content.
  String? sectionAtOffset(double offset) {
    if (!offset.isFinite) return null;
    final section = sections
        .where((s) => s.top != null && s.top! <= offset)
        .lastOrNull;
    if (section == null) return null;
    final top = section.top;
    final extent = section.extent;
    if (top == null) return null;
    if (extent == null) {
      return offset < top + section.measuredExtent ? section.id : null;
    }
    if (offset >= top && offset < top + extent) return section.id;
    return null;
  }
}

/// Stores measured row heights for one input revision; does not clone items.
class SectionedMeasurementHost {
  /// Creates a store for one input revision.
  SectionedMeasurementHost({this.onChanged, this.onInvalidated});

  /// Called when a row changes height.
  final VoidCallback? onChanged;

  /// Called when an already measured row changes, rather than becoming known.
  final VoidCallback? onInvalidated;
  final _rows = <(String, int), double>{};

  /// Last measured row height, or null.
  double? rowExtent(String sectionId, int row) => _rows[(sectionId, row)];

  /// Records a measured height, or an exact height from an app subclass.
  void recordRow(String sectionId, int row, double extent) {
    if (!extent.isFinite || extent < 0) {
      throw ArgumentError.value(extent, 'extent', 'Must be finite and >= 0');
    }
    if (_rows[(sectionId, row)] == extent) return;
    if (_rows.containsKey((sectionId, row))) onInvalidated?.call();
    _rows[(sectionId, row)] = extent;
    onChanged?.call();
  }
}
