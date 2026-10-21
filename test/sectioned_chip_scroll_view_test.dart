import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll/src/common.dart'
    show HeaderMaterial, PressFeedback, SpringValue;

import 'helpers.dart';

Widget _view(
  List<ChipSection<int>> sections, {
  SectionedChipScrollConfig config = const SectionedChipScrollConfig(),
  ValueChanged<ChipSection<int>>? onSectionTap,
  ValueChanged<ChipSection<int>>? onSectionSelected,
  SectionColumnsBuilder? columnsBuilder,
  Widget Function(BuildContext, int) itemBuilder = testItem,
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
  ),
);

/// The title text of a section in the list (not the chip, not the picker).
Finder _title(String label) =>
    find.descendant(of: find.byType(SliverList), matching: find.text(label));

/// Title top minus list top (the chip bar bottom), minus the title's 12 px
/// top padding. Navigation aligns the text itself to the viewport top.
double _offsetError(WidgetTester tester, String label) =>
    tester.getTopLeft(_title(label)).dy -
    tester.getTopLeft(find.byType(CustomScrollView)).dy;

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
                if (!categories) {
                  expect(slot.size, const Size(48, 48));
                  final long = find.text(names[2]).first;
                  final text = tester.widget<Text>(long);
                  expect(text.maxLines, 1);
                  expect(text.softWrap, false);
                  expect(text.overflow, TextOverflow.ellipsis);
                  final chip = find
                      .ancestor(of: long, matching: find.byType(Material))
                      .first;
                  expect(tester.getSize(chip).width, closeTo(width - 48, .01));
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
                expect(tester.getRect(close).size, const Size(48, 48));
                expect(tester.getRect(close), slot);
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
        expect(tester.getTopLeft(close), Offset(size.width - 48, 100));
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
          expect(leading('A'), closeTo(0, .1));
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
            expect(panel, findsNothing);
            expect(selected, isEmpty);
            expect(
              tester.getSemantics(
                find.bySemanticsLabel('${names.first}, 1 of 35'),
              ),
              containsSemantics(isSelected: true),
            );
          }
          if (selected.isNotEmpty) break;
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
        final margin = (bar.width - 48 - rect.width).clamp(0.0, 48.0);
        expect(rect.left, closeTo(bar.left + margin, .1));
        expect(rect.right, lessThanOrEqualTo(bar.right - 48));
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
        expect(spyRect.right, lessThanOrEqualTo(bar.right - 48));
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
        testApp(_view(s, onSectionSelected: (x) => selected.add(x.id))),
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

    testWidgets('changing row geometry cancels motion and resumes scroll-spy', (
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
      expect(tester.takeException(), isNull);
      expect(_state(tester).navigationPhase, isNull);
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
            expect(
              selected,
              isEmpty,
              reason: 'callbacks muted during transaction',
            );
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
            expect(
              tester.takeAnnouncements().map((a) => a.message),
              isNot(contains('Section $target')),
            );
            expect(selected, isNot(contains('s$target')));
            if (cause != 'dispose' && !(cause == 'category' && !rail)) {
              expect(_state(tester).navigationPhase, isNull);
              final stopped = listPosition(tester).pixels;
              await tester.pump(const Duration(seconds: 1));
              expect(
                listPosition(tester).pixels,
                closeTo(stopped, 0.01),
                reason: 'cancel never re-drives',
              );
              if ([
                'rotation',
                'scale',
                'insets',
                'row',
                'data',
              ].contains(cause)) {
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
          expect(
            listPosition(tester).pixels,
            0,
            reason: 'no move during close',
          );
          expect(selected, isEmpty);
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
          expect(selected, dismiss == 'pick' ? ['s10'] : isEmpty);
          expect(
            tester.takeAnnouncements().map((a) => a.message),
            dismiss == 'pick' ? ['Section 10'] : isEmpty,
          );
          if (dismiss != 'pick') expect(listPosition(tester).pixels, 0);
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
