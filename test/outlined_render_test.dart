import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

const _out = String.fromEnvironment('RENDER_OUT');
const _fonts = String.fromEnvironment('SCS_FONT_DIR');
const _suffix = String.fromEnvironment('RENDER_SUFFIX');

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

  for (final categories in [3, 1]) {
    for (final scale in [1.0, 3.12]) {
      final name =
          'outlined-${categories == 3 ? 'with-rail' : 'rail-hidden'}-$scale';
      testWidgets(name, (tester) async {
        final previousShadows = debugDisableShadows;
        try {
          if (_fonts.isNotEmpty) debugDisableShadows = false;
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: _fonts.isEmpty ? null : 'PingFang TC',
                colorSchemeSeed: const Color(0xFFB42318),
                scaffoldBackgroundColor: Colors.white,
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    appBar: AppBar(
                      title: const Text('分類瀏覽'),
                      backgroundColor: Colors.white,
                    ),
                    body: CategorizedChipScrollView<String>(
                      categories: [
                        for (var i = 0; i < categories; i++)
                          SectionCategory(
                            id: 'c$i',
                            label: ['文具', '生活', '保健'][i],
                            sections: [
                              for (final label in ['筆類', '本冊', '收納'])
                                ChipSection(
                                  id: label,
                                  label: label,
                                  items: [
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
                        expand: '展開分類',
                        changeCategory: '切換分類',
                      ),
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
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final state = tester.state<SectionedChipScrollViewState<String>>(
            find.byType(SectionedChipScrollView<String>),
          );
          expect(state.geometry!.sections.first.extent, isNotNull);
          // At AX5 the 3-category case must retain the existing picker fallback.
          expect(
            find.byIcon(Icons.unfold_more),
            categories == 3 && scale > 3 ? findsOneWidget : findsNothing,
          );
          if (_out.isNotEmpty) {
            expect(_fonts, isNotEmpty, reason: 'Evidence requires real fonts');
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$_out/$name$_suffix.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        } finally {
          debugDisableShadows = previousShadows;
        }
      });
    }
  }
}
