import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';
import 'package:sectioned_chip_scroll/src/common.dart' show HeaderMaterial;

import 'helpers.dart';

List<ChipSection<int>> _sections({int lastRows = 18}) => [
  for (var s = 0; s < 35; s++)
    ChipSection(
      id: 's$s',
      label: 'Category $s',
      items: List.generate(s == 34 ? lastRows : 18, (r) => s * 100 + r),
    ),
];

Widget _scene(List<ChipSection<int>> sections, PageStorageBucket bucket) =>
    testApp(
      PageStorage(
        bucket: bucket,
        child: SectionedChipScrollView<int>(
          key: const PageStorageKey('round5'),
          sections: sections,
          itemBuilder: (_, i) => SizedBox(
            key: ValueKey('row-$i'),
            height: 60 + (i % 7) * 17.0,
            child: Text('row $i'),
          ),
        ),
      ),
    );

SectionedChipScrollViewState<int> _state(WidgetTester tester) =>
    tester.state(find.byType(SectionedChipScrollView<int>));

Finder _title(int section) => find.descendant(
  of: find.byType(SliverList),
  matching: find.text('Category $section'),
);

double _titleError(WidgetTester tester, int section) =>
    tester.getTopLeft(_title(section)).dy -
    tester.getTopLeft(find.byType(CustomScrollView)).dy -
    12;

String _selected(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .firstWhere(
      (w) =>
          w.properties.selected == true &&
          (w.properties.label?.startsWith('Category ') ?? false),
    )
    .properties
    .label!
    .split(',')
    .first;

Future<void> _startPick(WidgetTester tester, int section) async {
  await tester.tap(find.byIcon(Icons.expand_more));
  await tester.pumpAndSettle();
  final chip = find.text('Category $section').last;
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _pick(WidgetTester tester, int section) async {
  await _startPick(tester, section);
  await tester.pumpAndSettle();
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    List<ChipSection<int>> sections,
    PageStorageBucket bucket,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(sections, bucket));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'R4-1 removing a far anchor shows the reselected section at top',
    (tester) async {
      final bucket = PageStorageBucket();
      final data = _sections();
      await mount(tester, data, bucket);
      await _pick(tester, 30);
      await tester.pumpWidget(
        _scene(data.where((s) => s.id != 's30').toList(), bucket),
      );
      await tester.pumpAndSettle();
      expect(_selected(tester), 'Category 0');
      expect(
        listPosition(tester).pixels,
        closeTo(0, .5),
        reason: 'old anchored pixels cannot become a plain offset',
      );
      expect(_titleError(tester, 0), closeTo(0, 1));
      expect(
        _state(tester).geometry!.sectionAtOffset(listPosition(tester).pixels),
        's0',
      );
    },
  );

  testWidgets(
    'R5-2 removing origin refreshes spy and reveals visible chip next frame',
    (tester) async {
      final bucket = PageStorageBucket();
      final data = _sections();
      await mount(tester, data, bucket);
      await _pick(tester, 30);
      for (var i = 0; i < 20 && _selected(tester) != 'Category 32'; i++) {
        listPosition(tester).jumpTo(listPosition(tester).pixels + 400);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(_selected(tester), 'Category 32');
      await tester.pumpWidget(
        _scene(data.where((s) => s.id != 's30').toList(), bucket),
      );
      await tester.pump();
      expect(_titleError(tester, 0), closeTo(0, 1));
      expect(_selected(tester), 'Category 0');
      final chip = find.text('Category 0').first;
      final viewport = tester.getRect(find.byType(HeaderMaterial).first);
      expect(tester.getRect(chip).left, greaterThanOrEqualTo(viewport.left));
      expect(tester.getRect(chip).right, lessThanOrEqualTo(viewport.right));
    },
  );

  testWidgets(
    'R4-2 reset clears the stored anchor before plain offset restore',
    (tester) async {
      final bucket = PageStorageBucket();
      var data = _sections();
      await mount(tester, data, bucket);
      await _pick(tester, 30);
      data = data.where((s) => s.id != 's30').toList();
      await tester.pumpWidget(_scene(data, bucket));
      await tester.pumpAndSettle();
      listPosition(tester).jumpTo(450);
      await tester.pumpAndSettle();
      final saved = listPosition(tester).pixels;
      final row = _topRow(tester);
      final y = tester.getTopLeft(find.byKey(row)).dy;
      await tester.pumpWidget(testApp(const SizedBox()));
      await tester.pumpWidget(_scene(data, bucket));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomScrollView>(find.byType(CustomScrollView)).center,
        isNull,
        reason: 'plain pixels must not restore the stale anchor',
      );
      expect(listPosition(tester).pixels, closeTo(saved, .5));
      expect(tester.getTopLeft(find.byKey(row)).dy, closeTo(y, 1));
    },
  );

  testWidgets('R4-2 far anchor and offset restore together', (tester) async {
    final bucket = PageStorageBucket();
    final data = _sections();
    await mount(tester, data, bucket);
    await _pick(tester, 30);
    final saved = listPosition(tester).pixels;
    final y = _titleError(tester, 30);
    await tester.pumpWidget(testApp(const SizedBox()));
    await tester.pumpWidget(_scene(data, bucket));
    await tester.pumpAndSettle();
    expect(listPosition(tester).pixels, closeTo(saved, .5));
    expect(_titleError(tester, 30), closeTo(y, 1));
    expect(_selected(tester), 'Category 30');
  });

  testWidgets(
    'R4-3 unmeasured upward far pick decreases offset and lands exact',
    (tester) async {
      await mount(tester, _sections(), PageStorageBucket());
      await _pick(tester, 30);
      expect(_state(tester).geometry!.sections[5].top, isNull);
      final before = listPosition(tester).pixels;
      await _startPick(tester, 5);
      final offsets = <double>[listPosition(tester).pixels];
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(listPosition(tester).pixels);
      }
      expect(
        offsets.first,
        lessThan(before),
        reason: 'pre-jump must move upward',
      );
      expect(
        offsets.last,
        lessThan(offsets.first),
        reason: 'final animation must move upward',
      );
      expect(offsets.toSet().length, greaterThan(2));
      await tester.pumpAndSettle();
      expect(_titleError(tester, 5), closeTo(0, 1));
      expect(_selected(tester), 'Category 5');
    },
  );

  testWidgets('T-a drag during anchored motion cancels and spy resumes', (
    tester,
  ) async {
    await mount(tester, _sections(), PageStorageBucket());
    await _startPick(tester, 30);
    await tester.pump(const Duration(milliseconds: 64));
    expect(_state(tester).navigationPhase, 'moving');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).navigationPhase, isNull);
    final stopped = listPosition(tester).pixels;
    await tester.pump(const Duration(seconds: 1));
    expect(listPosition(tester).pixels, closeTo(stopped, .01));
    final id = _state(tester).geometry!.sectionAtOffset(stopped)!;
    expect(_selected(tester), 'Category ${id.substring(1)}');
    expect(_selected(tester), isNot('Category 30'));
  });

  testWidgets(
    'T-b backward scroll measures rows without moving visible content',
    (tester) async {
      await mount(tester, _sections(), PageStorageBucket());
      await _pick(tester, 30);
      final before = _state(
        tester,
      ).geometry!.sections[29].rowExtents.whereType<double>().length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
      );
      // Establish the drag before sampling so touch slop is not a layout delta.
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump(const Duration(milliseconds: 16));
      // Cross the anchor and multiple row/section boundaries at a slow drag speed.
      for (var frame = 0; frame < 48; frame++) {
        final row = _topRow(tester);
        final y = tester.getTopLeft(find.byKey(row)).dy;
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
        final movedY = tester.getTopLeft(find.byKey(row)).dy;
        expect(movedY - y, closeTo(40, 1), reason: 'drag frame $frame');
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(find.byKey(row)).dy,
          closeTo(movedY, 1),
          reason: 'measurement frame $frame',
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final geometry = _state(tester).geometry!;
      expect(
        geometry.sections[29].rowExtents.whereType<double>().length,
        greaterThan(before),
      );
      final id = geometry.sectionAtOffset(listPosition(tester).pixels)!;
      expect(_selected(tester), 'Category ${id.substring(1)}');
      expect(_selected(tester), isNot('Category 30'));
    },
  );

  for (final lastRows in [1, 18]) {
    testWidgets(
      'T-c anchored last section clamps without a gap rows=$lastRows',
      (tester) async {
        await mount(tester, _sections(lastRows: lastRows), PageStorageBucket());
        await _pick(tester, 34);
        final position = listPosition(tester);
        expect(
          position.pixels,
          lessThanOrEqualTo(position.maxScrollExtent + .1),
        );
        expect(_selected(tester), 'Category 34');
        if (lastRows == 1) {
          expect(position.pixels, closeTo(position.maxScrollExtent, .5));
          final last = find.byKey(const ValueKey('row-3400'));
          expect(
            tester.getBottomLeft(last).dy,
            closeTo(tester.getBottomLeft(find.byType(CustomScrollView)).dy, 1),
          );
        } else {
          expect(_titleError(tester, 34), closeTo(0, 1));
        }
        expect(_state(tester).navigationPhase, isNull);
      },
    );
  }
}

ValueKey<String> _topRow(WidgetTester tester) {
  final viewport = tester.getRect(find.byType(CustomScrollView));
  final rows =
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('row-'),
          )
          .evaluate()
          .where((e) {
            final rect = tester.getRect(find.byWidget(e.widget));
            return rect.bottom > viewport.top && rect.top < viewport.bottom;
          })
          .toList()
        ..sort(
          (a, b) => tester
              .getTopLeft(find.byWidget(a.widget))
              .dy
              .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
        );
  return rows.first.widget.key! as ValueKey<String>;
}
