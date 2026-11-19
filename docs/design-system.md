# Design System & Visual Identity

SYNQRA rejects sterile, homogenized design conventions in favor of a **Neo-Brutalist Archival aesthetic**. The visual language is engineered to feel like an authoritative, high-density scientific instrument.

---

## Design Principles

1. **Tactile Brutalism**: High-contrast solid borders (1.5px - 2.5px) paired with hard-edge directional drop shadows (`Offset(3, 3)`) with zero gaussian blur.
2. **Archival Typography**: High-character editorial slab-serifs for headlines paired with monospaced precision for technical readouts and latency data.
3. **Information Density**: Maximum screen utilization with structured modular cards, progress bars, and metadata chips.
4. **Zero Blurry Bitmaps**: Vector canvas rendering throughout with crisp vector glyphs and typography.

---

## Palette Tokens

All colors are codified in `lib/core/theme/app_theme.dart`:

| Token | Parchment (Light) | Nocturne (Dark) | Usage |
|---|---|---|---|
| **`scaffoldBackground`** | `#F5EFE6` (Warm Parchment) | `#121110` (Obsidian) | Root canvas background |
| **`surfaceBackground`** | `#EDE6DB` (Toned Vellum) | `#1C1A18` (Smoked Charcoal) | Card containers, terminal docks |
| **`solidBorder`** | `#1A1918` (Charcoal Carbon) | `#3D3833` (Warm Carbon) | High-contrast borders |
| **`accentVermilion`** | `#FF4C29` (Vermilion) | `#FF5C38` (Vivid Vermilion) | CTAs, active pills, blinking cursors |
| **`statusIndexed`** | `#2E7D32` (Forest Green) | `#4CAF50` (Emerald) | Completed indexing badges |
| **`statusFailed`** | `#D32F2F` (Crimson) | `#EF5350` (Coral Red) | Error alerts and failed chunking |
| **`textPrimary`** | `#121110` (Ink Black) | `#F2ECE4` (Parchment Cream) | Headlines, body copy, data values |
| **`textMuted`** | `#6B655E` (Archive Dust) | `#9E978F` (Nocturne Dust) | Telemetry codes, captions, hashes |

---

## Typography Hierarchy

- **Display & Headings**: `GoogleFonts.fraunces()` / `GoogleFonts.newsreader()` — Editorial slab-serif character with fallback to system `serif` and `Times New Roman`.
- **Telemetry & Readouts**: `GoogleFonts.jetBrainsMono()` — Monospaced fixed-width precision for latency metrics, hashes, and vector coordinates.
- **Reading Body**: Standard serif with generous line height (`1.55`) for readable research synthesis.

---

## Brutalist Shadow Physics

Containers in SYNQRA utilize hard-edge directional drop shadows implemented via `AppTheme.brutalistShadow()`:

```dart
static List<BoxShadow> brutalistShadow(
  Color borderColor, {
  Offset offset = const Offset(3, 3),
}) {
  return [
    BoxShadow(
      color: borderColor,
      offset: offset,
      blurRadius: 0, // Zero blur creates the iconic brutalist edge
    ),
  ];
}
```

---

## Android 12+ Adaptive Launcher Icons

The application includes custom-engineered vector adaptive icons:
- **Foreground**: Tactile `SYNQRA` monogram on geometric lattice (`adaptive_foreground.png`).
- **Monochrome**: Android 13+ material themed monochrome mask (`adaptive_monochrome.png`).
- **Background Sync**: Splash and launch window background synchronized to `#F5EFE6` to ensure zero launch flicker.
