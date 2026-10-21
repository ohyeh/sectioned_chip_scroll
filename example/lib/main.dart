import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const DemoApp());
}

/// Motion scenes with stable labels for device automation.
class DemoApp extends StatelessWidget {
  /// Creates the example.
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(
      appBar: AppBar(title: const Text('sectioned_chip_scroll')),
      body: Builder(
        builder: (context) => ListView(
          children: [
            for (final scene in ['few', 'flow', 'many', 'long'])
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                  child: Text(scene),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => _Scene(scene)),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

const _shortNames = ['Food', 'Sport', 'Care'];
const _flowNames = [
  'Food',
  'Sport',
  'Care',
  'Beauty',
  'Family',
  'Travel',
  'Books',
];
const _longNames = [
  '藥',
  '3C',
  '超商賣場',
  '健康照護與樂齡生活品牌',
  '一個非常非常非常非常非常長的分類名稱超過一行',
  '美妝',
  '寵物用品',
  '親子',
];

class _Scene extends StatefulWidget {
  const _Scene(this.name);
  final String name;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  double _scale = 1;
  String? _selected;

  List<String> get _names => switch (widget.name) {
    'few' => _shortNames,
    'flow' => _flowNames,
    'many' => [
      for (var i = 1; i <= 35; i++) 'Category ${i.toString().padLeft(2, '0')}',
    ],
    _ => _longNames,
  };

  @override
  Widget build(BuildContext context) {
    final names = _names;
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_scale)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.name),
          actions: [
            TextButton(
              onPressed: () => setState(() => _scale = _scale == 1 ? 3.12 : 1),
              child: Text(
                'scale ${_scale == 1 ? '1.0' : '3.12'}',
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ),
        body: SectionedChipScrollView<String>(
          sections: [
            for (var i = 0; i < names.length; i++)
              ChipSection(
                id: 'section-$i',
                label: names[i],
                items: [
                  for (var j = 0; j < (i < 2 ? 6 : 30); j++)
                    '${names[i]} item ${j + 1}',
                ],
              ),
          ],
          labels: const SectionedChipScrollLabels(
            panelTitle: 'Choose a category',
            expand: 'Show all categories',
            collapse: 'Collapse all categories',
            barrier: 'Dismiss all categories',
          ),
          config: const SectionedChipScrollConfig(panelBottomInset: 56),
          onSectionSelected: (section) =>
              setState(() => _selected = section.label),
          itemBuilder: (context, label) => Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined, size: 40),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              _selected ?? names.first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
