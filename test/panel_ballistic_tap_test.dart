import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_view.dart'
    show ChipControl;

// Exercise the shipped scene without a circular example dev dependency.
// ignore: avoid_relative_lib_imports
import '../example/lib/main.dart' show DemoApp;

import 'helpers.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final ios = platform == TargetPlatform.iOS;
    for (final pressMs in [50, if (ios) 500, if (ios) 650]) {
      for (final bounce in [false, true]) {
        if (!ios && bounce) continue;
        for (final delay in [
          0,
          100,
          300,
          600,
          if (ios && !bounce) 4000,
          if (!bounce) -1,
          if (!bounce) -2,
        ]) {
          final drag = delay == -1;
          final fast = delay == -2;
          if (pressMs != 50 && (drag || fast)) continue;
          final name = drag
              ? 'slow ballistic drag scrolls without picking'
              : fast
              ? 'fast ballistic tap only stops scrolling'
              : '${delay == 4000
                        ? 'idle'
                        : bounce
                        ? 'edge bounce'
                        : 'ballistic tail'} '
                    'tap after ${delay}ms picks once';
          testWidgets('${ios ? 'T1 iOS' : 'T-e Android'} AX5 $name'
              '${pressMs == 50 ? '' : ' press=${pressMs}ms'}', (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            try {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(375, 812);
              addTearDown(tester.view.reset);
              final selected = <String>[];
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData(platform: platform),
                  home: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(3.12),
                    ),
                    child: Scaffold(
                      body: SectionedChipScrollView<int>(
                        sections: testSections(List.filled(35, 8), 'Category'),
                        itemBuilder: testItem,
                        onSectionSelected: (section) =>
                            selected.add(section.id),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byIcon(Icons.expand_more));
              await tester.pumpAndSettle();
              final body = find.byKey(
                const ValueKey('sectioned_chip_scroll.panelScroll'),
              );
              final position = tester
                  .widget<SingleChildScrollView>(body)
                  .controller!
                  .position;
              expect(
                position.physics,
                ios
                    ? isA<BouncingScrollPhysics>()
                    : isA<ClampingScrollPhysics>(),
              );
              if (!bounce) {
                await tester.ensureVisible(find.text('Category 16').last);
                await tester.pumpAndSettle();
              }
              await tester.fling(
                body,
                Offset(0, bounce ? 180 : -180),
                fast ? 3000 : 1200,
              );
              var foundTail = false;
              for (var frame = 0; frame < 300; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                final activity = position.activity;
                if (activity is BallisticScrollActivity &&
                    activity.velocity.abs() > 0 &&
                    (fast
                        ? activity.velocity.abs() / 60 > kTouchSlop
                        : activity.velocity.abs() / 60 < kTouchSlop) &&
                    position.outOfRange == bounce) {
                  foundTail = true;
                  break;
                }
              }
              expect(
                foundTail,
                isTrue,
                reason: 'must reach the requested moving state',
              );
              await tester.pump(Duration(milliseconds: delay < 0 ? 0 : delay));
              if (delay == 4000) {
                await tester.pumpAndSettle();
                expect(position.activity, isA<IdleScrollActivity>());
                final stopped = position.pixels;
                for (var frame = 0; frame < 5; frame++) {
                  await tester.pump(const Duration(milliseconds: 125));
                  expect(position.pixels, stopped);
                }
              }
              final bounds = tester.getRect(body);
              String? target;
              Offset? point;
              for (var i = 1; i < 35; i++) {
                final text = find.text('Category $i').last;
                final center = tester.getCenter(text);
                if (center.dy > bounds.top + 30 &&
                    center.dy < bounds.bottom - 30 &&
                    bounds.contains(center)) {
                  target = 's$i';
                  point = center;
                  break;
                }
              }
              expect(target, isNotNull);
              if (!bounce && delay != 4000 && (ios || delay <= 0)) {
                expect(position.activity, isA<BallisticScrollActivity>());
              }
              final before = position.pixels;
              final gesture = await tester.startGesture(point!);
              if (drag) {
                await gesture.moveBy(const Offset(0, -100));
                await tester.pump(const Duration(milliseconds: 16));
                await gesture.moveBy(const Offset(0, -100));
              }
              await tester.pump(Duration(milliseconds: pressMs));
              await gesture.up();
              if (drag || fast) {
                await tester.pumpAndSettle();
                expect(selected, isEmpty);
                expect(
                  find.byKey(const ValueKey('sectioned_chip_scroll.panel')),
                  findsOneWidget,
                );
                if (drag) expect(position.pixels, greaterThan(before + 50));
                if (fast) expect(position.pixels, closeTo(before, 1));
                return;
              }
              expect(selected, [
                target,
              ], reason: 'pick must occur on pointer up');
              await tester.pumpAndSettle();
              expect(selected, [
                target,
              ], reason: 'pick must occur exactly once');
              expect(
                find.byKey(const ValueKey('sectioned_chip_scroll.panel')),
                findsNothing,
              );
            } finally {
              debugDefaultTargetPlatformOverride = null;
            }
          });
        }
      }
    }
  }

  for (final state in ['idle', 'subpixel tail', 'take1', 'take2']) {
    for (final pressMs in [500, 650]) {
      for (final spot in [
        'evidence',
        'bottom edge',
        'right clear of scrollbar',
        'scrollbar track',
      ]) {
        testWidgets('T1b iPhone geometry $state $spot press=${pressMs}ms', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          try {
            tester.view.devicePixelRatio = 2;
            tester.view.physicalSize = const Size(828, 1792);
            tester.view.padding = const FakeViewPadding(top: 88, bottom: 68);
            addTearDown(tester.view.reset);
            await tester.pumpWidget(const DemoApp());
            await tester.tap(find.text('many'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('scale 1.0'));
            await tester.pumpAndSettle();
            await tester.tap(find.byIcon(Icons.expand_more));
            await tester.pumpAndSettle();
            final body = find.byKey(
              const ValueKey('sectioned_chip_scroll.panelScroll'),
            );
            final position = tester
                .widget<SingleChildScrollView>(body)
                .controller!
                .position;
            expect(position.physics, isA<BouncingScrollPhysics>());
            await tester.timedDragFrom(
              const Offset(207, 700),
              const Offset(0, -480),
              Duration(milliseconds: state == 'take1' ? 445 : 451),
            );
            if (state == 'idle') {
              await tester.pumpAndSettle();
              expect(position.activity, isA<IdleScrollActivity>());
              final stopped = position.pixels;
              for (var frame = 0; frame < 5; frame++) {
                await tester.pump(const Duration(milliseconds: 125));
                expect(position.pixels, stopped);
              }
            } else if (state == 'subpixel tail') {
              var found = false;
              for (var frame = 0; frame < 300; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                final activity = position.activity;
                if (activity is BallisticScrollActivity &&
                    activity.velocity.abs() < 25 &&
                    activity.velocity.abs() > 0) {
                  found = true;
                  break;
                }
              }
              expect(found, isTrue);
              for (var frame = 0; frame < 5; frame++) {
                final before = position.pixels;
                await tester.pump(const Duration(milliseconds: 16));
                expect((position.pixels - before).abs() * 2, lessThan(1));
              }
              expect(position.activity, isA<BallisticScrollActivity>());
            } else {
              // Telemetry tap time minus swipe start and swipe duration.
              await tester.pump(
                Duration(milliseconds: state == 'take1' ? 1659 : 1806),
              );
            }
            final bounds = tester.getRect(body);
            final chips =
                find
                    .descendant(of: body, matching: find.byType(ChipControl))
                    .evaluate()
                    .where((element) {
                      final rect = tester.getRect(
                        find.byWidget(element.widget),
                      );
                      return rect.top > bounds.top &&
                          rect.bottom < bounds.bottom &&
                          !(element.widget as ChipControl).selected;
                    })
                    .toList()
                  ..sort(
                    (a, b) =>
                        (tester.getCenter(find.byWidget(a.widget)).dy - 595)
                            .abs()
                            .compareTo(
                              (tester.getCenter(find.byWidget(b.widget)).dy -
                                      595)
                                  .abs(),
                            ),
                  );
            expect(chips, isNotEmpty);
            final chip = chips.first.widget as ChipControl;
            final rect = tester.getRect(find.byWidget(chip));
            final point = switch (spot) {
              'bottom edge' => Offset(rect.center.dx, rect.bottom - .5),
              'right clear of scrollbar' => Offset(
                rect.right - 48,
                rect.center.dy,
              ),
              'scrollbar track' => Offset(rect.right - .5, rect.center.dy),
              _ => Offset(rect.center.dx, rect.top + rect.height * .82),
            };
            expect(rect.contains(point), isTrue);
            final track = spot == 'scrollbar track';
            final chipHit = tester
                .hitTestOnBinding(point)
                .path
                .any(
                  (entry) =>
                      entry.target == tester.renderObject(find.byWidget(chip)),
                );
            expect(
              chipHit,
              !track,
              reason: 'a scrollbar track is not a chip hit',
            );
            var scrollbarHit = false;
            for (final paint in find.byType(CustomPaint).evaluate()) {
              final painter = (paint.widget as CustomPaint).foregroundPainter;
              if (painter is ScrollbarPainter) {
                final local =
                    point - tester.getTopLeft(find.byWidget(paint.widget));
                scrollbarHit |= painter.hitTest(local) ?? false;
              }
            }
            expect(scrollbarHit, track);
            final gesture = await tester.startGesture(point);
            await tester.pump(Duration(milliseconds: pressMs));
            await gesture.up();
            if (track) {
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('sectioned_chip_scroll.panel')),
                findsOneWidget,
              );
              expect(
                tester
                    .widgetList<ChipControl>(find.byType(ChipControl))
                    .where((control) => control.selected)
                    .every((control) => control.label == 'Category 01'),
                isTrue,
              );
              return;
            }
            // The example's bottom label changes synchronously on selection.
            await tester.pump();
            final selected = tester
                .widgetList<ChipControl>(find.byType(ChipControl))
                .where((control) => control.selected)
                .map((control) => control.label);
            expect(selected, contains(chip.label));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('sectioned_chip_scroll.panel')),
              findsNothing,
            );
            final footer = tester
                .widget<Scaffold>(find.byType(Scaffold).last)
                .bottomNavigationBar!;
            expect(
              find.descendant(
                of: find.byWidget(footer),
                matching: find.text(chip.label),
              ),
              findsOneWidget,
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}
