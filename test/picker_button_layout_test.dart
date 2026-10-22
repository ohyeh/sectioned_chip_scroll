import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll/src/presentation/chrome.dart'
    show HeaderMaterial;

import 'helpers.dart';

Finder _button(IconData icon) => find
    .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
    .first;

void main() {
  Future<void> mount(
    WidgetTester tester,
    double scale, {
    String title = 'Sections',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 932);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SectionedChipScrollView<int>(
              sections: testSections(List.filled(35, 8)),
              itemBuilder: testItem,
              labels: SectionedChipScrollLabels(panelTitle: title),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 3.12]) {
    for (final title in [
      'Go',
      'Choose from every available section in this very long panel title',
    ]) {
      testWidgets('T-f C3 vertical slot scale=$scale title=$title', (
        tester,
      ) async {
        await mount(tester, scale, title: title);
        final open = tester.getCenter(_button(Icons.expand_more));
        await tester.tap(_button(Icons.expand_more));
        await tester.pumpAndSettle();
        final close = tester.getCenter(_button(Icons.expand_less));
        expect(close.dy, closeTo(open.dy, .5));
        expect(close.dx, closeTo(open.dx, .5));
        final text = find.text(title);
        expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          title != 'Go',
        );
        final header = tester.getRect(
          find.byKey(const ValueKey('sectioned_chip_scroll.panelHeader')),
        );
        expect(tester.getRect(text).top, greaterThanOrEqualTo(header.top));
        expect(tester.getRect(text).bottom, lessThanOrEqualTo(header.bottom));
      });
    }

    testWidgets('L5-1 picker buttons center on their own rows scale=$scale', (
      tester,
    ) async {
      await mount(tester, scale);
      final open = tester.getRect(_button(Icons.expand_more));
      expect(open.width, greaterThanOrEqualTo(48));
      expect(open.height, greaterThanOrEqualTo(48));
      final bar = tester.getRect(find.byType(HeaderMaterial).first);
      expect(open.center.dy, closeTo(bar.center.dy, .5));
      expect(
        tester.getCenter(find.byIcon(Icons.expand_more)).dx,
        closeTo(open.center.dx, .5),
      );
      await tester.tap(_button(Icons.expand_more));
      await tester.pumpAndSettle();
      final close = tester.getRect(_button(Icons.expand_less));
      final header = tester.getRect(
        find.byKey(const ValueKey('sectioned_chip_scroll.panelHeader')),
      );
      expect(close.center.dy, closeTo(header.center.dy, .5));
      expect(
        tester.getCenter(find.byIcon(Icons.expand_less)).dx,
        closeTo(close.center.dx, .5),
      );
      expect(close.size, open.size);
      expect(close.right, closeTo(open.right, .5));
    });
  }

  for (final scale in [1.0, 1.5, 2.0, 3.12]) {
    testWidgets('L5-2 board chevron and shared plain hit area scale=$scale', (
      tester,
    ) async {
      await mount(tester, scale);
      final factor = scale.clamp(0.0, 2.0);
      final glyphSize = Size(16 * factor, 8 * factor);
      expect(tester.getSize(find.byIcon(Icons.expand_more)), glyphSize);
      final chip = find
          .ancestor(
            of: find.text('Section 0').first,
            matching: find.byType(Material),
          )
          .first;
      final chipHeight = tester.getSize(chip).height;
      final slot = tester.getRect(_button(Icons.expand_more));
      debugPrint('L5-2 scale=$scale glyph=$glyphSize slot=${slot.size}');
      expect(slot.width, (glyphSize.width + 24).clamp(48.0, double.infinity));
      expect(slot.height, closeTo(chipHeight, .5));
      expect(slot.height, greaterThanOrEqualTo(48));
      if (scale == 1) expect(slot.size, const Size(48, 48));
      for (final icon in [Icons.expand_more, Icons.expand_less]) {
        if (icon == Icons.expand_less) {
          await tester.tap(_button(Icons.expand_more));
          await tester.pumpAndSettle();
        }
        expect(tester.getSize(find.byIcon(icon)), glyphSize);
        expect(tester.getRect(_button(icon)).size, slot.size);
        expect(tester.getRect(_button(icon)).right, closeTo(slot.right, .5));
        expect(
          tester.getCenter(find.byIcon(icon)),
          tester.getCenter(_button(icon)),
        );
        final button = tester.widget<IconButton>(_button(icon));
        expect(button.style!.backgroundColor!.resolve({}), Colors.transparent);
        expect(button.style!.side!.resolve({}), BorderSide.none);
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byIcon(icon),
            matching: find.byType(CustomPaint),
          ),
        );
        await tester.runAsync(() async {
          // Supersampling distinguishes stroke scaling from just a larger box.
          const samples = 8;
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder)..scale(samples.toDouble());
          paint.painter!.paint(canvas, glyphSize);
          final picture = recorder.endRecording();
          final width = (glyphSize.width * samples).round();
          final image = await picture.toImage(
            width,
            (glyphSize.height * samples).round(),
          );
          final bytes = (await image.toByteData())!;
          final column = (4.5 * factor * samples).round();
          var coverage = 0.0;
          for (var y = 0; y < image.height; y++) {
            coverage += bytes.getUint8((y * width + column) * 4 + 3) / 255;
          }
          expect(
            coverage / samples,
            closeTo(1.6 * factor * math.sqrt(85) / 7, .15),
          );
          final apexY = icon == Icons.expand_more ? 7.0 : 1.0;
          final apex =
              ((apexY * factor * samples).round() * width +
                  (8 * factor * samples).round()) *
              4;
          expect(bytes.getUint8(apex + 3), 255);
          expect(
            [
              for (var channel = 0; channel < 3; channel++)
                bytes.getUint8(apex + channel),
            ],
            [44, 42, 45],
          );
          image.dispose();
          picture.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
}
