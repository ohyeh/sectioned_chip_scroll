# sectioned_chip_scroll

A scroll-spy chip bar for sectioned content in Flutter.

- A row of chips above the list, one per section. Scrolling selects the
  chip of the section in view.
- Tap a chip to scroll its section to just below the bar.
- An optional expand button opens a picker with every section.
- Built for large text: chip labels wrap and grow instead of being cut,
  and the bar keeps working up to the largest system text size.

Not related to the `scroll_spy` package.

## Usage

```dart
SectionedChipScrollView<Product>(
  sections: [
    ChipSection(id: 'fruit', label: 'Fruit', items: fruits),
    ChipSection(id: 'dairy', label: 'Dairy', items: dairy),
  ],
  itemBuilder: (context, product) => ProductTile(product),
)
```

The view is a scroll view, so give it bounded height: the body of a
`Scaffold`, or a child of `Expanded`.

`id` must be non-empty, unique and stable across data updates. The view keeps
the selection by `id`: when the selected section disappears, the first section
is selected. Sections are shown in the order you give; the view does not sort
or remove duplicates. With no sections to show, the view builds nothing, so
show your own empty state.

A rebuild with changed sections (ids, order, labels, or items compared with
`==`) stops a running jump and closes the picker. Give item types value
equality, or pass the same item lists again, so that an unchanged rebuild is
not taken as a change.

## Options

Behavior that differs between products is a switch in
`SectionedChipScrollConfig`:

| Field | Default | Effect |
|---|---|---|
| `chipSemantics` | `link` | Chips are links in a navigation landmark, or `tab`s. |
| `showExpandButton` | `true` | Button that opens the section picker. |
| `showChipFade` | `true` | Fade at the trailing edge of the chip bar. |
| `showSectionChevron` | `false` | Chevron after each section title (looks only). |
| `showEmptySections` | `false` | Show sections with no items. |
| `maxTextScale` | `null` | Upper limit for text scale inside the view and picker. |
| `focusAfterNavigate` | `preserve` | `announce` also reads the new section or category name once, where announcements are supported. |

Callbacks on the widget:

- `onSectionTap`: makes section titles tappable. When null, titles are plain
  headers with no tap target. Pair it with `showSectionChevron`.
- `onSectionSelected`: called when the selected section changes.
- `columnsBuilder`: number of item columns for a width and text scale.
- `initialSectionId`: section selected on the first build (no scroll).

## Categories (two levels)

`CategorizedChipScrollView` adds a level above the sections: category tabs
that switch which sections are shown.

```dart
CategorizedChipScrollView<Product>(
  categories: [
    SectionCategory(id: 'food', label: 'Food', sections: foodSections),
    SectionCategory(id: 'home', label: 'Home', sections: homeSections),
  ],
  itemBuilder: (context, product) => ProductTile(product),
)
```

- Tabs sit in a side rail at the start edge. With one category they are
  hidden, and the view is the plain sections view.
- When the rail would leave too little width for the content (large text on
  a narrow screen), `railLargeTextLayout` takes over: `picker` (default, one
  button that opens a category picker), `topTabs` (a row above the chip bar)
  or `rail` (keep the rail; names wrap).
- `keepCategoryState` (default `true`) brings back the selected section and
  scroll position when you return to a category.
- Section ids only need to be unique within a category.

`CategorizedChipScrollConfig` fields: `sectionConfig`, `showRailWhenSingle`,
`railWidth`, `railLargeTextLayout`, `keepCategoryState`.

## Theming and text

Colors come from the ambient `ColorScheme` (`surface`, `primaryContainer`,
`onPrimaryContainer`, `surfaceContainerHighest`) and text from `TextTheme`
(`labelLarge` for chips, `titleMedium` for titles). Override text with
`chipTextStyle`, `selectedChipTextStyle`, `sectionTitleStyle` and
`panelTitleStyle`.

Labels are English by default. Pass `SectionedChipScrollLabels` to translate
the button tooltips, picker title and the chip position label
(`'Fruit, 2 of 5'`).

## Accessibility

- Each chip reads its name, its position and whether it is selected.
- Section titles are headers; the chevron is not read out.
- Category tabs are tabs in a tab bar, with position and selected state.
  They switch only when activated (tap, double tap, Enter or Space); moving
  focus over them does not switch.
- Keyboard: the category tabs are one Tab stop on the selected tab, arrow
  keys move between them, and one Tab moves on to the content.
- Focus stays on the chip or tab you activated. Moving screen reader focus
  to the content is not offered: it is not verified on iOS and Android.
- The picker is a modal route: the content behind it is hidden from screen
  readers, and it closes with its close button or by tapping outside.
- The picker uses the view's text scale and theme, even when the view sits
  under a local `MediaQuery`.

## Behavior notes

- A jump to a section that is not laid out yet first lands on an estimate,
  then measures and corrects (up to three times). If it still cannot align,
  it reports through `FlutterError.reportError`.
- When the last sections are too short to reach the top, a jump ends at the
  bottom of the list and that section stays selected until the list leaves
  the bottom.
- A chip tap during a jump starts the new jump at once: the chip bar is not
  part of the scrolling list.
- Touching the list during a jump stops the jump. The underlying
  `scrollview_observer` scroll can still finish its current step.

## Example

See `example/` for a demo where every option can be switched at run time.
