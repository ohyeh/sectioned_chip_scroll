# Glossary

One term, one meaning. Code, docs, tests and commit scopes use these words.

## Layers (`lib/src/`)

| Layer | Holds | Depends on |
|---|---|---|
| `domain/` | Section data and its rules: `ChipSection`, `SectionCategory`, `uniqueIds`, section geometry (`SectionedGeometry`, `SectionedSectionGeometry`, `SectionedMeasurementHost`). | `flutter/foundation`, `flutter/painting` only |
| `application/` | Immutable options a host app passes in, with no widgets and no orchestration: `SectionedChipScrollConfig`, `CategorizedChipScrollConfig`, `SectionedChipScrollLabels`, behavior enums. | foundation |
| `presentation/` | Widgets, render objects, style and motion: the two views, chip bar, picker, layouts, `SectionedChipScrollStyle`. | domain, application, Flutter widgets |

`lib/sectioned_chip_scroll.dart` is the only public import. Files under
`lib/src/` are not a public interface.

## Terms

| Term | Meaning | Code |
|---|---|---|
| Section | One titled group of items in the content list. | `ChipSection` |
| Category | A level-1 group of sections, shown as tabs. | `SectionCategory`, `CategorizedChipScrollView` |
| Chip | The control for one section in the chip bar or the picker. | `ChipControl` |
| Chip bar | The horizontal row of chips above the content. | `SectionedChipScrollView` |
| Leading inset | Space before the first chip; a picked chip never scrolls past it. | `chipBarLeadingInset` |
| Edge fade | Fade at a chip bar edge; shown only where more chips exist. | `showChipFade` |
| Picker | The overlay with every chip. The board button (▼) opens it; its header button (▲) closes it in the same slot. | `picker.dart`, `PickerPanel` |
| Scroll-spy | Selecting the chip of the topmost visible section while the content scrolls. | `_spy` |
| Jump | Moving the content to a section after a chip tap. | `_jump*` |
| Far jump | A jump to a section not built yet; the list is anchored at the target instead of measuring every row before it. | anchored `CustomScrollView` center |
| Layout | How a section's items are placed: grid or one item per row. | `SectionedGridLayout`, `SectionedListLayout` |
| Geometry | Measured row extents and offsets used to place a jump target. | `SectionedGeometry` |
