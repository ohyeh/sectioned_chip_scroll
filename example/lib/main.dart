import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:sectioned_chip_scroll/sectioned_chip_scroll.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Build the semantics tree without a screen reader, so UI automation
  // (XCUITest, UiAutomator) can read the chip labels.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const DemoApp());
}

/// Demo item: a colored tile with a label.
class DemoItem {
  /// Creates an item.
  const DemoItem(this.label, this.color);

  /// Label under the tile.
  final String label;

  /// Tile color.
  final Color color;
}

const _names = [
  'Alpha',
  'Bravo, a long section name that wraps',
  'Charlie',
  'Delta and Echo, another long section name',
  'Foxtrot',
  'Golf',
  'Hotel',
  'India and Juliett, a long one',
  'Kilo',
  'Lima',
  'Mike',
  'November',
  'Oscar',
  'Papa',
  'Quebec, no items',
];
const _counts = [8, 12, 10, 9, 8, 11, 14, 7, 9, 6, 7, 8, 10, 15, 0];

final _sections = [
  for (var s = 0; s < _names.length; s++)
    ChipSection<DemoItem>(
      id: 'section-$s',
      label: _names[s],
      items: [
        for (var i = 0; i < _counts[s]; i++)
          DemoItem(
            i % 4 == 3 ? 'Item $s-$i with a long name' : 'Item $s-$i',
            Colors.primaries[(s + i) % Colors.primaries.length].shade300,
          ),
      ],
    ),
];

/// Three level-1 categories that reuse the sections with their own ids.
final _categories = [
  SectionCategory<DemoItem>(id: 'all', label: 'All', sections: _sections),
  SectionCategory<DemoItem>(
    id: 'first-half',
    label: 'First half, a long category name',
    sections: _sections.sublist(0, 7),
  ),
  SectionCategory<DemoItem>(
    id: 'second-half',
    label: 'Second half',
    sections: _sections.sublist(7),
  ),
];

const _zhLabels = SectionedChipScrollLabels(
  expand: '展開全部段落',
  collapse: '收合',
  barrier: '關閉段落面板',
  panelTitle: '全部段落',
  position: _zhPosition,
  changeCategory: '切換類別',
  categoryPanelTitle: '全部類別',
  categoryBarrier: '關閉類別面板',
);

String _zhPosition(String label, int i, int n) => '$label，第 $i 個，共 $n 個';

/// Text scale caps offered in the settings sheet, by name.
const _caps = <String, double?>{
  'No cap': null,
  '1.94 (iOS AX2)': 33 / 17,
  '2.35 (iOS AX3)': 40 / 17,
};

/// The demo: the view plus a settings sheet that flips every option.
class DemoApp extends StatefulWidget {
  /// Creates the demo.
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  SectionedChipScrollConfig get _config => _outer.sectionConfig;

  var _outer = const CategorizedChipScrollConfig();
  var _manyCategories = false;
  var _tappableTitles = false;
  var _dark = false;
  var _zh = false;
  var _status = 'Selected: ${_sections.first.label}';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('sectioned_chip_scroll'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Text(
              _status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => _openSettings(context),
            ),
          ],
        ),
        body: CategorizedChipScrollView<DemoItem>(
          categories: _manyCategories ? _categories : [_categories.first],
          config: _outer,
          onCategorySelected: (c) =>
              setState(() => _status = 'Category: ${c.label}'),
          labels: _zh ? _zhLabels : const SectionedChipScrollLabels(),
          itemBuilder: (context, item) => _Tile(item),
          onSectionSelected: (s) =>
              setState(() => _status = 'Selected: ${s.label}'),
          onSectionTap: _tappableTitles
              ? (s) => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('Title: ${s.label}')))
              : null,
        ),
      ),
    ),
  );

  void _openSettings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        void update(VoidCallback change) {
          setState(change);
          setSheet(() {});
        }

        void section(
          SectionedChipScrollConfig Function(SectionedChipScrollConfig) f,
        ) => update(() => _outer = _outer.copyWith(sectionConfig: f(_config)));

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Three categories'),
                  value: _manyCategories,
                  onChanged: (v) => update(() => _manyCategories = v),
                ),
                SwitchListTile(
                  title: const Text('Rail with one category'),
                  value: _outer.showRailWhenSingle,
                  onChanged: (v) => update(
                    () => _outer = _outer.copyWith(showRailWhenSingle: v),
                  ),
                ),
                ListTile(
                  title: const Text('When the rail does not fit'),
                  trailing: DropdownButton<CategoryFallbackLayout>(
                    value: _outer.railLargeTextLayout,
                    items: [
                      for (final l in CategoryFallbackLayout.values)
                        DropdownMenuItem(value: l, child: Text(l.name)),
                    ],
                    onChanged: (v) => update(
                      () => _outer = _outer.copyWith(railLargeTextLayout: v),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Keep category state'),
                  value: _outer.keepCategoryState,
                  onChanged: (v) => update(
                    () => _outer = _outer.copyWith(keepCategoryState: v),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Announce after navigation'),
                  value:
                      _config.focusAfterNavigate == FocusAfterNavigate.announce,
                  onChanged: (v) => section(
                    (c) => c.copyWith(
                      focusAfterNavigate: v
                          ? FocusAfterNavigate.announce
                          : FocusAfterNavigate.preserve,
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Chip semantics'),
                  trailing: SegmentedButton<ChipSemantics>(
                    segments: const [
                      ButtonSegment(
                        value: ChipSemantics.link,
                        label: Text('link'),
                      ),
                      ButtonSegment(
                        value: ChipSemantics.tab,
                        label: Text('tab'),
                      ),
                    ],
                    selected: {_config.chipSemantics},
                    onSelectionChanged: (v) =>
                        section((c) => c.copyWith(chipSemantics: v.single)),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Expand button'),
                  value: _config.showExpandButton,
                  onChanged: (v) =>
                      section((c) => c.copyWith(showExpandButton: v)),
                ),
                SwitchListTile(
                  title: const Text('Chip fade'),
                  value: _config.showChipFade,
                  onChanged: (v) => section((c) => c.copyWith(showChipFade: v)),
                ),
                SwitchListTile(
                  title: const Text('Section chevron'),
                  value: _config.showSectionChevron,
                  onChanged: (v) =>
                      section((c) => c.copyWith(showSectionChevron: v)),
                ),
                SwitchListTile(
                  title: const Text('Empty sections'),
                  value: _config.showEmptySections,
                  onChanged: (v) =>
                      section((c) => c.copyWith(showEmptySections: v)),
                ),
                SwitchListTile(
                  title: const Text('Tappable section titles'),
                  value: _tappableTitles,
                  onChanged: (v) => update(() => _tappableTitles = v),
                ),
                ListTile(
                  title: const Text('Text scale cap'),
                  trailing: DropdownButton<double?>(
                    value: _config.maxTextScale,
                    items: [
                      for (final e in _caps.entries)
                        DropdownMenuItem(value: e.value, child: Text(e.key)),
                    ],
                    onChanged: (v) =>
                        section((c) => c.copyWith(maxTextScale: () => v)),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Dark theme'),
                  value: _dark,
                  onChanged: (v) => update(() => _dark = v),
                ),
                SwitchListTile(
                  title: const Text('Traditional Chinese labels'),
                  value: _zh,
                  onChanged: (v) => update(() => _zh = v),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.item);

  final DemoItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 48, height: 48, color: item.color),
        const SizedBox(height: 4),
        Text(item.label, textAlign: TextAlign.center),
      ],
    ),
  );
}
