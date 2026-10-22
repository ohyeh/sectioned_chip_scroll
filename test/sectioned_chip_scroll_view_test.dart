import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll/src/presentation/chrome.dart'
    show HeaderMaterial;
import 'package:sectioned_chip_scroll/src/presentation/motion.dart'
    show PressFeedback, SpringValue;
import 'package:sectioned_chip_scroll/src/presentation/sectioned_chip_scroll_view.dart'
    show ChipControl;

import 'helpers.dart';

Widget _view(
  List<ChipSection<int>> sections, {
  SectionedChipScrollConfig config = const SectionedChipScrollConfig(),
  ValueChanged<ChipSection<int>>? onSectionTap,
  ValueChanged<ChipSection<int>>? onSectionSelected,
  SectionColumnsBuilder? columnsBuilder,
  Widget Function(BuildContext, int) itemBuilder = testItem,
  SectionedLayout layout = const SectionedLayout.list(),
}) => SizedBox(
  // Compact fixtures must overflow to exercise the picker rather than B2.
  width: sections.length <= 3 ? 280 : null,
  child: SectionedChipScrollView<int>(
    labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
    sections: sections,
    itemBuilder: itemBuilder,
    config: config,
    onSectionTap: onSectionTap,
    onSectionSelected: onSectionSelected,
    columnsBuilder: columnsBuilder,
    layout: columnsBuilder == null ? layout : const SectionedLayout.grid(),
  ),
);

/// The title text of a section in the list (not the chip, not the picker).
Finder _title(String label) =>
    find.descendant(of: find.byType(SliverList), matching: find.text(label));

/// Title top minus list top and the header's 12px top padding.
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
  group('round 2', () {
    Future<void> build(
      WidgetTester tester, {
      double scale = 1,
      double width = 375,
      bool categories = false,
      SectionedChipScrollStyle style =
          const SectionedChipScrollStyle.outlined(),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 812);
      addTearDown(tester.view.reset);
      final sections = testSections(List.filled(35, 8));
      Widget item(BuildContext context, int i) =>
          SizedBox(height: 72.0 + i * 13, child: Text('row $i'));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: categories
                  ? CategorizedChipScrollView<int>(
                      categories: [
                        SectionCategory(
                          id: 'c',
                          label: 'Category',
                          sections: sections,
                        ),
                      ],
                      itemBuilder: item,
                    )
                  : SectionedChipScrollView<int>(
                      sections: sections,
                      itemBuilder: item,
                      style: style,
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('R1 anchor follows parent text reflow at unchanged viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      final scale = ValueNotifier(1.0);
      addTearDown(scale.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<double>(
            valueListenable: scale,
            builder: (_, value, _) => MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(value)),
              child: Scaffold(
                body: Column(
                  children: [
                    const Text(
                      'A heading above the category bar',
                      style: TextStyle(fontSize: 20),
                    ),
                    Expanded(child: _view(testSections(List.filled(8, 8)))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _openPanel(tester);
      scale.value = 2;
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('sectioned_chip_scroll.panelHeader')),
            )
            .dy,
        tester.getTopLeft(find.byType(HeaderMaterial).first).dy,
      );
    });

    for (final categories in [false, true]) {
      testWidgets(
        'L1 default renders one item per row categories=$categories',
        (tester) async {
          await build(tester, categories: categories);
          final first = tester.getRect(find.text('row 0').first);
          final second = tester.getRect(find.text('row 1').first);
          expect(second.top, greaterThanOrEqualTo(first.bottom));
          expect(second.left, first.left);
        },
      );
    }

    for (final width in [320.0, 375.0, 414.0, 430.0]) {
      for (final scale in [1.0, 3.12]) {
        testWidgets('V1 leading inset width=$width scale=$scale', (
          tester,
        ) async {
          await build(tester, width: width, scale: scale);
          final chip = find.byType(ChipControl).first;
          expect(tester.getTopLeft(chip).dx, 12);
        });
      }
    }

    testWidgets('V1 style override sets the scrolling content inset', (
      tester,
    ) async {
      final style = const SectionedChipScrollStyle.outlined().copyWith(
        chipBarLeadingInset: 24,
      );
      await build(tester, style: style);
      expect(tester.getTopLeft(find.byType(ChipControl).first).dx, 24);
      expect(style.copyWith(), style);
    });

    testWidgets('L1 uneven list scroll-spy follows the visible section', (
      tester,
    ) async {
      await build(tester);
      await _openPanel(tester);
      await tester.ensureVisible(find.text('Section 34').last);
      await _pick(tester, 'Section 34');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
      await tester.pumpAndSettle();
      final position = listPosition(tester);
      final id = _state(tester).geometry!.sectionAtOffset(position.pixels);
      final selected = tester
          .widgetList<ChipControl>(find.byType(ChipControl))
          .singleWhere((c) => c.selected);
      expect(selected.label, 'Section ${id!.substring(1)}');
      expect(selected.label, isNot('Section 34'));
    });

    for (final timing in [true, false]) {
      testWidgets(
        '${timing ? 'V2' : 'V3'} far picker starts motion and selection immediately',
        (tester) async {
          await build(tester, scale: 3.12);
          await _openPanel(tester);
          final pick = find.text('Section 34').last;
          await tester.ensureVisible(pick);
          await tester.pumpAndSettle();
          final before = listPosition(tester).pixels;
          await tester.tap(pick);
          await tester.pump();
          List<String> selected() => tester
              .widgetList<ChipControl>(
                find.descendant(
                  of: find.byType(HeaderMaterial).first,
                  matching: find.byType(ChipControl),
                ),
              )
              .where((c) => c.selected)
              .map((c) => c.label)
              .toList();
          if (!timing) expect(selected(), ['Section 34']);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (!timing) expect(selected(), ['Section 34']);
          }
          if (timing) expect(listPosition(tester).pixels, greaterThan(before));
          for (
            var i = 0;
            i < 300 && _state(tester).navigationPhase != null;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 16));
            if (!timing) expect(selected(), ['Section 34']);
          }
          await tester.pumpAndSettle();
          expect(_offsetError(tester, 'Section 34'), closeTo(0, 1));
          expect(selected(), ['Section 34']);
        },
      );
    }
  });
  group('final design', () {
    Future<void> screen(
      WidgetTester tester,
      List<String> names, {
      double scale = 1,
      Size size = const Size(375, 812),
      bool categories = false,
      TextDirection direction = TextDirection.ltr,
      ValueChanged<ChipSection<int>>? onSelected,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final sections = [
        for (var i = 0; i < names.length; i++)
          ChipSection(
            id: 's$i',
            label: names[i],
            items: List.generate(i < 3 ? 1 : 30, (j) => j),
          ),
      ];
      const labels = SectionedChipScrollLabels(
        expand: 'Open sections',
        collapse: 'Collapse sections',
        barrier: 'Dismiss sections',
        panelTitle: 'Choose a section with a long heading',
        categoryPanelTitle: 'Choose a category',
      );
      const config = SectionedChipScrollConfig(panelBottomInset: 56);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: direction, child: child!),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Column(
                  children: [
                    const SizedBox(height: 100),
                    Expanded(
                      child: categories
                          ? CategorizedChipScrollView<int>(
                              categories: [
                                for (var i = 0; i < names.length; i++)
                                  SectionCategory(
                                    id: 'c$i',
                                    label: names[i],
                                    sections: sections,
                                  ),
                              ],
                              config: const CategorizedChipScrollConfig(
                                railWidth: 1000,
                                sectionConfig: config,
                              ),
                              labels: labels,
                              itemBuilder: testItem,
                            )
                          : SectionedChipScrollView<int>(
                              sections: sections,
                              itemBuilder: testItem,
                              layout: const SectionedLayout.list(),
                              config: config,
                              labels: labels,
                              onSectionSelected: onSelected,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final names = [
      'A',
      'Medium',
      'A very long unique label that cannot fit on a phone at any text scale',
      for (var i = 3; i < 35; i++) 'Choice $i',
    ];
    final panel = find.byKey(const ValueKey('sectioned_chip_scroll.panel'));
    final header = find.byKey(
      const ValueKey('sectioned_chip_scroll.panelHeader'),
    );
    final inner = find.byKey(
      const ValueKey('sectioned_chip_scroll.panelScroll'),
    );

    testWidgets(
      'B2 hides only when natural chip widths fit and updates on scale',
      (tester) async {
        await screen(tester, ['A', 'B', 'C']);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        await screen(tester, ['A', 'Medium', 'Long name']);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        await screen(tester, ['A', 'Medium', 'Long name'], scale: 3.12);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final scale in [1.0, 3.12]) {
      for (final width in [320.0, 375.0, 414.0, 430.0]) {
        for (final height in [568.0, 932.0]) {
          for (final categories in [false, true]) {
            testWidgets(
              'B2-B10 B15 C3 C7 picker geometry ${width}x$height scale=$scale categories=$categories',
              (tester) async {
                final size = Size(width, height);
                await screen(tester, ['A', 'B', 'C'], size: size, scale: scale);
                expect(find.byIcon(Icons.expand_more), findsNothing);
                await screen(
                  tester,
                  names,
                  size: size,
                  scale: scale,
                  categories: categories,
                );
                final trigger = find.byIcon(
                  categories ? Icons.unfold_more : Icons.expand_more,
                );
                final slot = tester.getRect(
                  find
                      .ancestor(of: trigger, matching: find.byType(IconButton))
                      .first,
                );
                expect(
                  slot.width,
                  (16 * scale.clamp(0.0, 2.0) + 24).clamp(
                    48.0,
                    double.infinity,
                  ),
                );
                expect(slot.height, greaterThanOrEqualTo(48));
                if (!categories) {
                  final long = find.text(names[2]).first;
                  final text = tester.widget<Text>(long);
                  expect(text.maxLines, 1);
                  expect(text.softWrap, false);
                  expect(text.overflow, TextOverflow.ellipsis);
                  final chip = find
                      .ancestor(of: long, matching: find.byType(Material))
                      .first;
                  expect(
                    tester.getSize(chip).width,
                    closeTo(width - slot.width - 12, .01),
                  );
                  expect(slot.height, closeTo(tester.getSize(chip).height, .5));
                  expect(tester.getSize(long).height, lessThan(60));
                }
                await tester.tap(trigger);
                await tester.pumpAndSettle();
                expect(tester.getTopLeft(panel).dy, 100);
                final close = find
                    .ancestor(
                      of: find.byIcon(Icons.expand_less),
                      matching: find.byType(IconButton),
                    )
                    .first;
                expect(tester.getRect(close).size, slot.size);
                expect(tester.getRect(close).right, closeTo(slot.right, .5));
                expect(
                  tester.getCenter(close).dy,
                  closeTo(tester.getCenter(header).dy, .5),
                );
                final title = find.descendant(
                  of: header,
                  matching: find.byType(Text),
                );
                expect(tester.widget<Text>(title).maxLines, 1);
                expect(
                  tester.widget<Text>(title).overflow,
                  TextOverflow.ellipsis,
                );
                expect(tester.getSize(header).height, greaterThanOrEqualTo(48));
                if (scale > 1) {
                  expect(tester.getSize(header).height, greaterThan(48));
                }
                final wrap = find.descendant(
                  of: panel,
                  matching: find.byType(Wrap),
                );
                expect(tester.widget<Wrap>(wrap).spacing, 8);
                expect(tester.widget<Wrap>(wrap).runSpacing, 8);
                final a = find.descendant(of: panel, matching: find.text('A'));
                final medium = find.descendant(
                  of: panel,
                  matching: find.text('Medium'),
                );
                expect(
                  tester.getSize(a).width,
                  lessThan(tester.getSize(medium).width),
                );
                final long = find.descendant(
                  of: panel,
                  matching: find.text(names[2]),
                );
                expect(tester.widget<Text>(long).maxLines, 1);
                expect(tester.widget<Text>(long).softWrap, false);
                expect(
                  tester.widget<Text>(long).overflow,
                  TextOverflow.ellipsis,
                );
                expect(
                  tester
                      .getSize(
                        find
                            .ancestor(of: long, matching: find.byType(Material))
                            .first,
                      )
                      .width,
                  closeTo(width - 16, .01),
                );
                expect(
                  tester.getBottomLeft(panel).dy,
                  lessThanOrEqualTo(height - 56 - 80),
                );
                final position = tester
                    .widget<SingleChildScrollView>(inner)
                    .controller!
                    .position;
                expect(position.maxScrollExtent, greaterThan(0));
                final before = tester.getRect(header);
                final fade = tester.widget<DecoratedBox>(
                  find.byKey(const ValueKey('sectioned_chip_scroll.panelFade')),
                );
                expect((fade.decoration as BoxDecoration).gradient, isNotNull);
                expect(
                  tester
                      .widget<Scrollbar>(
                        find.descendant(
                          of: panel,
                          matching: find.byType(Scrollbar),
                        ),
                      )
                      .thumbVisibility,
                  true,
                );
                await tester.drag(inner, const Offset(0, -180));
                await tester.pumpAndSettle();
                expect(position.pixels, greaterThan(0));
                expect(tester.getRect(header), before);
                await tester.tap(find.byIcon(Icons.expand_less));
                await tester.pumpAndSettle();
                expect(panel, findsNothing);
                await tester.tap(trigger);
                await tester.pumpAndSettle();
                await tester.tapAt(Offset(width / 2, height - 96));
                await tester.pumpAndSettle();
                expect(panel, findsNothing);
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }

    for (final size in [
      const Size(568, 320),
      const Size(844, 390),
      const Size(932, 430),
    ]) {
      for (final scale in [1.0, 3.12]) {
        for (final categories in [false, true]) {
          testWidgets(
            'F1 landscape $size scale=$scale categories=$categories',
            (tester) async {
              await screen(
                tester,
                names,
                size: size,
                scale: scale,
                categories: categories,
              );
              await tester.tap(
                find.byIcon(categories ? Icons.unfold_more : Icons.expand_more),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(
                tester.getBottomLeft(panel).dy,
                lessThanOrEqualTo(size.height - 56),
              );
              tester.view.physicalSize = Size(size.height, size.width);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              tester.view.physicalSize = size;
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final chip = find.descendant(of: panel, matching: find.text('A'));
              await tester.ensureVisible(chip);
              await tester.pumpAndSettle();
              final rect = tester.getRect(chip);
              expect(
                rect.center.dy,
                inInclusiveRange(
                  tester.getTopLeft(panel).dy,
                  tester.getBottomLeft(panel).dy,
                ),
              );
              await tester.tap(chip);
              await tester.pumpAndSettle();
              expect(panel, findsNothing);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets('R2 short panel scroll carries the header', (tester) async {
      await screen(tester, names, size: const Size(568, 320), scale: 3.12);
      await _openPanel(tester);
      final header = find.byKey(
        const ValueKey('sectioned_chip_scroll.panelHeader'),
      );
      final inner = find.byKey(
        const ValueKey('sectioned_chip_scroll.panelScroll'),
      );
      final before = tester.getTopLeft(header).dy;
      await tester.drag(inner, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, lessThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('R3 fades respect header padding and full panel extent', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          SectionedChipScrollView<int>(
            sections: testSections(List.filled(35, 8)),
            itemBuilder: testItem,
            style: const SectionedChipScrollStyle.outlined(edgeFadeExtent: 24),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final titlePadding = tester
          .widget<Padding>(
            find
                .ancestor(
                  of: _title('Section 0'),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding
          .resolve(TextDirection.ltr)
          .top;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      final fade = find
          .ancestor(
            of: find.byType(HeaderMaterial).last,
            matching: find.byType(Positioned),
          )
          .first;
      expect(tester.getSize(fade).height, titlePadding);
      await _openPanel(tester);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('sectioned_chip_scroll.panelFade')),
            )
            .height,
        24,
      );
    });

    testWidgets('F2 expand visibility is stable across selected label widths', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          SizedBox(
            width: 300,
            child: SectionedChipScrollView<int>(
              sections: const [
                ChipSection(id: 'a', label: 'A', items: [0, 1, 2, 3, 4, 5]),
                ChipSection(
                  id: 'b',
                  label: 'Wide label',
                  items: [0, 1, 2, 3, 4, 5],
                ),
              ],
              itemBuilder: testItem,
              chipTextStyle: const TextStyle(fontSize: 14),
              selectedChipTextStyle: const TextStyle(fontSize: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visibility = <bool>[];
      for (final label in ['A', 'Wide label', 'A']) {
        final chip = find.text(label).first;
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        visibility.add(find.byIcon(Icons.expand_more).evaluate().isNotEmpty);
      }
      expect(visibility, [true, true, true]);
    });

    for (final categories in [false, true]) {
      testWidgets(
        'F3 anchor uses resized bounds in the first frame categories=$categories',
        (tester) async {
          await screen(
            tester,
            names,
            scale: 3.12,
            size: const Size(320, 568),
            categories: categories,
          );
          await tester.tap(
            find.byIcon(categories ? Icons.unfold_more : Icons.expand_more),
          );
          await tester.pumpAndSettle();
          for (final size in [
            const Size(568, 320),
            const Size(844, 390),
            const Size(932, 430),
          ]) {
            tester.view.physicalSize = size;
            await tester.pump();
            expect(tester.getSize(panel).width, size.width);
            expect(tester.getTopLeft(panel).dy, 100);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }

    testWidgets(
      'F4 landed title keeps header padding and stays below the fade',
      (tester) async {
        await screen(tester, names, scale: 3.12);
        await _openPanel(tester);
        await tester.ensureVisible(find.text('Choice 10').last);
        await _pick(tester, 'Choice 10');
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final title = tester.getRect(_title('Choice 10'));
        expect(title.top - viewport.top, closeTo(12, .1));
        final fade = find.byType(HeaderMaterial).last;
        expect(tester.getRect(fade).bottom, lessThanOrEqualTo(title.top));
        expect(tester.takeException(), isNull);
      },
    );

    for (final categories in [false, true]) {
      for (final scale in [1.0, 3.12]) {
        testWidgets(
          'F5 bottom fade disappears when content fits or reaches end scale=$scale categories=$categories',
          (tester) async {
            BoxDecoration fade() =>
                tester
                        .widget<DecoratedBox>(
                          find.byKey(
                            const ValueKey('sectioned_chip_scroll.panelFade'),
                          ),
                        )
                        .decoration
                    as BoxDecoration;
            await screen(
              tester,
              names.take(3).toList(),
              scale: scale,
              categories: categories,
            );
            await tester.tap(
              find.byIcon(categories ? Icons.unfold_more : Icons.expand_more),
            );
            await tester.pumpAndSettle();
            final fitPosition = tester
                .widget<SingleChildScrollView>(inner)
                .controller!
                .position;
            expect(fitPosition.maxScrollExtent, 0);
            expect(fade().gradient, isNull);
            await tester.tap(find.byIcon(Icons.expand_less));
            await tester.pumpAndSettle();
            await screen(tester, names, scale: scale, categories: categories);
            await tester.tap(
              find.byIcon(categories ? Icons.unfold_more : Icons.expand_more),
            );
            await tester.pumpAndSettle();
            final position = tester
                .widget<SingleChildScrollView>(inner)
                .controller!
                .position;
            expect(position.extentAfter, greaterThan(0));
            expect(fade().gradient, isNotNull);
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(position.extentAfter, 0);
            expect(fade().gradient, isNull);
          },
        );
      }
    }

    testWidgets('C7 open picker follows live width and height on resize', (
      tester,
    ) async {
      await screen(tester, names, scale: 3.12, size: const Size(320, 568));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      for (final size in [
        const Size(430, 932),
        const Size(414, 568),
        const Size(320, 932),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).width, size.width);
        expect(tester.getTopLeft(panel).dy, 100);
        expect(
          tester.getBottomLeft(panel).dy,
          lessThanOrEqualTo(size.height - 56 - 80),
        );
        final close = find
            .ancestor(
              of: find.byIcon(Icons.expand_less),
              matching: find.byType(IconButton),
            )
            .first;
        expect(tester.getRect(close).right, closeTo(size.width, .5));
        expect(
          tester.getCenter(close).dy,
          closeTo(tester.getCenter(header).dy, .5),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'B11 clip height and scrim increase without scaling or overshoot, then reverse',
      (tester) async {
        await screen(tester, names);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pump();
        final reveal = find.byKey(
          const ValueKey('sectioned_chip_scroll.reveal'),
        );
        final heights = <double>[];
        final alphas = <double>[];
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          heights.add(tester.getSize(reveal).height);
          alphas.add(
            tester
                .widget<AnimatedModalBarrier>(
                  find.byType(AnimatedModalBarrier).last,
                )
                .color
                .value!
                .a,
          );
          expect(tester.getSize(panel).height, closeTo(576, .01));
          expect(tester.getRect(panel).size, const Size(375, 576));
          expect(
            find.ancestor(of: panel, matching: find.byType(ClipRect)),
            findsWidgets,
          );
          expect(
            find.ancestor(of: panel, matching: find.byType(ScaleTransition)),
            findsNothing,
          );
        }
        expect(heights.first, inExclusiveRange(0, heights.last));
        for (var i = 1; i < heights.length; i++) {
          expect(heights[i], greaterThanOrEqualTo(heights[i - 1]));
          expect(heights[i], lessThanOrEqualTo(576));
          expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1]));
        }
        expect(alphas.last, closeTo(.24, .01));
        await tester.tap(find.byIcon(Icons.expand_less));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          tester.getSize(reveal).height,
          inExclusiveRange(0, heights.last),
        );
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
      },
    );

    for (final width in [320.0, 375.0, 414.0, 430.0]) {
      testWidgets('Q1 bar fades stop at content edges width=$width', (
        tester,
      ) async {
        await screen(tester, names, size: Size(width, 812));
        final bar = find.byType(SingleChildScrollView).first;
        Future<int> edgeAlpha(double x) async {
          final mask = tester.widget<ShaderMask>(
            find.ancestor(of: bar, matching: find.byType(ShaderMask)).first,
          );
          final size = tester.getSize(bar);
          return (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final rect = Offset.zero & size;
            ui.Canvas(
              recorder,
            ).drawRect(rect, ui.Paint()..shader = mask.shaderCallback(rect));
            final picture = recorder.endRecording();
            final image = await picture.toImage(size.width.ceil(), 1);
            final bytes = (await image.toByteData())!;
            final alpha = bytes.getUint8(x.floor() * 4 + 3);
            image.dispose();
            picture.dispose();
            return alpha;
          }))!;
        }

        Future<void> choose(String label) async {
          await _openPanel(tester);
          await tester.ensureVisible(find.text(label).last);
          await _pick(tester, label);
          final chip = find
              .ancestor(
                of: find.text(label).first,
                matching: find.byType(Material),
              )
              .first;
          final rect = tester.getRect(chip);
          final visible = tester.getRect(bar);
          expect(rect.left, greaterThanOrEqualTo(visible.left - .1));
          expect(rect.right, lessThanOrEqualTo(visible.right + .1));
          expect(
            rect.right,
            lessThanOrEqualTo(
              tester.getRect(find.byIcon(Icons.expand_more)).left,
            ),
          );
        }

        await choose('Choice 34');
        expect(await edgeAlpha(tester.getSize(bar).width - 1), 255);
        // Leading fade present when scrolled past the start.
        expect(await edgeAlpha(0), lessThan(255));
        await choose('A');
        final position = tester
            .widget<SingleChildScrollView>(bar)
            .controller!
            .position;
        expect(position.pixels, 0);
        // Leading fade absent at offset 0.
        expect(await edgeAlpha(0), 255);
        position.jumpTo(position.maxScrollExtent.clamp(1.0, 40.0));
        await tester.pump();
        expect(position.pixels, greaterThan(0));
        expect(await edgeAlpha(0), lessThan(255));
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [320.0, 375.0, 430.0, 768.0]) {
      for (final label in [names[2], 'Choice 10']) {
        testWidgets(
          'G1 selected label stays opaque under bar fade width=$width label=$label',
          (tester) async {
            await screen(tester, names, size: Size(width, 812));
            final bar = find.byType(SingleChildScrollView).first;
            Future<int> alphaAt(double x) async {
              final mask = tester.widget<ShaderMask>(
                find.ancestor(of: bar, matching: find.byType(ShaderMask)).first,
              );
              final size = tester.getSize(bar);
              return (await tester.runAsync(() async {
                final recorder = ui.PictureRecorder();
                final rect = Offset.zero & size;
                ui.Canvas(recorder).drawRect(
                  rect,
                  ui.Paint()..shader = mask.shaderCallback(rect),
                );
                final picture = recorder.endRecording();
                final image = await picture.toImage(size.width.ceil(), 1);
                final bytes = (await image.toByteData())!;
                final alpha = bytes.getUint8(
                  x.floor().clamp(0, size.width.ceil() - 1) * 4 + 3,
                );
                image.dispose();
                picture.dispose();
                return alpha;
              }))!;
            }

            await _openPanel(tester);
            await tester.ensureVisible(find.text(label).last);
            await _pick(tester, label);
            final text = find.text(label).first;
            final barRect = tester.getRect(bar);
            final labelRect = tester.getRect(text);
            expect(await alphaAt(labelRect.left - barRect.left), 255);
            expect(await alphaAt(labelRect.right - barRect.left - 1), 255);
            final position = tester
                .widget<SingleChildScrollView>(bar)
                .controller!
                .position;
            // Fade width equals the leading inset on each active side.
            if (position.pixels > 0) {
              const inset = 12.0;
              expect(await alphaAt(0), lessThan(255));
              expect(await alphaAt(inset + 1), 255);
            }
            if (position.extentAfter > 0) {
              const inset = 12.0;
              final end = tester.getSize(bar).width;
              expect(await alphaAt(end - 1), lessThan(255));
              expect(await alphaAt(end - inset - 1), 255);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final direction in TextDirection.values) {
      testWidgets(
        'C1 bar follows 48px from leading edge and clamps at both ends $direction',
        (tester) async {
          await screen(tester, names, direction: direction);
          Future<void> choose(String label) async {
            await tester.tap(find.byIcon(Icons.expand_more));
            await tester.pumpAndSettle();
            final pick = find.descendant(of: panel, matching: find.text(label));
            await tester.ensureVisible(pick);
            await tester.tap(pick);
            await tester.pumpAndSettle();
          }

          double leading(String label) {
            final chip = find
                .ancestor(
                  of: find.text(label).first,
                  matching: find.byType(Material),
                )
                .first;
            final viewport = find
                .ancestor(
                  of: chip,
                  matching: find.byType(SingleChildScrollView),
                )
                .first;
            final rect = tester.getRect(chip);
            final bar = tester.getRect(viewport);
            expect(rect.left, greaterThanOrEqualTo(bar.left));
            expect(rect.right, lessThanOrEqualTo(bar.right));
            return direction == TextDirection.ltr
                ? rect.left - bar.left
                : bar.right - rect.right;
          }

          await choose('Choice 10');
          expect(leading('Choice 10'), closeTo(48, .1));
          await choose('A');
          expect(leading('A'), closeTo(12, .1));
          await choose('Choice 34');
          expect(leading('Choice 34'), greaterThanOrEqualTo(48));
        },
      );
    }

    for (final scrim in [false, true]) {
      testWidgets(
        'C4 overridable action labels and focus return scrim=$scrim',
        (tester) async {
          final handle = tester.ensureSemantics();
          await screen(tester, names);
          final icon = find.byIcon(Icons.expand_more);
          final focus = Focus.of(tester.element(icon));
          focus.requestFocus();
          await tester.pump();
          expect(focus.hasPrimaryFocus, isTrue);
          expect(
            tester.getSemantics(icon),
            containsSemantics(isButton: true, hasTapAction: true),
          );
          expect(
            tester.getSemantics(icon).getSemanticsData().tooltip,
            'Open sections',
          );
          await tester.tap(icon);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(find.byIcon(Icons.expand_less)),
            containsSemantics(isButton: true, hasTapAction: true),
          );
          expect(
            tester
                .getSemantics(find.byIcon(Icons.expand_less))
                .getSemanticsData()
                .tooltip,
            'Collapse sections',
          );
          expect(find.bySemanticsLabel('Dismiss sections'), findsOneWidget);
          if (scrim) {
            await tester.tapAt(const Offset(180, 710));
          } else {
            await tester.tap(find.byIcon(Icons.expand_less));
          }
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
          expect(focus.hasPrimaryFocus, isTrue);
          handle.dispose();
        },
      );
    }

    testWidgets('appearance hooks reach chip and panel materials', (
      tester,
    ) async {
      const style = SectionedChipScrollStyle.outlined(
        chipBackground: Colors.yellow,
        selectedChipBackground: Colors.blue,
        selectedChipBorder: BorderSide(color: Colors.orange, width: 3),
        chipMinHeight: 60,
        chipPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        chipShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        panelBackground: Colors.pink,
        panelBottomRadius: 25,
        panelShadowColor: Colors.green,
        panelElevation: 12,
        scrimColor: Colors.purple,
        scrimOpacity: .4,
      );
      expect(const SectionedChipScrollLabels().panelTitle, isEmpty);
      expect(const SectionedChipScrollLabels().categoryPanelTitle, isEmpty);
      expect(style.copyWith(), style);
      await tester.pumpWidget(
        testApp(
          SizedBox(
            width: 320,
            child: SectionedChipScrollView<int>(
              sections: testSections(List.filled(8, 3)),
              itemBuilder: testItem,
              style: style,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = find
          .ancestor(
            of: find.text('Section 0').first,
            matching: find.byType(Material),
          )
          .first;
      final material = tester.widget<Material>(chip);
      expect(material.color!.toARGB32(), Colors.blue.toARGB32());
      final border = (material.shape! as OutlinedBorder).side;
      expect(border.width, 3);
      expect(border.color.toARGB32(), Colors.orange.toARGB32());
      expect(tester.getSize(chip).height, 60);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      final surface = tester.widget<Material>(panel);
      expect(surface.color, Colors.pink);
      expect(surface.shadowColor, Colors.green);
      expect(surface.elevation, 12);
      expect(
        (surface.shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(bottom: Radius.circular(25)),
      );
      final barrier = tester.widget<AnimatedModalBarrier>(
        find.byType(AnimatedModalBarrier).last,
      );
      expect(barrier.color.value, Colors.purple.withValues(alpha: .4));
    });

    testWidgets(
      'B12-B14 C1 C2 measured AX5 far jump is smooth, stable, exact, and spy follows',
      (tester) async {
        final selected = <String>[];
        await screen(
          tester,
          names,
          scale: 3.12,
          onSelected: (s) => selected.add(s.id),
        );
        final position = listPosition(tester);
        expect(_state(tester).geometry!.sections[10].top, isNull);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();
        final pick = find.descendant(
          of: panel,
          matching: find.text('Choice 10'),
        );
        await tester.ensureVisible(pick);
        await tester.tap(pick);
        final offsets = <double>[];
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (offsets.isEmpty || offsets.last != position.pixels) {
            offsets.add(position.pixels);
          }
          if (_state(tester).navigationPhase == 'moving') {
            expect(selected, ['s10']);
          }
          if (_state(tester).navigationPhase == null) break;
        }
        await tester.pumpAndSettle();
        expect(offsets.length, greaterThan(5));
        expect(selected, ['s10']);
        expect(_offsetError(tester, 'Choice 10'), closeTo(0, .1));
        final chip = find
            .ancestor(
              of: find.text('Choice 10').first,
              matching: find.byType(Material),
            )
            .first;
        final bar = tester.getRect(find.byType(HeaderMaterial).first);
        final rect = tester.getRect(chip);
        final buttonWidth = tester
            .getSize(
              find
                  .ancestor(
                    of: find.byIcon(Icons.expand_more),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .width;
        final margin = (bar.width - buttonWidth - rect.width).clamp(0.0, 48.0);
        expect(rect.left, closeTo(bar.left + margin, .1));
        expect(rect.right, lessThanOrEqualTo(bar.right - buttonWidth));
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expect(selected.last, isNot('s10'));
        final label = names[int.parse(selected.last.substring(1))];
        final spyChip = find
            .ancestor(
              of: find.text(label).first,
              matching: find.byType(Material),
            )
            .first;
        final spyRect = tester.getRect(spyChip);
        expect(spyRect.left, greaterThanOrEqualTo(bar.left));
        expect(spyRect.right, lessThanOrEqualTo(bar.right - buttonWidth));
        expect(tester.takeException(), isNull);
      },
    );
  });

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
        testApp(
          _view(
            s,
            layout: const SectionedLayout.grid(),
            onSectionSelected: (x) => selected.add(x.id),
          ),
        ),
      );
      final all = testSections([2, 2, 2]);
      await show(all);
      await tester.ensureVisible(find.text('Section 1').first);
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

    for (final scale in [1.0, 3.12]) {
      testWidgets(
        'R5-1 picked long chip keeps inset and ellipsis scale=$scale',
        (tester) async {
          const label =
              'A very long section name that must remain ellipsized '
              'after the longest chip is selected';
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(375, 812);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: _view([
                    ...testSections([8, 8, 8]),
                    const ChipSection(
                      id: 'long',
                      label: label,
                      items: [0, 1, 2],
                    ),
                  ]),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _openPanel(tester);
          await tester.ensureVisible(find.text(label).last);
          await _pick(tester, label);
          final chip = find.byWidgetPredicate(
            (w) => w is ChipControl && w.selected && w.label == label,
          );
          final inset =
              const SectionedChipScrollStyle.outlined().chipBarLeadingInset;
          expect(tester.getRect(chip).left, greaterThanOrEqualTo(inset - .5));
          final text = find.descendant(of: chip, matching: find.text(label));
          expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isTrue);
          expect(paragraph.overflow, TextOverflow.ellipsis);
        },
      );
    }

    testWidgets('a long chip label stays on one line with ellipsis', (
      tester,
    ) async {
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
      expect(tester.getSize(find.text(long).first).height, short);
      expect(
        tester.widget<Text>(find.text(long).first).overflow,
        TextOverflow.ellipsis,
      );
    });
  });

  group('jump', () {
    // Short first sections and tall later ones make SliverList's extent
    // estimate for unbuilt sections wrong, so the first move stops short.
    final misestimated = testSections([1, 1, 1, ...List.filled(11, 12)]);

    testWidgets('long tail aligns without an estimated jump or retry', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_view(misestimated)));
      await _openPanel(tester);
      await _pick(tester, 'Section 10');
      expect(_offsetError(tester, 'Section 10').abs(), lessThan(1));
      expect(_state(tester).navigationPhase, isNull);
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
      // Inside the spring after real geometry preparation.
      for (var i = 0; i < 80 && listPosition(tester).pixels == 0; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(listPosition(tester).pixels, greaterThan(0));
      // One tap: the chip bar is outside the animating scroll view.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Section 4').first);
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
      expect(
        tester.getSemantics(find.bySemanticsLabel('Section 0, 1 of 14')),
        containsSemantics(isSelected: true),
      );
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
      expect(
        tester.getSemantics(find.bySemanticsLabel('Section 0, 1 of 14')),
        containsSemantics(isSelected: true),
      );
    });

    testWidgets('settling row geometry retargets the jump and still lands', (
      tester,
    ) async {
      // Section 5 above the target grows once after first layout (A1 settle).
      const grower = -1;
      Widget item(BuildContext c, int i) =>
          i == grower ? const _SettlingTile(index: grower) : testItem(c, i);
      final s = [
        ...testSections(List.filled(5, 12)),
        const ChipSection(id: 's5', label: 'Section 5', items: [grower]),
        ...testSections(List.filled(7, 12)).skip(6),
      ];
      await tester.pumpWidget(testApp(_view(s, itemBuilder: item)));
      await _openPanel(tester);
      await tester.tap(find.text('Section 6').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_state(tester).navigationPhase, isNull);
      expect(_offsetError(tester, 'Section 6').abs(), lessThan(1));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 50000),
        8000,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Section 0, 1 of 7')),
        containsSemantics(isSelected: true),
      );
    });
  });

  group('A1 A2 slow far jump', () {
    /// Grows once after the first layout, like Android release content settle.
    Widget settlingItem(BuildContext context, int i) => _SettlingTile(index: i);

    testWidgets('A3 opening many records built and measured rows', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      final built = <int>{};
      await tester.pumpWidget(
        testApp(
          SectionedChipScrollView<int>(
            sections: [
              for (var s = 0; s < 35; s++)
                ChipSection(
                  id: 's$s',
                  label: 'Category $s',
                  items: List.generate(8, (r) => s * 100 + r),
                ),
            ],
            itemBuilder: (c, i) {
              built.add(i);
              return testItem(c, i);
            },
          ),
        ),
      );
      final firstFrame = built.length;
      await tester.pumpAndSettle();
      final geometry = _state(tester).geometry!;
      final measured = geometry.sections.fold<int>(
        0,
        (sum, s) => sum + s.rowExtents.whereType<double>().length,
      );
      final touched = built.map((i) => i ~/ 100).toSet().length;
      expect(touched, 1);
      expect(measured, lessThan(35 * 8));
      debugPrint(
        'A3 opening: first-frame rows=$firstFrame; settled built=${built.length}; measured=$measured; sections=$touched/35; total rows=280',
      );
    });

    testWidgets('A1 far pick lands under slow frames and settling row heights', (
      tester,
    ) async {
      final built = <int>{};
      Widget countedItem(BuildContext context, int i) {
        built.add(i);
        return settlingItem(context, i);
      }

      final selected = <String>[];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      final sections = [
        for (var s = 0; s < 35; s++)
          ChipSection(
            id: 's$s',
            label: 'Category $s',
            items: List.generate(40, (r) => s * 100 + r),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionedChipScrollView<int>(
              sections: sections,
              itemBuilder: countedItem,
              sectionDecoration: const BoxDecoration(
                border: Border.fromBorderSide(BorderSide(width: 8)),
              ),
              onSectionSelected: (s) => selected.add(s.id),
              labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_state(tester).geometry!.sections[30].top, isNull);
      await _openPanel(tester);
      final pick = find.text('Category 30').last;
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      final before = listPosition(tester).pixels;
      built.clear();
      final offsets = <double>{before};
      final position = listPosition(tester);
      void recordOffset() => offsets.add(position.pixels);
      position.addListener(recordOffset);
      await tester.tap(pick);
      // Pick frame: selection commits and motion must start.
      await tester.pump();
      expect(selected, ['s30']);
      expect(_state(tester).navigationPhase, isNotNull);
      await tester.pump(const Duration(milliseconds: 100));
      debugPrint(
        'A1 first100ms: before=$before; offset=${listPosition(tester).pixels}',
      );
      expect(
        listPosition(tester).pixels,
        greaterThan(before),
        reason: 'far pick must move in the first slow frame',
      );
      // T-d counts only animation samples after the initial pre-jump.
      offsets.clear();
      expect(
        built.where((i) => i ~/ 100 >= 1 && i ~/ 100 <= 27 && i % 100 != 39),
        isEmpty,
        reason: 'do not build the intervening section rows',
      );
      // Slow device: large frame gaps while rows settle and remeasure.
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (_state(tester).navigationPhase == null) break;
      }
      await tester.pumpAndSettle();
      expect(listPosition(tester).pixels, greaterThan(before));
      expect(
        built.where((i) => i ~/ 100 >= 1 && i ~/ 100 <= 27 && i % 100 != 39),
        isEmpty,
        reason: 'far pick must not measure the intervening prefix',
      );
      expect(_offsetError(tester, 'Category 30'), closeTo(0, 1));
      expect(selected.last, 's30');
      expect(_state(tester).navigationPhase, isNull);
      expect(
        offsets.length,
        greaterThan(2),
        reason: 'T-d: A1 must animate after its pre-jump',
      );
      position.removeListener(recordOffset);
    });

    testWidgets('A2 far pick starts moving within 100ms and animates at AX5', (
      tester,
    ) async {
      final selected = <String>[];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.12)),
            child: Scaffold(
              body: SectionedChipScrollView<int>(
                sections: testSections(List.filled(35, 8), 'Category'),
                itemBuilder: settlingItem,
                layout: const SectionedLayout.list(),
                onSectionSelected: (s) => selected.add(s.id),
                labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openPanel(tester);
      final pick = find.text('Category 30').last;
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      final before = listPosition(tester).pixels;
      await tester.tap(pick);
      await tester.pump();
      expect(selected, ['s30']);
      final offsets = <double>[before];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final pixels = listPosition(tester).pixels;
        if (offsets.last != pixels) offsets.add(pixels);
      }
      expect(
        offsets.any((o) => o > before),
        isTrue,
        reason: 'list must start moving within ~100ms of the pick',
      );
      expect(
        offsets.length,
        greaterThan(2),
        reason: 'far jump must animate, not teleport',
      );
      for (var i = 0; i < 200 && _state(tester).navigationPhase != null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(_offsetError(tester, 'Category 30'), closeTo(0, 1));
      expect(selected.last, 's30');
    });
  });

  group('T1 panel tap after fling', () {
    final many = [
      for (var i = 0; i < 35; i++)
        ChipSection(
          id: 's$i',
          label: 'Category $i',
          items: List.generate(8, (j) => j),
        ),
    ];
    final panelScroll = find.byKey(
      const ValueKey('sectioned_chip_scroll.panelScroll'),
    );

    Future<void> pumpAx5(WidgetTester tester, List<String> selected) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.12)),
            child: Scaffold(
              body: SectionedChipScrollView<int>(
                sections: many,
                itemBuilder: testItem,
                layout: const SectionedLayout.list(),
                config: const SectionedChipScrollConfig(panelBottomInset: 56),
                labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
                onSectionSelected: (s) => selected.add(s.id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openPanel(tester);
    }

    testWidgets('T1a tap after panel fling settles picks at AX5', (
      tester,
    ) async {
      final selected = <String>[];
      await pumpAx5(tester, selected);
      await tester.fling(panelScroll, const Offset(0, -3000), 4000);
      await tester.pumpAndSettle();
      const label = 'Category 25';
      final chip = find.text(label).last;
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sectioned_chip_scroll.panel')),
        findsNothing,
      );
      expect(selected, ['s25']);
    });

    testWidgets('T1b tap during panel ballistic picks at AX5', (tester) async {
      final selected = <String>[];
      await pumpAx5(tester, selected);
      await tester.ensureVisible(find.text('Category 20').last);
      await tester.pumpAndSettle();
      final position = tester
          .widget<SingleChildScrollView>(panelScroll)
          .controller!
          .position;
      await tester.fling(panelScroll, const Offset(0, -2000), 3000);
      // Wait until motion is below the platform touch slop, but not settled.
      final slop = kTouchSlop;
      var frames = 0;
      while (frames < 120) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        final activity = position.activity;
        if (activity is BallisticScrollActivity) {
          final velocity = activity.velocity.abs();
          if (velocity > 0 && velocity <= slop * 60) break;
        } else if (position.isScrollingNotifier.value == false) {
          break;
        }
      }
      // Tap a chip whose center clears the fixed panel header.
      final panel = find.byKey(const ValueKey('sectioned_chip_scroll.panel'));
      final headerBottom = tester
          .getRect(
            find.byKey(const ValueKey('sectioned_chip_scroll.panelHeader')),
          )
          .bottom;
      final panelRect = tester.getRect(panel);
      String? tapped;
      for (var i = 0; i < 35; i++) {
        final label = 'Category $i';
        final text = find.text(label);
        if (text.evaluate().isEmpty) continue;
        final rect = tester.getRect(text.last);
        if (rect.center.dy > headerBottom + 4 &&
            panelRect.contains(rect.center)) {
          await tester.tap(text.last);
          tapped = 's$i';
          break;
        }
      }
      expect(tapped, isNotNull, reason: 'need a visible chip to tap');
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(selected, [tapped]);
    });
  });

  group('G3 landing matrix', () {
    final uneven = testSections([1, 1, 1, ...List.filled(11, 12)]);
    final even = testSections(List.filled(14, 6));

    Future<void> pumpSized(
      WidgetTester tester, {
      required Size size,
      required double scale,
      required List<ChipSection<int>> sections,
      SectionedLayout layout = const SectionedLayout.list(),
      ValueChanged<ChipSection<int>>? onSelected,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: _view(
                sections,
                layout: layout,
                onSectionSelected: onSelected,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 3.12]) {
      testWidgets('G3 grid exact landing uneven scale=$scale', (tester) async {
        await pumpSized(
          tester,
          size: const Size(375, 812),
          scale: scale,
          sections: uneven,
          layout: const SectionedLayout.grid(),
        );
        await _openPanel(tester);
        await tester.ensureVisible(find.text('Section 10').last);
        await _pick(tester, 'Section 10');
        expect(_offsetError(tester, 'Section 10'), closeTo(0, .1));
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [320.0, 430.0]) {
      for (final height in [568.0, 932.0]) {
        for (final scale in [1.0, 3.12]) {
          for (final target in [1, 7, 12]) {
            testWidgets(
              'G3 list landing+spy w=$width h=$height scale=$scale t=$target',
              (tester) async {
                final selected = <String>[];
                await pumpSized(
                  tester,
                  size: Size(width, height),
                  scale: scale,
                  sections: even,
                  onSelected: (s) => selected.add(s.id),
                );
                await _openPanel(tester);
                await tester.ensureVisible(find.text('Section $target').last);
                await _pick(tester, 'Section $target');
                expect(selected.last, 's$target');
                expect(_offsetError(tester, 'Section $target'), closeTo(0, .1));
                await tester.fling(
                  find.byType(CustomScrollView),
                  Offset(0, target <= 1 ? -5000 : 5000),
                  5000,
                );
                await tester.pumpAndSettle();
                expect(selected.last, isNot('s$target'));
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });

  group('stage 2', () {
    Widget scene(
      List<ChipSection<int>> sections, {
      required bool rail,
      double scale = 1,
      bool reduced = false,
      SectionedChipScrollStyle style =
          const SectionedChipScrollStyle.outlined(),
      Decoration? decoration,
      ValueChanged<ChipSection<int>>? selected,
      Widget Function(BuildContext, int) item = testItem,
      double width = 390,
      String categoryId = 'a',
    }) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            supportsAnnounce: true,
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: CategorizedChipScrollView<int>(
                labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
                categories: [
                  SectionCategory(
                    id: categoryId,
                    label: 'Main',
                    sections: sections,
                  ),
                  if (rail)
                    SectionCategory(
                      id: 'b',
                      label: 'Other',
                      sections: testSections([6, 6]),
                    ),
                ],
                itemBuilder: item,
                style: style,
                sectionDecoration: decoration,
                onSectionSelected: selected,
                config: const CategorizedChipScrollConfig(
                  railWidth: 72,
                  sectionConfig: SectionedChipScrollConfig(
                    focusAfterNavigate: FocusAfterNavigate.announce,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> phase(WidgetTester tester, String expected) async {
      for (
        var i = 0;
        i < 40 && _state(tester).navigationPhase != expected;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_state(tester).navigationPhase, expected);
    }

    for (final rail in [false, true]) {
      for (final scale in [1.0, 2.0, 3.12]) {
        for (final uneven in [false, true]) {
          testWidgets(
            'visible one move rail=$rail scale=$scale uneven=$uneven',
            (tester) async {
              final data = testSections(
                uneven ? [1, 1, 1, ...List.filled(11, 12)] : List.filled(14, 6),
              );
              final selected = <String>[];
              await tester.pumpWidget(
                scene(
                  data,
                  rail: rail,
                  scale: scale,
                  selected: (s) => selected.add(s.id),
                ),
              );
              await tester.pumpAndSettle();
              final position = listPosition(tester);
              final offsets = <double>[position.pixels];
              position.addListener(() {
                if (offsets.last != position.pixels) {
                  offsets.add(position.pixels);
                }
              });
              await _openPanel(tester);
              await tester.ensureVisible(find.text('Section 10').last);
              await _pick(tester, 'Section 10');
              final header = tester.getRect(_title('Section 10'));
              final viewport = tester.getRect(find.byType(CustomScrollView));
              expect(header.overlaps(viewport), isTrue);
              if (uneven) {
                expect(_offsetError(tester, 'Section 10'), closeTo(0, .1));
              }
              expect(
                offsets.length,
                greaterThan(3),
                reason: 'far navigation has intermediate animation frames',
              );
              expect(offsets.last, greaterThan(offsets.first));
              expect(selected, ['s10']);
              expect(tester.takeAnnouncements().map((a) => a.message), [
                'Section 10',
              ]);
              expect(_state(tester).navigationPhase, isNull);
            },
          );
        }
      }

      for (final preparing in [true, false]) {
        for (final cause in [
          'tap',
          'drag',
          'category',
          'data',
          'rotation',
          'scale',
          'insets',
          'row',
          'dispose',
        ]) {
          testWidgets('cancel $cause preparing=$preparing rail=$rail', (
            tester,
          ) async {
            var data = testSections(List.filled(14, 6));
            var scale = 1.0;
            var width = 390.0;
            var categoryId = 'a';
            Decoration? decoration;
            final height = ValueNotifier(120.0);
            addTearDown(height.dispose);
            final selected = <String>[];
            Widget tile(BuildContext c, int i) =>
                ValueListenableBuilder<double>(
                  valueListenable: height,
                  builder: (_, h, _) =>
                      SizedBox(height: h, child: Text('tile $i')),
                );
            Widget build() => scene(
              data,
              rail: rail,
              scale: scale,
              width: width,
              categoryId: categoryId,
              decoration: decoration,
              item: tile,
              selected: (s) => selected.add(s.id),
            );
            await tester.pumpWidget(build());
            await tester.pumpAndSettle();
            final target = preparing ? 10 : 1;
            await tester.ensureVisible(find.text('Section $target').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Section $target').first);
            await phase(tester, preparing ? 'preparing' : 'moving');
            if (!preparing) await tester.pump(const Duration(milliseconds: 64));
            expect(selected, [
              's$target',
            ], reason: 'pick selects immediately; spy stays muted');
            final before = listPosition(tester).pixels;
            expect(tester.takeAnnouncements(), isEmpty);
            switch (cause) {
              case 'tap':
                await tester.ensureVisible(find.text('Section 0').first);
                await tester.tap(find.text('Section 0').first);
              case 'drag':
                final gesture = await tester.startGesture(
                  tester.getCenter(find.byType(CustomScrollView)),
                );
                await tester.pump(const Duration(milliseconds: 64));
                expect(listPosition(tester).pixels, closeTo(before, 0.01));
                await gesture.moveBy(const Offset(0, 25));
                await gesture.up();
              case 'category':
                if (rail) {
                  await tester.tap(find.text('Other'));
                } else {
                  // The no-rail category is replaced with a new category id.
                  categoryId = 'replacement';
                  await tester.pumpWidget(build());
                }
              case 'data':
                data = [
                  ...data.take(13),
                  const ChipSection(id: 's13', label: 'changed', items: [1]),
                ];
                await tester.pumpWidget(build());
              case 'rotation':
                width = 360;
                await tester.pumpWidget(build());
              case 'scale':
                scale = 1.2;
                await tester.pumpWidget(build());
              case 'insets':
                decoration = const BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(width: 8)),
                );
                await tester.pumpWidget(build());
              case 'row':
                height.value = 140;
                // Rebuild real rows without replacing the public builder.
                await tester.pumpWidget(build());
              case 'dispose':
                await tester.pumpWidget(const SizedBox());
            }
            await tester.pumpAndSettle();
            // Row-height settle must not cancel (A1); other causes still cancel.
            if (cause == 'row') {
              expect(
                tester.takeAnnouncements().map((a) => a.message),
                contains('Section $target'),
              );
              expect(
                _offsetError(tester, 'Section $target').abs(),
                lessThan(1),
              );
            } else {
              expect(
                tester.takeAnnouncements().map((a) => a.message),
                isNot(contains('Section $target')),
              );
            }
            expect(selected.first, 's$target');
            if (cause != 'dispose' && !(cause == 'category' && !rail)) {
              expect(_state(tester).navigationPhase, isNull);
              final stopped = listPosition(tester).pixels;
              await tester.pump(const Duration(seconds: 1));
              expect(
                listPosition(tester).pixels,
                closeTo(stopped, 0.01),
                reason: 'cancel never re-drives',
              );
              if (['rotation', 'scale', 'insets', 'data'].contains(cause)) {
                expect(
                  stopped,
                  closeTo(before, 0.01),
                  reason: 'cancel does not roll back',
                );
              }
            }
            expect(tester.takeException(), isNull);
          });
        }
      }

      for (final dismiss in [
        'barrier',
        'back',
        'pick',
        'stale-data',
        'stale-geometry',
      ]) {
        testWidgets('section picker $dismiss rail=$rail', (tester) async {
          var data = testSections(List.filled(14, 6));
          var scale = 1.0;
          final selected = <String>[];
          Widget build() => scene(
            data,
            rail: rail,
            scale: scale,
            style: const SectionedChipScrollStyle.outlined(
              pickerTransition: PickerTransition.clipReveal,
            ),
            selected: (s) => selected.add(s.id),
          );
          await tester.pumpWidget(build());
          await tester.pumpAndSettle();
          await _openPanel(tester);
          final route =
              ModalRoute.of(tester.element(find.text('Sections')))!
                  as TransitionRoute<void>;
          if (dismiss == 'barrier') {
            await tester.tapAt(const Offset(780, 590));
          } else if (dismiss == 'back') {
            Navigator.of(tester.element(find.text('Sections'))).pop();
          } else {
            await tester.ensureVisible(find.text('Section 10').last);
            await tester.tap(find.text('Section 10').last);
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          final picked = !['barrier', 'back'].contains(dismiss);
          expect(listPosition(tester).pixels, picked ? greaterThan(0) : 0);
          expect(selected, picked ? ['s10'] : isEmpty);
          if (dismiss == 'stale-data') {
            data = [
              ...data.take(13),
              const ChipSection(id: 's13', label: 'new', items: [0]),
            ];
            await tester.pumpWidget(build());
          } else if (dismiss == 'stale-geometry') {
            scale = 1.2;
            await tester.pumpWidget(build());
          }
          await tester.pumpAndSettle();
          if (picked) {
            expect(selected.first, 's10');
          } else {
            expect(selected, isEmpty);
          }
          expect(
            tester.takeAnnouncements().map((a) => a.message),
            dismiss == 'pick' ? ['Section 10'] : isEmpty,
          );
          if (!picked) expect(listPosition(tester).pixels, 0);
        });
      }

      testWidgets('prefix preparation stops before unrelated suffix rail=$rail', (
        tester,
      ) async {
        final built = <int>{};
        var live = 0;
        var peak = 0;
        final keys = <int, GlobalKey>{};
        void life(int delta) {
          live += delta;
          if (live > peak) peak = live;
        }

        final data = [
          for (var s = 0; s < 12; s++)
            ChipSection(
              id: 's$s',
              label: 'Section $s',
              items: List.generate(30, (i) => s * 100 + i),
            ),
        ];
        final watch = Stopwatch();
        await tester.pumpWidget(
          scene(
            data,
            rail: rail,
            item: (c, i) {
              built.add(i);
              return _LiveTile(
                key: keys.putIfAbsent(i, GlobalKey.new),
                onLife: life,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        await _openPanel(tester);
        watch.start();
        await _pick(tester, 'Section 3');
        watch.stop();
        expect(
          built.any((i) => i >= 600),
          isFalse,
          reason: 'prepare prefix and viewport suffix',
        );
        expect(
          tester
              .getRect(_title('Section 3'))
              .overlaps(tester.getRect(find.byType(CustomScrollView))),
          isTrue,
        );
        debugPrint(
          'PREP rail=$rail uniqueTiles=${built.length} peakLive=$peak finalLive=$live navigationWallMs=${watch.elapsedMilliseconds}',
        );
      });

      testWidgets('explicit short tail and spy ranges rail=$rail', (
        tester,
      ) async {
        final selected = <String>[];
        await tester.pumpWidget(
          scene(
            testSections([...List.filled(6, 12), 1, 1]),
            rail: rail,
            selected: (s) => selected.add(s.id),
          ),
        );
        await _openPanel(tester);
        await _pick(tester, 'Section 6');
        expect(selected.last, 's6');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
        await tester.pumpAndSettle();
        expect(selected.last, 's6');
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(selected.last, 's7');
      });

      testWidgets('near spring and reduced motion rail=$rail', (tester) async {
        for (final reduced in [false, true]) {
          await tester.pumpWidget(const SizedBox());
          final selected = <String>[];
          await tester.pumpWidget(
            scene(
              testSections(List.filled(14, 6)),
              rail: rail,
              reduced: reduced,
              selected: (s) => selected.add(s.id),
            ),
          );
          await tester.pumpAndSettle();
          final position = listPosition(tester);
          final offsets = <double>[position.pixels];
          position.addListener(() {
            if (offsets.last != position.pixels) offsets.add(position.pixels);
          });
          await tester.tap(find.text('Section 1').first);
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(_title('Section 1'))
                .overlaps(tester.getRect(find.byType(CustomScrollView))),
            isTrue,
          );
          for (var i = 1; i < offsets.length; i++) {
            expect(offsets[i], greaterThanOrEqualTo(offsets[i - 1]));
          }
          expect(offsets.length, reduced ? 2 : greaterThan(2));
          expect(selected, ['s1']);
          expect(tester.takeAnnouncements().map((a) => a.message), [
            'Section 1',
          ]);
        }
      });
    }

    testWidgets(
      'parent rebuild with new closure preserves geometry and chip tap reaches target',
      (tester) async {
        final selected = <String>[];
        Widget build(int seed) => testApp(
          SectionedChipScrollView<int>(
            sections: testSections(List.filled(14, 3)),
            itemBuilder: (context, item) =>
                SizedBox(height: 120, child: Text('item $item ($seed)')),
            layout: const SectionedLayout.grid(),
            onSectionSelected: (s) => selected.add(s.id),
          ),
        );
        await tester.pumpWidget(build(0));
        await tester.pumpAndSettle();
        final state = _state(tester);
        expect(state.geometry!.sections[3].top, isNotNull);

        // Parent rebuilds with fresh closure
        await tester.pumpWidget(build(1));
        await tester.pump();

        expect(state.geometry!.sections[3].top, isNotNull);

        // Tap Section 3 chip
        await tester.tap(find.text('Section 3').first);
        await tester.pumpAndSettle();
        expect(selected, contains('s3'));
        expect(state.navigationPhase, isNull);
      },
    );

    testWidgets('parent rebuild mid-jump does not cancel jump', (tester) async {
      final selected = <String>[];
      Widget build(int capture) => testApp(
        SectionedChipScrollView<int>(
          sections: testSections(List.filled(14, 3)),
          itemBuilder: (context, item) =>
              SizedBox(height: 120, child: Text('item $item capture=$capture')),
          onSectionSelected: (s) => selected.add(s.id),
        ),
      );
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();

      // Tap Section 3 chip (within near spring path)
      await tester.tap(find.text('Section 3').first);
      for (
        var i = 0;
        i < 40 && _state(tester).navigationPhase != 'moving';
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_state(tester).navigationPhase, 'moving');
      await tester.pump(const Duration(milliseconds: 64));

      // Unrelated parent rebuild mid-jump with equal data but new closure
      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();

      expect(selected, contains('s3'));
      expect(_state(tester).navigationPhase, isNull);
    });

    testWidgets('columnsBuilder with non-grid layout asserts', (tester) async {
      expect(
        () => SectionedChipScrollView<int>(
          sections: testSections([3]),
          itemBuilder: testItem,
          layout: const SectionedLayout.list(),
          columnsBuilder: (w, s) => 2,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('inline columnsBuilder does not cancel running jump', (
      tester,
    ) async {
      final selected = <String>[];
      Widget build(int seed) => testApp(
        SectionedChipScrollView<int>(
          sections: testSections(List.filled(14, 3)),
          columnsBuilder: (w, t) => 3 + (seed * 0),
          layout: const SectionedLayout.grid(),
          itemBuilder: testItem,
          onSectionSelected: (s) => selected.add(s.id),
        ),
      );
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Section 3').first);
      for (
        var i = 0;
        i < 40 && _state(tester).navigationPhase != 'moving';
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_state(tester).navigationPhase, 'moving');
      await tester.pump(const Duration(milliseconds: 64));

      // Parent rebuild with new closure instance for columnsBuilder
      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();

      expect(selected, contains('s3'));
      expect(_state(tester).navigationPhase, isNull);
    });
  });

  group('polish', () {
    testWidgets(
      'pointer down responds before commit and dragging away cancels',
      (tester) async {
        final selected = <String>[];
        await tester.pumpWidget(
          testApp(
            _view(
              testSections([6, 6]),
              onSectionSelected: (s) => selected.add(s.id),
            ),
          ),
        );
        final label = find.text('Section 1').first;
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        final feedback = find
            .ancestor(of: label, matching: find.byType(PressFeedback))
            .first;
        final down = await tester.startGesture(tester.getCenter(label));
        await tester.pump();
        final highlight = find.descendant(
          of: feedback,
          matching: find.byType(ColoredBox),
        );
        expect(
          tester.widget<ColoredBox>(highlight.first).color.a,
          greaterThan(0),
        );
        expect(selected, isEmpty);
        await tester.pump(const Duration(milliseconds: 80));
        final transform = find
            .descendant(of: feedback, matching: find.byType(Transform))
            .first;
        expect(
          tester.widget<Transform>(transform).transform.entry(0, 0),
          lessThan(1),
        );
        await down.moveBy(const Offset(0, 100));
        await down.up();
        await tester.pumpAndSettle();
        expect(selected, isEmpty);
        expect(tester.widget<ColoredBox>(highlight.first).color.a, 0);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(selected.last, 's1');
      },
    );

    testWidgets('spring retargets from the presentation value', (tester) async {
      Widget spring(double value) => testApp(
        SpringValue(
          value: value,
          style: const SectionedChipScrollStyle.outlined(),
          builder: (_, x) => Transform.translate(
            key: const ValueKey('spring-value'),
            offset: Offset(x, 0),
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      await tester.pumpWidget(spring(0));
      await tester.pumpWidget(spring(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      double position() => tester
          .widget<Transform>(find.byKey(const ValueKey('spring-value')))
          .transform
          .entry(0, 3);
      final before = position();
      expect(before, inExclusiveRange(0, 100));
      await tester.pumpWidget(spring(20));
      expect(position(), closeTo(before, 0.001));
      await tester.pumpAndSettle();
      expect(position(), closeTo(20, 0.01));
    });

    testWidgets('anchored picker stays opaque and can reverse while opening', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          SectionedChipScrollView<int>(
            labels: const SectionedChipScrollLabels(panelTitle: 'Sections'),
            sections: testSections(List.filled(8, 3)),
            itemBuilder: testItem,
            style: const SectionedChipScrollStyle.outlined(
              pickerTransition: PickerTransition.clipReveal,
            ),
          ),
        ),
      );
      final triggerTop = tester
          .getTopLeft(find.byType(HeaderMaterial).first)
          .dy;
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final title = find.text('Sections').last;
      expect(
        find.ancestor(of: title, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(triggerTop));
      final route =
          ModalRoute.of(tester.element(title))! as TransitionRoute<void>;
      final before = route.animation!.value;
      expect(before, inExclusiveRange(0, 1));
      Navigator.of(tester.element(title)).pop();
      await tester.pump();
      expect(route.animation!.value, closeTo(before, 0.001));
      await tester.pumpAndSettle();
      expect(find.text('Sections'), findsNothing);
    });

    for (final reduce in [false, true]) {
      testWidgets('instant picker with none or reduced motion: $reduce', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Scaffold(
                body: SectionedChipScrollView<int>(
                  labels: const SectionedChipScrollLabels(
                    panelTitle: 'Sections',
                  ),
                  sections: testSections(List.filled(8, 3)),
                  itemBuilder: testItem,
                  style: SectionedChipScrollStyle.outlined(
                    pickerTransition: reduce
                        ? PickerTransition.clipReveal
                        : PickerTransition.none,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pump();
        final route =
            ModalRoute.of(tester.element(find.text('Sections').last))!
                as TransitionRoute<void>;
        expect(route.animation!.value, 1);
        expect(
          MediaQuery.disableAnimationsOf(
            tester.element(find.text('Sections').last),
          ),
          reduce,
        );
        await tester.tap(find.byIcon(Icons.expand_less));
        await tester.pumpAndSettle();
        expect(find.text('Sections'), findsNothing);
      });
    }

    testWidgets('high contrast uses solid chrome and a defined border', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Scaffold(body: _view(testSections([3]))),
          ),
        ),
      );
      final header = find.byType(HeaderMaterial).first;
      expect(
        find.descendant(of: header, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: header,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(decoration.border, isNotNull);
    });

    test(
      'default selected text contrast is at least 4.5 in light and dark',
      () {
        const style = SectionedChipScrollStyle.outlined();
        for (final brightness in Brightness.values) {
          final surface = ThemeData(
            colorSchemeSeed: const Color(0xFFB42318),
            brightness: brightness,
          ).colorScheme.surface;
          final fill = Color.alphaBlend(
            style.accentColor.withValues(alpha: style.selectedFillOpacity),
            surface,
          );
          final foreground = style.selectedForeground(fill);
          final a = foreground.computeLuminance();
          final b = fill.computeLuminance();
          final contrast = a > b
              ? (a + .05) / (b + .05)
              : (b + .05) / (a + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          debugPrint(
            'CONTRAST ${brightness.name}=${contrast.toStringAsFixed(2)}',
          );
        }
        expect(
          style
              .copyWith(pickerTransition: PickerTransition.clipReveal)
              .pickerTransition,
          PickerTransition.clipReveal,
        );
        final simulation = SpringSimulation(style.spring(), 0, 1, 0);
        for (var t = 0.0; t < 2; t += .016) {
          expect(simulation.x(t), inInclusiveRange(0, 1));
          expect(simulation.dx(t), greaterThanOrEqualTo(0));
        }
      },
    );
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
      await tester.pumpWidget(testApp(_view(testSections(List.filled(8, 2)))));
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

class _LiveTile extends StatefulWidget {
  const _LiveTile({super.key, required this.onLife});
  final ValueChanged<int> onLife;

  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> {
  @override
  void initState() {
    super.initState();
    widget.onLife(1);
  }

  @override
  void dispose() {
    widget.onLife(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 120);
}

/// First layout is short; the next frame grows — mimics Android content settle.
class _SettlingTile extends StatefulWidget {
  const _SettlingTile({required this.index});
  final int index;

  @override
  State<_SettlingTile> createState() => _SettlingTileState();
}

class _SettlingTileState extends State<_SettlingTile> {
  double _height = 72;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _height < 120) setState(() => _height = 120);
    });
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: _height, child: Text('item ${widget.index}'));
}
