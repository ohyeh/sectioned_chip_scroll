import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll_example/main.dart';

void main() {
  testWidgets(
    'motion scenes have stable buttons, unique labels and AX5 layouts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const DemoApp());
      final counts = {'few': 3, 'flow': 7, 'many': 35, 'long': 8};
      for (final entry in counts.entries) {
        final button = find.widgetWithText(OutlinedButton, entry.key);
        expect(
          tester.getSemantics(button),
          containsSemantics(isButton: true, hasTapAction: true),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        final view = tester.widget<SectionedChipScrollView<String>>(
          find.byType(SectionedChipScrollView<String>),
        );
        expect(view.sections.length, entry.value);
        expect(view.sections.map((s) => s.label).toSet().length, entry.value);
        expect(
          find.byIcon(Icons.expand_more),
          entry.key == 'few' ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'scale 1.0'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'scale 3.12'), findsOneWidget);
        final context = tester.element(
          find.byType(SectionedChipScrollView<String>),
        );
        expect(MediaQuery.textScalerOf(context).scale(10), closeTo(31.2, .01));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.expand_less), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.expand_less));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );
}
