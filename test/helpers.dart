import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

/// Sections `<prefix> 0..n-1` with ids `s0..`; section i has `counts[i]`
/// items.
List<ChipSection<int>> testSections(
  List<int> counts, [
  String prefix = 'Section',
]) => [
  for (var i = 0; i < counts.length; i++)
    ChipSection(
      id: 's$i',
      label: '$prefix $i',
      items: List.generate(counts[i], (j) => j),
    ),
];

/// A 120 px tall item.
Widget testItem(BuildContext context, int i) =>
    SizedBox(height: 120, child: Text('item $i'));

/// [body] in a Scaffold, in a MaterialApp.
Widget testApp(Widget body, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: body),
      ),
    );

/// Scroll position of the section list.
ScrollPosition listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;
