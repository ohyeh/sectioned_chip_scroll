import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

import 'helpers.dart';

class _AppGrid extends SectionedGridLayout {
  const _AppGrid();
}

class _AppList extends SectionedListLayout {
  const _AppList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scale in [1.0, 3.12]) {
    for (final layout in [const _AppGrid(), const _AppList()]) {
      test(
        'table ${layout.runtimeType} scale=$scale includes headers/insets',
        () {
          final input = SectionedLayoutInput<int>(
            sections: testSections([5, 2, 0]),
            crossAxisWidth: 390,
            textScaler: TextScaler.linear(scale),
            headerStyle: const TextStyle(fontSize: 16, height: 1),
            textDirection: TextDirection.ltr,
            sectionDecoration: const BoxDecoration(
              border: Border.fromBorderSide(BorderSide(width: 3)),
            ),
            itemBuilder: testItem,
            headerBuilder: (_, s) => Text(s.label),
          );
          final host = SectionedMeasurementHost();
          final unknown = layout.prepare(input, host);
          expect(unknown.sections.first.top, 0);
          expect(unknown.sections.first.extent, isNull);
          expect(unknown.sections[1].top, isNull);
          expect(unknown.sectionAtOffset(2000), isNull);
          final columns = layout is SectionedListLayout
              ? 1
              : (scale == 1 ? 3 : 2);
          final rowCounts = [(5 / columns).ceil(), (2 / columns).ceil(), 0];
          for (var s = 0; s < rowCounts.length; s++) {
            for (var r = 0; r < rowCounts[s]; r++) {
              host.recordRow('s$s', r, (20 + r * 10) * scale);
            }
          }
          final geometry = layout.prepare(input, host, throughSectionId: 's2');
          var top = 0.0;
          for (var s = 0; s < 3; s++) {
            final section = geometry.sections[s];
            final painter = TextPainter(
              text: TextSpan(text: 'Section $s', style: input.headerStyle),
              textDirection: TextDirection.ltr,
              textScaler: input.textScaler,
            )..layout(maxWidth: 390 - 6 - 24 - 16);
            final header = painter.height + 16;
            painter.dispose();
            final rows = List.generate(
              rowCounts[s],
              (r) => (20 + r * 10) * scale,
            );
            final extent = header + 6 + rows.fold<double>(0, (a, b) => a + b);
            expect(section.columns, columns);
            expect(section.top, closeTo(top, 0.001));
            expect(section.headerExtent, closeTo(header, 0.001));
            expect(section.extent, closeTo(extent, 0.001));
            expect(geometry.sectionAtOffset(top), 's$s');
            expect(geometry.sectionAtOffset(top + extent - 0.001), 's$s');
            top += extent;
          }
          expect(geometry.extent, closeTo(top, 0.001));
          expect(geometry.sectionAtOffset(top), isNull);
          expect(geometry.sectionAtOffset(-1), isNull);
          expect(geometry.sectionAtOffset(double.nan), isNull);
          expect(() => geometry.sections.clear(), throwsUnsupportedError);
          expect(
            () => host.recordRow('s0', 0, double.infinity),
            throwsArgumentError,
          );
        },
      );

      testWidgets('renderer agrees with table ${layout.runtimeType} $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 2000),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SectionedChipScrollView<int>(
                  sections: testSections([2, 1]),
                  layout: layout,
                  sectionDecoration: const BoxDecoration(
                    border: Border.fromBorderSide(BorderSide(width: 2)),
                  ),
                  itemBuilder: (_, i) => SizedBox(
                    key: ValueKey('tile-$i'),
                    height: (20 + i * 10) * scale,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state<SectionedChipScrollViewState<int>>(
          find.byType(SectionedChipScrollView<int>),
        );
        final g = state.geometry!;
        final origin = tester.getTopLeft(find.byType(CustomScrollView)).dy;
        for (var s = 0; s < 2; s++) {
          final header = find.descendant(
            of: find.byType(SliverList),
            matching: find.text('Section $s'),
          );
          expect(
            tester.getTopLeft(header).dy - 12 - 2 - origin,
            closeTo(g.sections[s].top!, 0.01),
          );
        }
        expect(
          g.sections[0].rowExtents,
          layout is SectionedListLayout
              ? [20 * scale, 30 * scale]
              : [30 * scale],
        );
      });
    }
  }

  test(
    'style copyWith preserves values and factories expose public layouts',
    () {
      const style = SectionedChipScrollStyle.outlined();
      final copy = style.copyWith(accentColor: Colors.blue);
      expect(copy.accentColor, Colors.blue);
      expect(copy.chipShape, style.chipShape);
      expect(const SectionedLayout.grid(), isA<SectionedGridLayout>());
      expect(const SectionedLayout.list(), isA<SectionedListLayout>());
    },
  );

  testWidgets(
    'rail visual cannot add focus or actions; item keeps two actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var itemTaps = 0;
      var visualTaps = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        testApp(
          CategorizedChipScrollView<int>(
            categories: [
              for (var i = 0; i < 3; i++)
                SectionCategory(
                  id: 'c$i',
                  label: 'Cat $i',
                  sections: testSections([1]),
                ),
            ],
            railItemBuilder: (_, category, selected) => Focus(
              focusNode: category.id == 'c0' ? node : null,
              child: TextButton(
                onPressed: () => visualTaps++,
                child: const Text('Nested'),
              ),
            ),
            itemBuilder: (_, i) => Column(
              children: [
                TextButton(
                  onPressed: () => itemTaps++,
                  child: const Text('Buy'),
                ),
                TextButton(
                  onPressed: () => itemTaps++,
                  child: const Text('Details'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(node.canRequestFocus, isFalse);
      expect(find.bySemanticsLabel('Nested'), findsNothing);
      expect(find.bySemanticsLabel('Cat 0, 1 of 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(visualTaps, 0);
      await tester.tap(find.text('Buy'));
      await tester.tap(find.text('Details'));
      expect(itemTaps, 2);
      semantics.dispose();
    },
  );

  testWidgets('itemBuilder can return a LayoutBuilder tile without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        SectionedChipScrollView<int>(
          sections: testSections([3]),
          itemBuilder: (context, item) => LayoutBuilder(
            builder: (context, constraints) =>
                SizedBox(height: 100, child: Text('item $item')),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('item 0'), findsOneWidget);
  });

  testWidgets('RTL mirrors cell positions and hit test order', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      testApp(
        SectionedChipScrollView<int>(
          sections: testSections([3]),
          itemBuilder: (context, item) => GestureDetector(
            onTap: () => tapped.add(item),
            child: SizedBox(height: 50, child: Text('item $item')),
          ),
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();
    final item0 = tester.getTopLeft(find.text('item 0')).dx;
    final item2 = tester.getTopLeft(find.text('item 2')).dx;
    expect(
      item0,
      greaterThan(item2),
      reason: 'in RTL, item 0 must be to the right of item 2',
    );
    await tester.tap(find.text('item 0'));
    await tester.tap(find.text('item 2'));
    expect(tapped, [0, 2]);
  });
}
