import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

import 'helpers.dart';

SectionedChipScrollView<int> _view(
  List<ChipSection<int>> sections, {
  SectionedChipScrollConfig config = const SectionedChipScrollConfig(),
  ValueChanged<ChipSection<int>>? onSectionTap,
  ValueChanged<ChipSection<int>>? onSectionSelected,
  SectionColumnsBuilder? columnsBuilder,
  Widget Function(BuildContext, int) itemBuilder = testItem,
}) => SectionedChipScrollView<int>(
  sections: sections,
  itemBuilder: itemBuilder,
  config: config,
  onSectionTap: onSectionTap,
  onSectionSelected: onSectionSelected,
  columnsBuilder: columnsBuilder,
);

/// The title text of a section in the list (not the chip, not the picker).
Finder _title(String label) =>
    find.descendant(of: find.byType(SliverList), matching: find.text(label));

/// Title top minus list top (the chip bar bottom), minus the title's 12 px
/// top padding.
double _offsetError(WidgetTester tester, String label) =>
    tester.getTopLeft(_title(label)).dy -
    tester.getTopLeft(find.byType(CustomScrollView)).dy -
    12;

SectionedChipScrollViewState<int> _state(WidgetTester tester) =>
    tester.state(find.byType(SectionedChipScrollView<int>));

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.expand_more));
  await tester.pumpAndSettle();
}

/// Taps [label] inside the open picker (the picker is the last route).
Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

double _scaleAt(WidgetTester tester, Finder f) =>
    MediaQuery.textScalerOf(tester.element(f)).scale(10) / 10;

void main() {
  group('semantics', () {
    for (final mode in ChipSemantics.values) {
      testWidgets('chips expose $mode, selected and tap, in bar and picker', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          testApp(
            _view(
              testSections([2, 2, 2]),
              config: SectionedChipScrollConfig(chipSemantics: mode),
            ),
          ),
        );
        void check(Finder f, {required bool selected}) {
          final node = tester.getSemantics(f);
          expect(
            node,
            containsSemantics(
              isSelected: selected,
              hasTapAction: true,
              isLink: mode == ChipSemantics.link,
            ),
          );
          expect(
            node.getSemanticsData().role,
            mode == ChipSemantics.tab
                ? SemanticsRole.tab
                : isNot(SemanticsRole.tab),
          );
        }

        check(find.bySemanticsLabel('Section 0, 1 of 3'), selected: true);
        check(find.bySemanticsLabel('Section 1, 2 of 3'), selected: false);
        await _openPanel(tester);
        check(find.bySemanticsLabel('Section 2, 3 of 3').last, selected: false);
        handle.dispose();
      });
    }
  });

  group('section title', () {
    for (final chevron in [false, true]) {
      for (final tappable in [false, true]) {
        testWidgets('chevron=$chevron tappable=$tappable', (tester) async {
          final handle = tester.ensureSemantics();
          final tapped = <String>[];
          await tester.pumpWidget(
            testApp(
              _view(
                testSections([2, 2]),
                config: SectionedChipScrollConfig(showSectionChevron: chevron),
                onSectionTap: tappable ? (s) => tapped.add(s.id) : null,
              ),
            ),
          );
          expect(
            find.byIcon(Icons.chevron_right),
            chevron ? findsWidgets : findsNothing,
          );
          // The chevron is not read out: the title label is the plain label.
          final title = find.bySemanticsLabel('Section 0');
          expect(
            tester.getSemantics(title),
            containsSemantics(
              isHeader: true,
              isButton: tappable,
              hasTapAction: tappable,
            ),
          );
          expect(
            find.descendant(
              of: _title('Section 0'),
              matching: find.byType(InkWell),
            ),
            findsNothing,
          );
          await tester.tap(_title('Section 0'));
          expect(tapped, tappable ? ['s0'] : isEmpty);
          handle.dispose();
        });
      }
    }
  });

  group('text scale', () {
    testWidgets('maxTextScale caps the view and the picker', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3.12;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        testApp(
          _view(
            testSections([2, 2]),
            config: const SectionedChipScrollConfig(maxTextScale: 2),
          ),
        ),
      );
      expect(_scaleAt(tester, _title('Section 0')), closeTo(2, 0.01));
      await _openPanel(tester);
      expect(_scaleAt(tester, find.text('Sections')), closeTo(2, 0.01));
    });

    for (final max in [null, 2.0]) {
      testWidgets('picker inherits a local scale (max: $max)', (tester) async {
        await tester.pumpWidget(
          testApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(3.12)),
                child: _view(
                  testSections([2, 2]),
                  config: SectionedChipScrollConfig(maxTextScale: max),
                ),
              ),
            ),
          ),
        );
        await _openPanel(tester);
        expect(
          _scaleAt(tester, find.text('Sections')),
          closeTo(max ?? 3.12, 0.01),
        );
      });
    }

    testWidgets('picker keeps the route geometry and the captured scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.12)),
              child: _view(testSections([2, 2])),
            ),
          ),
        ),
      );
      await _openPanel(tester);
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();
      final panelText = tester.element(find.text('Sections'));
      expect(MediaQuery.sizeOf(panelText), const Size(400, 900));
      expect(_scaleAt(tester, find.text('Sections')), closeTo(3.12, 0.01));
    });
  });

  group('data updates', () {
    testWidgets('reorder keeps, removal reselects, empty builds nothing', (
      tester,
    ) async {
      final selected = <String>[];
      Future<void> show(List<ChipSection<int>> s) => tester.pumpWidget(
        testApp(_view(s, onSectionSelected: (x) => selected.add(x.id))),
      );
      final all = testSections([2, 2, 2]);
      await show(all);
      await tester.tap(find.text('Section 1').first);
      await tester.pumpAndSettle();
      expect(selected.last, 's1');

      await show([all[2], all[1], all[0]]);
      await tester.pumpAndSettle();
      expect(selected.last, 's1');

      await show([all[2], all[0]]);
      await tester.pumpAndSettle();
      expect(selected.last, 's2');

      await show([]);
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsNothing);
    });

    testWidgets('an update closes the open picker only', (tester) async {
      final all = testSections([2, 2, 2]);
      await tester.pumpWidget(testApp(_view(all)));
      await _openPanel(tester);
      expect(find.text('Sections'), findsOneWidget);
      await tester.pumpWidget(testApp(_view(all.sublist(1))));
      await tester.pumpAndSettle();
      expect(find.text('Sections'), findsNothing);
      expect(find.byType(SectionedChipScrollView<int>), findsOneWidget);
    });

    testWidgets('equal data keeps the picker; a renamed section closes it', (
      tester,
    ) async {
      final all = testSections([2, 2, 2]);
      await tester.pumpWidget(testApp(_view(all)));
      await _openPanel(tester);
      await tester.pumpWidget(testApp(_view(List.of(all))));
      await tester.pumpAndSettle();
      expect(find.text('Sections'), findsOneWidget);

      final renamed = [
        ChipSection(id: 's0', label: 'Renamed', items: all[0].items),
        ...all.skip(1),
      ];
      await tester.pumpWidget(testApp(_view(renamed)));
      await tester.pumpAndSettle();
      expect(find.text('Sections'), findsNothing);
      expect(find.text('Renamed'), findsWidgets);
    });

    testWidgets('a long chip label wraps past two lines', (tester) async {
      const long = 'A very long section name that needs three or more lines';
      await tester.pumpWidget(
        testApp(
          _view([
            const ChipSection(id: 'a', label: 'Short', items: [0]),
            const ChipSection(id: 'b', label: long, items: [0]),
          ]),
        ),
      );
      final short = tester.getSize(find.text('Short').first).height;
      expect(
        tester.getSize(find.text(long).first).height,
        greaterThan(2.5 * short),
      );
    });
  });

  group('jump', () {
    // Short first sections and tall later ones make SliverList's extent
    // estimate for unbuilt sections wrong, so the first move stops short.
    final misestimated = testSections([1, 1, 1, ...List.filled(11, 12)]);

    testWidgets('long tail aligns after at least one retry', (tester) async {
      await tester.pumpWidget(testApp(_view(misestimated)));
      await _openPanel(tester);
      await _pick(tester, 'Section 10');
      expect(_offsetError(tester, 'Section 10').abs(), lessThan(1));
      expect(_state(tester).lastJumpRetries, greaterThanOrEqualTo(1));
    });

    testWidgets('short tail stops at a stable end and keeps the selection', (
      tester,
    ) async {
      final selected = <String>[];
      final s = testSections([...List.filled(6, 12), 1]);
      await tester.pumpWidget(
        testApp(_view(s, onSectionSelected: (x) => selected.add(x.id))),
      );
      await _openPanel(tester);
      await _pick(tester, 'Section 6');
      expect(tester.takeException(), isNull);
      expect(_offsetError(tester, 'Section 6'), greaterThan(1));
      expect(selected.last, 's6');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(selected.last, 's6');
    });

    testWidgets('a picked short section before the last stays selected', (
      tester,
    ) async {
      final selected = <String>[];
      final s = testSections([...List.filled(6, 12), 1, 1]);
      await tester.pumpWidget(
        testApp(_view(s, onSectionSelected: (x) => selected.add(x.id))),
      );
      await _openPanel(tester);
      await _pick(tester, 'Section 6');
      expect(selected.last, 's6');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(selected.last, 's6');
      // Leaving the end and coming back hands the selection to the last one.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(selected.last, 's7');
    });

    testWidgets('content shorter than a page keeps the first selection', (
      tester,
    ) async {
      final selected = <String>[];
      await tester.pumpWidget(
        testApp(
          _view(
            testSections([1, 1]),
            onSectionSelected: (x) => selected.add(x.id),
          ),
        ),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
    });

    testWidgets('a single section works', (tester) async {
      await tester.pumpWidget(testApp(_view(testSections([3]))));
      await tester.tap(find.text('Section 0').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chip tap during a jump wins at once', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        testApp(
          _view(misestimated, onSectionSelected: (x) => selected.add(x.id)),
        ),
      );
      await _openPanel(tester);
      await tester.tap(find.text('Section 6').last);
      // Past the picker's exit transition, inside the 300 ms jump.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(listPosition(tester).isScrollingNotifier.value, isTrue);
      // One tap: the chip bar is outside the animating scroll view.
      await tester.tap(find.text('Section 4').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_offsetError(tester, 'Section 4').abs(), lessThan(1));
      expect(selected.last, 's4');
    });

    testWidgets('two quick chip taps: the last one wins', (tester) async {
      await tester.pumpWidget(testApp(_view(misestimated)));
      await tester.tap(find.text('Section 2').first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Section 4').first);
      await tester.pumpAndSettle();
      expect(_offsetError(tester, 'Section 4').abs(), lessThan(1));
    });

    testWidgets('disposing during a jump throws nothing', (tester) async {
      await tester.pumpWidget(testApp(_view(misestimated)));
      await tester.tap(find.text('Section 4').first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drag cancels the jump and scroll-spy resumes', (
      tester,
    ) async {
      final selected = <String>[];
      await tester.pumpWidget(
        testApp(
          _view(misestimated, onSectionSelected: (x) => selected.add(x.id)),
        ),
      );
      await tester.tap(find.text('Section 4').first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 5000),
        5000,
      );
      await tester.pumpAndSettle();
      expect(selected.last, 's0');
    });

    testWidgets('a data update cancels the jump and scroll-spy resumes', (
      tester,
    ) async {
      final selected = <String>[];
      Widget build(List<ChipSection<int>> s) =>
          testApp(_view(s, onSectionSelected: (x) => selected.add(x.id)));
      await tester.pumpWidget(build(misestimated));
      await tester.tap(find.text('Section 4').first);
      await tester.pump(const Duration(milliseconds: 50));
      // Same ids, changed content: a real update, not an equal rebuild.
      await tester.pumpWidget(
        build([
          ...misestimated.take(13),
          ChipSection(id: 's13', label: 'Section 13', items: const [0]),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 5000),
        5000,
      );
      await tester.pumpAndSettle();
      expect(selected.last, 's0');
    });

    testWidgets('exhausted retries report once and resume scroll-spy', (
      tester,
    ) async {
      // Section 5 sits right above the target and keeps growing once it is
      // laid out, so the target title keeps moving down.
      const grower = -1;
      Widget item(BuildContext c, int i) => i == grower
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 100, end: 40000),
              duration: const Duration(seconds: 40),
              builder: (_, h, _) => SizedBox(height: h),
            )
          : testItem(c, i);
      final s = [
        ...testSections(List.filled(5, 12)),
        const ChipSection(id: 's5', label: 'Section 5', items: [grower]),
        ...testSections(List.filled(7, 12)).skip(6),
      ];
      await tester.pumpWidget(testApp(_view(s, itemBuilder: item)));
      await _openPanel(tester);
      await tester.tap(find.text('Section 6').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(tester.takeException(), isA<StateError>());
      expect(_state(tester).lastJumpRetries, 3);
      // Scroll-spy is back: dragging to the top selects section 0.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 50000),
        8000,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Section 0, 1 of 7')),
        containsSemantics(isSelected: true),
      );
    });
  });

  group('config', () {
    testWidgets('showExpandButton and showChipFade', (tester) async {
      await tester.pumpWidget(
        testApp(
          _view(
            testSections([2]),
            config: const SectionedChipScrollConfig(
              showExpandButton: false,
              showChipFade: false,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpWidget(testApp(_view(testSections([2]))));
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('showEmptySections', (tester) async {
      final s = testSections([2, 0, 2]);
      await tester.pumpWidget(testApp(_view(s)));
      expect(find.text('Section 1'), findsNothing);
      await tester.pumpWidget(
        testApp(
          _view(
            s,
            config: const SectionedChipScrollConfig(showEmptySections: true),
          ),
        ),
      );
      expect(find.text('Section 1'), findsWidgets);
    });

    testWidgets('columnsBuilder sets the item columns', (tester) async {
      final widths = <double>[];
      await tester.pumpWidget(
        testApp(
          _view(
            testSections([4]),
            columnsBuilder: (w, _) {
              widths.add(w);
              return 1;
            },
          ),
        ),
      );
      expect(widths, isNotEmpty);
      expect(
        tester.getTopLeft(find.text('item 1')).dx,
        tester.getTopLeft(find.text('item 0')).dx,
      );
    });

    test('defaultColumns', () {
      expect(
        SectionedChipScrollView.defaultColumns(375, TextScaler.noScaling),
        3,
      );
      expect(
        SectionedChipScrollView.defaultColumns(
          375,
          const TextScaler.linear(3.12),
        ),
        2,
      );
      expect(
        SectionedChipScrollView.defaultColumns(100, TextScaler.noScaling),
        1,
      );
    });

    test('copyWith clears maxTextScale', () {
      const c = SectionedChipScrollConfig(maxTextScale: 2);
      expect(c.copyWith(maxTextScale: () => null).maxTextScale, isNull);
      expect(c.copyWith(showChipFade: false).maxTextScale, 2);
    });
  });
}
