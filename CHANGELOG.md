# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `DockCore`: `com.apple.dock` reading through `CFPreferences`, defensive decoding, tile validation, tile ordering, icon rasterization and caching, and a diffing `DockStateStore`.
- `DockKit`: non-activating dock-level `NSPanel`, layer-backed tile rendering with running indicators, pure geometry and magnification math, display identity and reconciliation with controller pooling, and system-Dock host detection.
- `Dockyard`: menu bar status item, SwiftUI settings window with per-display toggles, launch at login through `SMAppService`.
- Bottom, left, and right orientation geometry; magnification driven by mouse-moved events with no timer.
- Vertical alignment taken from the real Dock's reserved screen edge, so Dockyard's bar sits at the same distance from the screen edge as the system Dock at any `tilesize`.
- Fixture-driven test suites for decoding, validation, ordering, snapshot diffing, geometry, the magnification curve, and coordinate conversion.
- `Scripts/calibrate.swift`, `Scripts/benchmark.sh`, `Scripts/lint-forbidden-apis.sh`, `Scripts/make-app.sh`, `Scripts/build-release.sh`, `Scripts/notarize.sh`, `Scripts/make-icon.swift`.

### Fixed

- The Trash tile never showed its full state. Reading `~/.Trash` needs Full Disk Access, so the planned `contentsOfDirectory` check failed silently and always reported empty; `getattrlist` with `ATTR_DIR_ENTRYCOUNT` returns the count with no permission. The Trash watcher was removed for the same reason, and the count is now re-read on every rebuild.
- The Trash used a dark, dated bin image. It now uses the Dock's own `s-trashempty` and `s-trashfull` artwork, with a fallback chain.
- Calendar showed its static bundle icon. `CalendarTileRenderer` now draws the localized weekday and today's date over it, keyed into the icon cache and refreshed on `NSCalendarDayChanged`, so no timer is involved.
- Magnification snapped straight to full size on entry. It now ramps over 0.20 s and decays to instant cursor tracking, and collapses over 0.16 s on exit.

- Magnification felt sluggish and never collapsed after the cursor left the bar. The tracking area was being removed and re-added on every `mouseMoved`, which both dominated the per-event cost and broke AppKit's enter and exit bookkeeping. The tracking rect is now the panel's stable bounds.
- The right-click menu opened at the cursor and overlapped the bar. It now opens above the tile, horizontally centred on it and clamped to the panel.
- Redundant per-event work removed: the running-indicator image and the bar's corner radius and border are only reassigned when they actually change.

### Known gaps

- Auto-hide reveal behaviour is modelled but not implemented.
- Clock renders its static bundle icon: a live second hand needs a timer, which the project bans. Calendar is drawn instead of loaded.
- Minimized windows do not get their own tiles.
- Folder tiles reveal in Finder rather than fanning out.
- No window list or minimized-window restore.
