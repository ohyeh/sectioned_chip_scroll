import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sectioned_chip_scroll/src/domain/chip_section.dart';
import 'package:sectioned_chip_scroll/src/domain/section_geometry.dart';

/// Returns at least one column for the available width and text scale.
typedef SectionColumnsBuilder =
    int Function(double maxWidth, TextScaler textScaler);

/// Immutable inputs for one layout revision, in content-scroll coordinates.
class SectionedLayoutInput<T> {
  /// Captures section data and the rendering environment.
  SectionedLayoutInput({
    required List<ChipSection<T>> sections,
    required this.crossAxisWidth,
    required this.textScaler,
    required this.headerStyle,
    required this.textDirection,
    required this.itemBuilder,
    required this.headerBuilder,
    this.showChevron = true,
    this.tappableHeader = false,
    this.sectionDecoration,
    this.sliverKey,
    this.measurementViewportStart,
    this.measurementViewportExtent = 0,
  }) : sections = List.unmodifiable(sections);

  /// Sections in display order.
  final List<ChipSection<T>> sections;

  /// Available width before decoration padding.
  final double crossAxisWidth;

  /// Current text scaler.
  final TextScaler textScaler;

  /// Resolved header style shared with the renderer.
  final TextStyle headerStyle;

  /// Direction for text and decoration padding.
  final TextDirection textDirection;

  /// Whether headers reserve a chevron.
  final bool showChevron;

  /// Whether headers require a 48 dp tap target.
  final bool tappableHeader;

  /// Paint and padding around each section.
  final Decoration? sectionDecoration;

  /// Builds an app item with its own semantics and actions.
  final Widget Function(BuildContext, T) itemBuilder;

  /// Builds the package header in its measured bounds.
  final Widget Function(BuildContext, ChipSection<T>) headerBuilder;

  /// Optional stable keys for section slivers.
  final Key? Function(String id)? sliverKey;

  /// Real viewport during navigation preparation; null outside preparation.
  final double? measurementViewportStart;

  /// Viewport height for excluding offscreen measurement-only rows.
  final double measurementViewportExtent;

  /// Decoration padding included in section geometry.
  EdgeInsets get insets =>
      sectionDecoration?.padding.resolve(textDirection) ?? EdgeInsets.zero;

  /// Measures the header at the current width and scale.
  double headerExtent(ChipSection<T> section) {
    final painter =
        TextPainter(
          text: TextSpan(text: section.label, style: headerStyle),
          textScaler: textScaler,
          textDirection: textDirection,
        )..layout(
          maxWidth: math.max(
            0,
            crossAxisWidth -
                insets.horizontal -
                24 -
                (showChevron ? headerStyle.fontSize ?? 16 : 0),
          ),
        );
    final height =
        math.max(
          painter.height,
          showChevron ? headerStyle.fontSize ?? 16.0 : 0.0,
        ) +
        16;
    painter.dispose();
    return tappableHeader ? math.max(48.0, height) : height;
  }
}

/// Layout extension point. Navigation, selection and announcements stay core-owned.
abstract class SectionedLayout {
  /// Constructor for app subclasses.
  const SectionedLayout();

  /// Creates the dynamic grid layout.
  const factory SectionedLayout.grid({SectionColumnsBuilder? columnsBuilder}) =
      SectionedGridLayout;

  /// Creates the dynamic single-column layout.
  const factory SectionedLayout.list() = SectionedListLayout;

  /// Unmeasured rows remain unknown. [throughSectionId] identifies the active
  /// navigation target while the core prepares its prefix and viewport suffix.
  SectionedGeometry prepare<T>(
    SectionedLayoutInput<T> input,
    SectionedMeasurementHost measurementHost, {
    String? throughSectionId,
  });

  /// Renders from the snapshot returned by [prepare].
  List<Widget> buildSlivers<T>(
    BuildContext context,
    SectionedLayoutInput<T> input,
    SectionedGeometry geometry,
    SectionedMeasurementHost measurementHost,
  );
}

/// Dynamic rows: each row fills the height of its tallest item.
class SectionedGridLayout extends SectionedLayout {
  /// Creates a grid. Apps may extend it and override either hook.
  const SectionedGridLayout({this.columnsBuilder});

  /// Column rule, or [defaultColumns].
  final SectionColumnsBuilder? columnsBuilder;

  /// Copies this grid layout with the supplied changes.
  SectionedGridLayout copyWith({SectionColumnsBuilder? columnsBuilder}) =>
      SectionedGridLayout(
        columnsBuilder: columnsBuilder ?? this.columnsBuilder,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionedGridLayout &&
          other.runtimeType == runtimeType &&
          (other.columnsBuilder == null) == (columnsBuilder == null);

  @override
  int get hashCode => Object.hash(runtimeType, columnsBuilder != null);

  /// Three columns, two at large text, fewer below 72 dp per cell.
  static int defaultColumns(double width, TextScaler scaler) {
    var columns = scaler.scale(14) / 14 >= 2 ? 2 : 3;
    // shortcut: 72 is the existing minimum cell width; measure before 1.0.
    while (columns > 1 && width / columns < 72) {
      columns--;
    }
    return columns;
  }

  @override
  SectionedGeometry prepare<T>(
    SectionedLayoutInput<T> input,
    SectionedMeasurementHost measurementHost, {
    String? throughSectionId,
  }) {
    final columns = (columnsBuilder ?? defaultColumns)(
      input.crossAxisWidth - input.insets.horizontal,
      input.textScaler,
    );
    if (columns < 1) throw ArgumentError('columnsBuilder must return >= 1');
    double? top = 0;
    final sections = <SectionedSectionGeometry>[];
    for (final section in input.sections) {
      final geometry = SectionedSectionGeometry(
        id: section.id,
        top: top,
        headerExtent: input.headerExtent(section),
        rowExtents: [
          for (
            var row = 0;
            row < (section.items.length / columns).ceil();
            row++
          )
            measurementHost.rowExtent(section.id, row),
        ],
        insets: input.insets,
        columns: columns,
      );
      sections.add(geometry);
      top = top == null || geometry.extent == null
          ? null
          : top + geometry.extent!;
    }
    return SectionedGeometry(sections);
  }

  @override
  List<Widget> buildSlivers<T>(
    BuildContext context,
    SectionedLayoutInput<T> input,
    SectionedGeometry geometry,
    SectionedMeasurementHost measurementHost,
  ) => [
    for (var s = 0; s < input.sections.length; s++)
      _section(input, input.sections[s], geometry.sections[s], measurementHost),
  ];

  Widget _section<T>(
    SectionedLayoutInput<T> input,
    ChipSection<T> section,
    SectionedSectionGeometry geometry,
    SectionedMeasurementHost host,
  ) {
    Widget sliver = SliverLayoutBuilder(
      builder: (context, constraints) {
        final reverse = constraints.growthDirection == GrowthDirection.reverse;
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            childCount: 1 + geometry.rowExtents.length,
            (context, childIndex) {
              final index = reverse
                  ? geometry.rowExtents.length - childIndex
                  : childIndex;
              if (index == 0) {
                final start = input.measurementViewportStart;
                final top = geometry.top;
                final offscreen =
                    start != null &&
                    (top == null ||
                        top + geometry.insets.top >=
                            start + input.measurementViewportExtent ||
                        top + geometry.insets.top + geometry.headerExtent <=
                            start);
                return ExcludeFocus(
                  excluding: offscreen,
                  child: ExcludeSemantics(
                    excluding: offscreen,
                    child: IgnorePointer(
                      ignoring: offscreen,
                      child: SizedBox(
                        height: geometry.headerExtent,
                        child: input.headerBuilder(context, section),
                      ),
                    ),
                  ),
                );
              }
              final row = index - 1;
              Widget child = _MeasureRow(
                host: host,
                sectionId: section.id,
                row: row,
                columns: geometry.columns,
                textDirection: input.textDirection,
                children: [
                  for (
                    var i = row * geometry.columns;
                    i < (row + 1) * geometry.columns;
                    i++
                  )
                    i < section.items.length
                        ? input.itemBuilder(context, section.items[i])
                        : const SizedBox.shrink(),
                ],
              );
              final start = input.measurementViewportStart;
              var offscreen = false;
              if (start != null) {
                double? top = geometry.top == null
                    ? null
                    : geometry.top! +
                          geometry.insets.top +
                          geometry.headerExtent;
                for (var i = 0; i < row && top != null; i++) {
                  final extent = geometry.rowExtents[i];
                  top = extent == null ? null : top + extent;
                }
                final height = geometry.rowExtents[row];
                offscreen =
                    top == null ||
                    top >= start + input.measurementViewportExtent ||
                    (height != null && top + height <= start);
              }
              return ExcludeFocus(
                excluding: offscreen,
                child: ExcludeSemantics(
                  excluding: offscreen,
                  child: IgnorePointer(ignoring: offscreen, child: child),
                ),
              );
            },
          ),
        );
      },
    );
    sliver = SliverPadding(padding: geometry.insets, sliver: sliver);
    if (input.sectionDecoration case final decoration?) {
      sliver = DecoratedSliver(decoration: decoration, sliver: sliver);
    }
    return KeyedSubtree(key: input.sliverKey?.call(section.id), child: sliver);
  }
}

/// A dynamic layout with one item per row.
class SectionedListLayout extends SectionedGridLayout {
  /// Creates a single-column layout. Apps may extend it.
  const SectionedListLayout() : super(columnsBuilder: _oneColumn);

  static int _oneColumn(double width, TextScaler scaler) => 1;
}

class _MeasureRow extends MultiChildRenderObjectWidget {
  const _MeasureRow({
    required this.host,
    required this.sectionId,
    required this.row,
    required this.columns,
    required this.textDirection,
    required super.children,
  });

  final SectionedMeasurementHost host;
  final String sectionId;
  final int row;
  final int columns;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureRow(
    host: host,
    sectionId: sectionId,
    row: row,
    columns: columns,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureRow renderObject,
  ) {
    var needsLayout = false;
    if (renderObject.host != host) {
      renderObject.host = host;
      needsLayout = true;
    }
    if (renderObject.sectionId != sectionId) {
      renderObject.sectionId = sectionId;
      needsLayout = true;
    }
    if (renderObject.row != row) {
      renderObject.row = row;
      needsLayout = true;
    }
    if (renderObject.columns != columns) {
      renderObject.columns = columns;
      needsLayout = true;
    }
    if (renderObject.textDirection != textDirection) {
      renderObject.textDirection = textDirection;
      needsLayout = true;
    }
    if (needsLayout) {
      renderObject.markNeedsLayout();
    }
  }
}

class _MeasureRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMeasureRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MeasureRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MeasureRowParentData> {
  _RenderMeasureRow({
    required SectionedMeasurementHost host,
    required String sectionId,
    required int row,
    required int columns,
    required TextDirection textDirection,
  }) : _host = host,
       _sectionId = sectionId,
       _row = row,
       _columns = columns,
       _textDirection = textDirection;

  SectionedMeasurementHost _host;
  SectionedMeasurementHost get host => _host;
  set host(SectionedMeasurementHost value) {
    if (_host != value) {
      _host = value;
      markNeedsLayout();
    }
  }

  String _sectionId;
  String get sectionId => _sectionId;
  set sectionId(String value) {
    if (_sectionId != value) {
      _sectionId = value;
      markNeedsLayout();
    }
  }

  int _row;
  int get row => _row;
  set row(int value) {
    if (_row != value) {
      _row = value;
      markNeedsLayout();
    }
  }

  int _columns;
  int get columns => _columns;
  set columns(int value) {
    if (_columns != value) {
      _columns = value;
      markNeedsLayout();
    }
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection != value) {
      _textDirection = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MeasureRowParentData) {
      child.parentData = _MeasureRowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cellWidth = _columns > 0 ? width / _columns : width;
    var maxHeight = 0.0;

    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints(
          minWidth: cellWidth,
          maxWidth: cellWidth,
          minHeight: 0,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      if (child.size.height > maxHeight) {
        maxHeight = child.size.height;
      }
      final childParentData = child.parentData! as _MeasureRowParentData;
      child = childParentData.nextSibling;
    }

    child = firstChild;
    var index = 0;
    while (child != null) {
      child.layout(
        BoxConstraints(
          minWidth: cellWidth,
          maxWidth: cellWidth,
          minHeight: maxHeight,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      final dx = _textDirection == TextDirection.rtl
          ? width - (index + 1) * cellWidth
          : index * cellWidth;
      final childParentData = child.parentData! as _MeasureRowParentData;
      childParentData.offset = Offset(dx, 0);
      child = childParentData.nextSibling;
      index++;
    }

    size = Size(width, maxHeight);
    _host.recordRow(_sectionId, _row, maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
