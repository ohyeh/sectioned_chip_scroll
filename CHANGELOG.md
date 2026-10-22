## 0.2.0

- Far jumps anchor the list at the target section, so a jump to an unbuilt
  section starts at once and lands exactly.
- Picker: clip reveal from the chip bar, ▲ close button in the ▼ slot, both
  vertically centered; the chevron scales with text up to 2×; hit areas at
  least 48×48.
- Picker taps during a slow ballistic scroll select the chip.
- A picked long chip keeps the leading inset; chip width is capped at the
  visible bar width.
- Chip bar edge fades show only where more chips exist; fade width equals
  the leading inset.
- Default both views to a one-item-per-row list. Grid layout is opt-in;
  `columnsBuilder` requires an explicit grid layout.
- Show example items as rows with a 72×72 leading placeholder.
- Sources are organized into `domain/`, `application/` and `presentation/`
  layers (see `GLOSSARY.md`). The public import is unchanged.

## 0.1.0

* First release: `SectionedChipScrollView` with a scroll-spy chip bar,
  tap-to-jump with re-measured correction, an expand picker, and
  `SectionedChipScrollConfig` switches for chip semantics, expand button,
  chip fade, section chevron, empty sections and a text scale cap.
* `CategorizedChipScrollView`: category tabs (side rail, top tabs or a
  picker button) above the sections view, with kept state per category,
  roving keyboard focus, and optional announcements.
