# Geometry and calibration

Dockyard reads every geometric value the Dock exposes and derives, measures, or fits the rest. This file records where each number comes from so it can be re-derived when Apple changes the Dock's appearance.

## Read from `com.apple.dock`

| Value | Key |
|---|---|
| Base tile size | `tilesize` |
| Magnified tile size | `largesize` |
| Magnification on | `magnification` |
| Orientation | `orientation` |
| Running indicators | `show-process-indicators` |
| Recents section | `show-recents` |
| Auto-hide and its timings | `autohide`, `autohide-delay`, `autohide-time-modifier` |

Every one of these is clamped on read. `tilesize` can be set to any value with `defaults write`, and an unclamped value produces either an invisible bar or one wider than the screen.

## Measured from the system at runtime

**Reserved edge strip.** The display hosting the real Dock has its `visibleFrame` inset from its `frame` on the Dock's edge. That inset is `barThickness + screenEdgeMargin` for the real Dock, so Dockyard uses it directly and derives its own margin as `reservedStrip - barThickness`. The result is that Dockyard's bar sits at exactly the same distance from the screen edge as the system Dock, at any `tilesize`, on any macOS version, without a fitted constant.

Measured on macOS 26.5 with `tilesize` 27: the strip is 47 points. The ratio-only fallback would have produced 40.

The fallback applies only when no display reserves an edge, which means the Dock is auto-hidden or hidden by a full-screen app.

## Fitted constants in `DockMetrics`

These are the values the Dock does not expose. They are expressed as ratios of `tilesize` with absolute floors, because the real Dock does not scale everything linearly down to tiny tile sizes.

| Constant | Sonoma / Sequoia | Tahoe (macOS 26) | Basis |
|---|---|---|---|
| `barPaddingRatio` | 0.1042 | 0.2222 | Tahoe fitted to the measured 47-point strip at `tilesize` 27; earlier releases fitted to a 48-point Dock |
| `screenEdgeMarginRatio` | 0.0833 | 0.2963 | Same fit; only used as a fallback |
| `interTileSpacingRatio` | 0.0833 | 0.1100 | Screenshot measurement, **the least certain value here** |
| `cornerRadiusRatio` | 0.28 | 0.50 | Tahoe's dock is effectively a capsule |
| `separatorLengthRatio` | 0.25 | 0.25 | Screenshot measurement |
| `smallSpacerLengthRatio` | 0.50 | 0.50 | Half a tile, per the Dock's own behaviour |
| `indicatorDiameterRatio` | 0.0833 | 0.0833 | Screenshot measurement, floor of 3 points |
| `magnificationWindowTiles` | 3.0 | 3.0 | Curve fit; see below |

Floors: spacing at least 3 points, bar padding at least 5, edge margin at least 3. Without the padding floor the running indicator does not fit inside the bar at small tile sizes.

The indicator inset is derived rather than fitted: `(barPadding - indicatorDiameter) / 2`, so the dot is centred in the padding strip below the tile.

## Magnification curve

The system Dock's magnification is not a linear falloff, and adjacent tiles are displaced outward so that the hovered tile stays under the cursor.

The model is `s(d) = 1 + (max - 1) · ½(1 + cos(πd / R))` for `|d| ≤ R`, where `d` is distance from the cursor in tile-pitch units, `R` is `magnificationWindowTiles`, and `max` is `largesize / tilesize`. It gives the maximum at the cursor, unity at the window edge, a smooth monotone falloff between, and it is symmetric.

Positions are then integrated outward from the cursor: the tile under the cursor keeps the cursor at the same fractional position within itself, and every other tile is placed by accumulating magnified widths. That anchoring is what makes magnification feel correct rather than merely animated. The run is clamped so the bar never leaves the display, and when the bar is wider than the display it pins to the leading edge.

Unit tests assert the peak, the falloff to unity, monotonicity, symmetry, that total width equals the sum of scaled widths plus gaps and padding, that the hovered tile still contains the cursor, and that clamping holds at both edges.

## Re-deriving

```bash
Scripts/calibrate.swift
```

The script prints the Dock's preferences, every display's frame, visible frame, and insets, the reserved strip and its ratio to `tilesize`, and the Dock's window bounds at dock level.

On macOS 26 the script cannot derive spacing or padding from window bounds: the Dock's dock-level window spans its entire display rather than hugging the bar. Those two constants must still be measured from a screenshot at a known `tilesize`. Turn auto-hide off, remove recents, quit unpinned applications, screenshot the Dock, measure the gap between two adjacent icons and the space above one, then divide by `tilesize` and update `DockMetrics`.
