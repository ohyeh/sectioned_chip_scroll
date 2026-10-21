import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

const _out = String.fromEnvironment('TAPS_OUT');
const _fonts = String.fromEnvironment('SCS_FONT_DIR');
const _polish = bool.fromEnvironment('POLISH');
const _stage2 = bool.fromEnvironment('STAGE2');

String _position(String label, int i, int n) => '$label，第 $i 個，共 $n 個';

void main() {
  setUpAll(() async {
    if (_fonts.isEmpty) return;
    for (final family in ['PingFang TC', 'MaterialIcons']) {
      final filename = family == 'PingFang TC'
          ? 'PingFangTC.ttf'
          : 'MaterialIcons-Regular.otf';
      final loader = FontLoader(family);
      for (final file in [
        filename,
        if (family == 'PingFang TC') ...[
          'PingFangTC-Medium.ttf',
          'PingFangTC-Semibold.ttf',
        ],
      ]) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(File('$_fonts/$file').readAsBytesSync()),
          ),
        );
      }
      await loader.load();
    }
  });

  for (final sequence
      in _stage2
          ? ['B', 'C']
          : _polish
          ? ['A', 'B', 'C', 'A-none']
          : ['A', 'B', 'C', 'D']) {
    testWidgets('AX5 tap sequence $sequence', (tester) async {
      final previousShadows = debugDisableShadows;
      try {
        if (_fonts.isNotEmpty) debugDisableShadows = false;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final point = ValueNotifier<Offset?>(null);
        final boundaryKey = GlobalKey();
        final images = <ui.Image>[];
        final captions = <String>[];
        var elapsed = 0;
        var selectedCategory = '文具';
        var selectedSection = '筆類';
        final positions = <double>[];
        final focusIds = <FocusNode, int>{};
        final motion = <(int, double)>[];

        ScrollPosition getPosition() => tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              ),
            )
            .position;

        Future<void> pump(int ms) async {
          var remaining = ms;
          while (remaining > 0) {
            final step = remaining > 16 ? 16 : remaining;
            elapsed += step;
            remaining -= step;
            await tester.pump(Duration(milliseconds: step));
            motion.add((elapsed, getPosition().pixels));
          }
        }

        Future<void> mark(Finder finder) async {
          point.value = tester.getCenter(finder);
          await tester.pump();
        }

        Future<void> frame(String description) async {
          final number = (captions.length + 1).toString().padLeft(2, '0');
          final name =
              '$sequence-$number-${elapsed.toString().padLeft(3, '0')}ms';
          captions.add('$name | $description');
          final position = getPosition();
          if (_stage2 && sequence == 'B' && description == 'closing') {
            expect(
              position.pixels,
              0,
              reason: 'picker must finish closing before navigation',
            );
          }
          positions.add(position.pixels);
          final focus = FocusManager.instance.primaryFocus;
          final focusId = focus == null
              ? 'none'
              : 'f${focusIds.putIfAbsent(focus, () => focusIds.length)}';
          debugPrint(
            'FRAME $name $description category=$selectedCategory '
            'section=$selectedSection offset=${position.pixels.toStringAsFixed(2)} '
            'focus=$focusId/${focus?.debugLabel}',
          );
          expect(tester.takeException(), isNull);
          if (_out.isEmpty) return;
          expect(
            _fonts,
            isNotEmpty,
            reason: 'PNG evidence requires real fonts',
          );
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            images.add(image);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$_out/$sequence/$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
        }

        Future<void> tap() async {
          final gesture = await tester.startGesture(point.value!);
          await pump(80);
          await frame('pointer DOWN; before commit');
          await gesture.up();
          await tester.pump();
        }

        Finder header(String label) => find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text(label),
        );

        void expectVisible(String label) {
          final viewport = tester.getRect(find.byType(CustomScrollView));
          expect(tester.getRect(header(label)).overlaps(viewport), isTrue);
          expect(selectedSection, label);
        }

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: _fonts.isEmpty ? null : 'PingFang TC',
              colorSchemeSeed: const Color(0xFFB42318),
              scaffoldBackgroundColor: Colors.white,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.12)),
              child: RepaintBoundary(
                key: boundaryKey,
                child: Stack(
                  children: [
                    Positioned.fill(child: child!),
                    ValueListenableBuilder<Offset?>(
                      valueListenable: point,
                      builder: (_, value, _) => value == null
                          ? const SizedBox.shrink()
                          : Positioned(
                              left: value.dx - 7,
                              top: value.dy - 7,
                              child: IgnorePointer(
                                child: ExcludeSemantics(
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.red.withValues(alpha: 0.15),
                                      border: Border.all(
                                        color: Colors.red,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            home: Scaffold(
              appBar: AppBar(
                title: const Text('分類瀏覽'),
                backgroundColor: Colors.white,
              ),
              body: CategorizedChipScrollView<String>(
                style: SectionedChipScrollStyle.outlined(
                  pickerTransition: _polish && sequence != 'A-none'
                      ? PickerTransition.clipReveal
                      : PickerTransition.none,
                ),
                config: CategorizedChipScrollConfig(
                  railLargeTextLayout: sequence == 'D'
                      ? CategoryFallbackLayout.topTabs
                      : CategoryFallbackLayout.picker,
                ),
                categories: [
                  for (final category in ['文具', '生活', '保健'])
                    SectionCategory(
                      id: category,
                      label: category,
                      sections: [
                        for (final label in [
                          '筆類',
                          '本冊',
                          '收納',
                          '紙品',
                          '配件',
                          '其他',
                        ])
                          ChipSection(
                            id: label,
                            label: label,
                            items: const [
                              '日用好物',
                              '設計選物',
                              '經典系列',
                              '輕巧隨行',
                              '生活提案',
                              '簡約風格',
                            ],
                          ),
                      ],
                    ),
                ],
                labels: const SectionedChipScrollLabels(
                  expand: '展開段落',
                  collapse: '收合',
                  panelTitle: '全部段落',
                  categoryPanelTitle: '全部類別',
                  changeCategory: '切換類別',
                  position: _position,
                ),
                onCategorySelected: (category) =>
                    selectedCategory = category.label,
                onSectionSelected: (section) => selectedSection = section.label,
                itemBuilder: (_, item) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F1EC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.edit_outlined,
                            size: 28,
                            color: Color(0xFF746A5E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(item, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (sequence.startsWith('A') || sequence == 'B') {
          await mark(
            find.byIcon(
              sequence.startsWith('A') ? Icons.unfold_more : Icons.expand_more,
            ),
          );
          await frame('before tap');
          await tap();
          await pump(60);
          await frame('opening');
          await pump(60);
          await frame('opening');
          await pump(500);
          await mark(find.text(sequence.startsWith('A') ? '生活' : '收納').last);
          await frame('panel open; next tap marked');
          await tap();
          await frame('immediately after pick');
          await pump(60);
          await frame('closing');
          await pump(60);
          await frame('closing');
          await pump(500);
          await frame('route closed');
          await pump(800);
          await frame('final');
          if (sequence.startsWith('A')) {
            expect(selectedCategory, '生活');
            expect(find.text('全部類別'), findsNothing);
          } else {
            expectVisible('收納');
            expect(find.text('全部段落'), findsNothing);
          }
        } else if (sequence == 'C') {
          await mark(find.text('收納').first);
          await frame('before tap');
          await tap();
          await frame('immediately after tap');
          for (final ms in [60, 60, 60, 120, 120, 200, 400]) {
            await pump(ms);
            await frame(elapsed < 300 ? 'jump moving' : 'jump/final');
          }
          expectVisible('收納');
          expect(positions.last, greaterThan(positions.first));
          for (var i = 1; i < positions.length; i++) {
            expect(positions[i], greaterThanOrEqualTo(positions[i - 1]));
          }
        } else {
          expect(find.byIcon(Icons.unfold_more), findsNothing);
          await mark(find.text('生活').first);
          await frame('top tabs; before tap');
          await tap();
          await frame('top tab selected');
          await pump(220);
          await frame('final');
          expect(selectedCategory, '生活');
          expect(find.text('全部類別'), findsNothing);
        }

        if (_out.isNotEmpty) {
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawColor(Colors.white, BlendMode.src);
            for (var i = 0; i < images.length; i++) {
              final left = i * 390.0;
              canvas.drawImage(images[i], Offset(left, 52), Paint());
              final caption = TextPainter(
                text: TextSpan(
                  text: captions[i],
                  style: const TextStyle(
                    fontFamily: 'PingFang TC',
                    color: Colors.black,
                    fontSize: 14,
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: 382);
              caption.paint(canvas, Offset(left + 4, 4));
              caption.dispose();
            }
            final picture = recorder.endRecording();
            final sheet = await picture.toImage(images.length * 390, 896);
            final bytes = await sheet.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_out/$sequence/$sequence-sheet.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            sheet.dispose();
            picture.dispose();
            for (final image in images) {
              image.dispose();
            }
          });
        }
        debugPrint(
          'SEQUENCE $sequence frames=${captions.length} elapsed=${elapsed}ms',
        );
        final state = tester.state<SectionedChipScrollViewState<String>>(
          find.byType(SectionedChipScrollView<String>),
        );
        debugPrint('JUMP $sequence phase=${state.navigationPhase}');
        final steps = <String>[];
        var previous = 0.0;
        for (final sample in motion) {
          final delta = sample.$2 - previous;
          if (delta.abs() > 100) {
            steps.add('${sample.$1}ms:${delta.toStringAsFixed(2)}px');
          }
          previous = sample.$2;
        }
        debugPrint('MOTION $sequence stepsOver100px=$steps');
        if (_stage2) {
          var moves = 0;
          var previousOffset = 0.0;
          for (final sample in motion) {
            expect(sample.$2, greaterThanOrEqualTo(previousOffset));
            if (sample.$2 != previousOffset) moves++;
            previousOffset = sample.$2;
          }
          expect(moves, 1, reason: 'this far fixture makes one instant move');
          expect(state.navigationPhase, isNull);
          debugPrint('STAGE2 $sequence moves=$moves reversals=0');
        }
        if (_polish && !_stage2 && (sequence == 'B' || sequence == 'C')) {
          // Fixture regression: reject the former 472 px preparation jump.
          expect(steps, isEmpty);
          expect(state.navigationPhase, isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        point.dispose();
        semantics.dispose();
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }
}
