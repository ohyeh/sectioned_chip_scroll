import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

import 'helpers.dart';

SectionCategory<int> _cat(String name, List<ChipSection<int>> sections) =>
    SectionCategory(id: name, label: 'Cat $name', sections: sections);

final _abc = [
  _cat('A', testSections([2, 2, 2], 'A')),
  _cat('B', testSections([2, 2, 2], 'B')),
  _cat('C', testSections([2, 2, 2], 'C')),
];

CategorizedChipScrollView<int> _view(
  List<SectionCategory<int>> categories, {
  CategorizedChipScrollConfig config = const CategorizedChipScrollConfig(),
  ValueChanged<SectionCategory<int>>? onCategorySelected,
}) => CategorizedChipScrollView<int>(
  categories: categories,
  itemBuilder: testItem,
  config: config,
  onCategorySelected: onCategorySelected,
);

SemanticsNode _node(WidgetTester tester, String label) =>
    tester.getSemantics(find.bySemanticsLabel(label));

bool _hasAncestorRole(SemanticsNode node, SemanticsRole role) {
  for (var n = node.parent; n != null; n = n.parent) {
    if (n.getSemanticsData().role == role) return true;
  }
  return false;
}

/// Whether the focused widget shows [text].
bool _focused(String text) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null &&
      find
          .descendant(
            of: find.byElementPredicate((e) => e == ctx),
            matching: find.text(text),
          )
          .evaluate()
          .isNotEmpty;
}

void main() {
  group('rail', () {
    testWidgets('one category shows no tabs unless showRailWhenSingle', (
      tester,
    ) async {
      final one = [_abc.first];
      await tester.pumpWidget(testApp(_view(one)));
      expect(find.text('Cat A'), findsNothing);
      expect(find.byType(SectionedChipScrollView<int>), findsOneWidget);

      await tester.pumpWidget(
        testApp(
          _view(
            one,
            config: const CategorizedChipScrollConfig(showRailWhenSingle: true),
          ),
        ),
      );
      expect(find.text('Cat A'), findsOneWidget);
    });

    testWidgets('tabs: tab role in a tab bar, selected, position, tap', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        testApp(_view(_abc, onCategorySelected: (c) => picked.add(c.id))),
      );
      final a = _node(tester, 'Cat A, 1 of 3');
      expect(a.getSemanticsData().role, SemanticsRole.tab);
      expect(_hasAncestorRole(a, SemanticsRole.tabBar), isTrue);
      expect(a, containsSemantics(isSelected: true, hasTapAction: true));
      expect(
        _node(tester, 'Cat B, 2 of 3'),
        containsSemantics(isSelected: false, hasTapAction: true),
      );

      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      expect(picked, ['B']);
      expect(find.text('B 0'), findsWidgets);
      expect(find.text('A 0'), findsNothing);
    });

    testWidgets('the rail is at the start edge (RTL: right)', (tester) async {
      await tester.pumpWidget(
        testApp(_view(_abc), direction: TextDirection.rtl),
      );
      expect(
        tester.getCenter(find.text('Cat A')).dx,
        greaterThan(tester.getCenter(find.byType(CustomScrollView)).dx),
      );
    });

    testWidgets('removing the selected category selects the first', (
      tester,
    ) async {
      final picked = <String>[];
      Widget build(List<SectionCategory<int>> c) =>
          testApp(_view(c, onCategorySelected: (x) => picked.add(x.id)));
      await tester.pumpWidget(build(_abc));
      await tester.tap(find.text('Cat C'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(_abc.sublist(1, 2)..insert(0, _abc[0])));
      await tester.pumpAndSettle();
      expect(picked, ['C', 'A']);
      await tester.pumpWidget(build(const []));
      expect(find.byType(SectionedChipScrollView<int>), findsNothing);
    });
  });

  group('kept state', () {
    // Section 6 is short and not last: at the bottom only an explicit pick
    // keeps it selected.
    final shortTail = [
      _cat('A', testSections([...List.filled(6, 12), 1, 1])),
      _cat('B', testSections([2, 2], 'B')),
    ];

    Future<void> pickSection6ThenSwitchBack(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section 6').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat A'));
      await tester.pumpAndSettle();
    }

    testWidgets('keepCategoryState: A to B to A keeps the short-tail pick', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_view(shortTail)));
      await pickSection6ThenSwitchBack(tester);
      final position = listPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
      expect(
        _node(tester, 'Section 6, 7 of 8'),
        containsSemantics(isSelected: true),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(
        _node(tester, 'Section 6, 7 of 8'),
        containsSemantics(isSelected: true),
      );
    });

    testWidgets('without keepCategoryState a category starts over', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          _view(
            shortTail,
            config: const CategorizedChipScrollConfig(keepCategoryState: false),
          ),
        ),
      );
      await pickSection6ThenSwitchBack(tester);
      expect(listPosition(tester).pixels, 0);
      expect(
        _node(tester, 'Section 0, 1 of 8'),
        containsSemantics(isSelected: true),
      );
    });

    testWidgets('the same section id in two categories is not shared', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_view(_abc)));
      await tester.tap(find.text('A 2').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      expect(_node(tester, 'B 0, 1 of 3'), containsSemantics(isSelected: true));
    });

    testWidgets('a layout change keeps the sections view state', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(_view(_abc)));
      await tester.tap(find.text('A 2').first);
      await tester.pumpAndSettle();
      // Too narrow for the rail: the picker layout takes over.
      tester.view.physicalSize = const Size(200, 600);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
      expect(_node(tester, 'A 2, 3 of 3'), containsSemantics(isSelected: true));
    });
  });

  group('keyboard', () {
    testWidgets('one Tab stop; arrows move without switching; Enter switches', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        testApp(_view(_abc, onCategorySelected: (c) => picked.add(c.id))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focused('Cat A'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focused('Cat B'), isTrue);
      expect(picked, isEmpty);

      // Tab leaves the tab list at once, without visiting Cat C.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focused('A 0'), isTrue);

      // Coming back lands on the selected tab.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(_focused('Cat A'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, ['B']);
      expect(_focused('Cat B'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(picked, ['B', 'C']);
    });
  });

  testWidgets('a lower selected tab still comes before the content', (
    tester,
  ) async {
    final many = [
      for (final n in ['A', 'B', 'C', 'D', 'E', 'F'])
        _cat(n, testSections([2, 2, 2], n)),
    ];
    await tester.pumpWidget(testApp(_view(many)));
    await tester.tap(find.text('Cat E'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focused('Cat E'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focused('E 0'), isTrue);
  });

  group('large text', () {
    Future<void> pumpNarrowLarge(
      WidgetTester tester,
      CategorizedChipScrollConfig config,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.12)),
              child: Scaffold(body: _view(_abc, config: config)),
            ),
          ),
        ),
      );
    }

    testWidgets('the picker layout replaces the rail and switches', (
      tester,
    ) async {
      await pumpNarrowLarge(tester, const CategorizedChipScrollConfig());
      expect(
        _node(tester, 'Cat A, 1 of 3'),
        containsSemantics(isButton: true, hint: 'Change category'),
      );
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      await tester.tap(find.text('Cat C').last);
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsNothing);
      expect(find.text('C 0'), findsWidgets);
    });

    testWidgets('topTabs puts the tabs in a row above the content', (
      tester,
    ) async {
      await pumpNarrowLarge(
        tester,
        const CategorizedChipScrollConfig(
          railLargeTextLayout: CategoryFallbackLayout.topTabs,
        ),
      );
      expect(
        tester.getBottomLeft(find.text('Cat A')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(CustomScrollView)).dy),
      );
      expect(find.byIcon(Icons.unfold_more), findsNothing);
    });
  });

  group('announce', () {
    Widget announcing(FocusAfterNavigate mode, {required bool supported}) =>
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(supportsAnnounce: supported),
              child: Scaffold(
                body: _view(
                  _abc,
                  config: CategorizedChipScrollConfig(
                    sectionConfig: SectionedChipScrollConfig(
                      focusAfterNavigate: mode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('announce: once per category switch and per chip jump', (
      tester,
    ) async {
      await tester.pumpWidget(
        announcing(FocusAfterNavigate.announce, supported: true),
      );
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B 2').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(
        [for (final a in tester.takeAnnouncements()) a.message],
        ['Cat B', 'B 2'],
      );
    });

    testWidgets('no announcement when unsupported or preserve', (tester) async {
      await tester.pumpWidget(
        announcing(FocusAfterNavigate.announce, supported: false),
      );
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        announcing(FocusAfterNavigate.preserve, supported: true),
      );
      await tester.tap(find.text('Cat C'));
      await tester.pumpAndSettle();
      expect(tester.takeAnnouncements(), isEmpty);
    });
  });

  group('review fixes', () {
    Widget narrow(Widget child) => MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 568),
        textScaler: TextScaler.linear(3.12),
      ),
      child: child,
    );

    testWidgets('a data update closes the open category picker', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      Widget build(List<SectionCategory<int>> c) =>
          MaterialApp(home: narrow(Scaffold(body: _view(c))));
      await tester.pumpWidget(build(_abc));
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      await tester.pumpWidget(build(_abc.sublist(0, 2)));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chip bar does not overwrite the stored list offset', (
      tester,
    ) async {
      final cats = [
        _cat('A', testSections(List.filled(10, 12))),
        _cat('B', testSections([2, 2], 'B')),
      ];
      await tester.pumpWidget(testApp(_view(cats)));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1100));
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Section 0').first,
        const Offset(-150, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final before = listPosition(tester).pixels;
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat A'));
      await tester.pumpAndSettle();
      expect(listPosition(tester).pixels, before);
    });

    testWidgets('rail width follows a nonlinear text scaler at body size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const _FlatAtLargeSizes()),
              child: Scaffold(body: _view(_abc)),
            ),
          ),
        ),
      );
      // 96 * (28 / 14) = 192 > 40% of 320: the picker replaces the rail.
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    });

    testWidgets('a restored offset reselects what is on screen', (
      tester,
    ) async {
      final a = testSections([...List.filled(6, 12), 1, 1]);
      Widget build(List<ChipSection<int>> aSections) => testApp(
        _view([
          _cat('A', aSections),
          _cat('B', testSections([2], 'B')),
        ]),
      );
      await tester.pumpWidget(build(a));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section 6').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      // Section 6 is gone when A comes back at the restored bottom offset.
      await tester.pumpWidget(build([...a.take(6), a[7]]));
      await tester.tap(find.text('Cat A'));
      await tester.pumpAndSettle();
      expect(
        _node(tester, 'Section 7, 7 of 7'),
        containsSemantics(isSelected: true),
      );
    });

    testWidgets('a category switch reports the new selected section', (
      tester,
    ) async {
      final sections = <String>[];
      await tester.pumpWidget(
        testApp(
          CategorizedChipScrollView<int>(
            categories: _abc,
            itemBuilder: testItem,
            onSectionSelected: (s) => sections.add(s.label),
          ),
        ),
      );
      await tester.tap(find.text('Cat B'));
      await tester.pumpAndSettle();
      expect(sections.last, 'B 0');
    });

    testWidgets('the Tab stop follows the tab id across a reorder', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_view(_abc)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focused('Cat B'), isTrue);
      await tester.pumpWidget(testApp(_view([_abc[2], _abc[0], _abc[1]])));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // B is last now; the next tab wraps to C.
      expect(_focused('Cat C'), isTrue);
    });

    testWidgets('first data after an empty list is not a selection change', (
      tester,
    ) async {
      final picked = <String>[];
      Widget build(List<SectionCategory<int>> c) =>
          testApp(_view(c, onCategorySelected: (x) => picked.add(x.id)));
      await tester.pumpWidget(build(const []));
      await tester.pumpWidget(build(_abc));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });
  });
}

/// Doubles small text but barely grows large sizes, like Android 14+
/// nonlinear font scaling.
class _FlatAtLargeSizes extends TextScaler {
  const _FlatAtLargeSizes();

  @override
  double scale(double fontSize) => fontSize < 30 ? fontSize * 2 : fontSize;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 2;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => this;
}
