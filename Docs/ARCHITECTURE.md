# Architecture

## Guiding principle

**One source of truth, N render targets.**

Panels do not know about each other and never synchronize with each other. Each subscribes to the same immutable snapshot and renders it. "Every bar shows the same state" and "one bar cannot affect another" therefore fall out of the design rather than requiring coordination logic, which is where multi-window apps usually accumulate bugs.

## Packages

```
Packages/DockCore     model, observation, ordering, icons      no window code at all
Packages/DockKit      panels, rendering, geometry, displays     depends on DockCore
Dockyard              agent lifecycle, status item, settings    depends on both
```

`DockCore` has no `NSWindow`, no `NSView`, and no `CALayer`. That constraint is what makes it unit-testable with no display attached, and it is why the model layer can be published on its own as "read the macOS Dock configuration from Swift".

## Data flow

```
CFPreferences ─┐
FSEvents ──────┤
NSWorkspace ───┼──> DockStateStore ──(DockSnapshot)──> DockPanelController(s) ──> CALayer diff
CGDisplay ─────┘         (diff)                          (per display)
```

1. An observer fires: a preference change, an application launch, a display reconfiguration, a Trash change.
2. The observer posts to `DockStateStore` on the main actor.
3. The store re-reads only what changed. A preference change re-reads the domain; an app launch does not.
4. `TileOrdering.tiles(preferences:running:trashIsEmpty:)` produces a new `[DockTile]`.
5. The store compares the new array and the appearance with the previous snapshot. **If nothing changed it publishes nothing.** `didActivateApplicationNotification` fires on every app switch, and most of those do not change the rendered output.
6. If something changed, a new `DockSnapshot` is published with an incremented generation.
7. Each `DockPanelController` applies a **diff**: tiles that persisted keep their existing layers, only added and removed tiles allocate.
8. Icons that are not cached are requested from the `IconProvider` actor; the tile renders empty and swaps in the image on arrival.

## Concurrency

Swift 6 language mode, strict concurrency, no `@unchecked Sendable` anywhere.

- `DockStateStore`, `DisplayCoordinator`, every `DockPanelController`, and every observer are `@MainActor`. All AppKit interaction is main-thread by definition; making that explicit at the type level removes a class of bug rather than relying on discipline.
- `IconProvider` is an `actor`. Icon rasterization is the one genuinely expensive operation, and it happens off the main actor.
- Preference resolution — the part that touches the filesystem to validate paths — runs in a detached `.utility` task over `Sendable` inputs and returns a `Sendable` value.
- `DockSnapshot` and everything it contains are `Sendable` value types, so passing them across actor boundaries is free of data-race risk by construction.
- `NSRunningApplication` is never stored. It is a reference type with live KVO machinery; the observer extracts `RunningApplicationState` at the boundary.

## Observation

| Change | Signal | Work |
|---|---|---|
| Dock contents or appearance | `com.apple.dock.prefchanged` (distributed notification) | Re-read domain, resolve, order, diff |
| Same, fallback | `DispatchSource` watch on `~/Library/Preferences`, 50 ms debounce | Identical path |
| App launch, quit, activate, hide | `NSWorkspace.shared.notificationCenter` | Refresh running set, order, diff |
| Trash contents | none available | Entry count re-read on every rebuild, one syscall |
| Calendar day rollover | `NSCalendarDayChanged` | Re-request dynamic icons |
| Display add, remove, mode change | `CGDisplayRegisterReconfigurationCallback` | Hide panels on begin, reconcile 350 ms after the last end flag |
| Screen parameters, wake | `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.didWakeNotification` | Same settle path |
| Space switch | none needed | `.canJoinAllSpaces` handles it |

The preferences directory is watched, not the file: preference writes are atomic, a temporary file is renamed over the original, the inode changes, and a file-level watcher therefore dies silently after the first write.

Reconfiguration debouncing uses a **cancellable** settle task. A raw delay per event still produces N repositions for N events; cancelling collapses them into one.

## Display identity

Per-display settings are keyed on the EDID triple plus built-in flag plus an ordinal tiebreaker, never on `CGDirectDisplayID`. The window server can reassign that ID across disconnect, sleep, and GPU switching, which would otherwise produce the failure where a user disables the bar on their external display, unplugs it overnight, and finds the setting applied to the wrong screen. `CGDirectDisplayID` is still used for every runtime lookup; it is simply never written to disk.

Some monitors report a zero serial number and two identical panels can be indistinguishable, hence `ordinalFallback`, which uses arrangement order and only matters when the triple collides.

Controllers are **pooled** for two minutes after a display disappears. Closing and reopening a laptop lid is the common case, and reuse keeps a warm layer tree instead of rebuilding one.

## Rendering

- The panel is a `.borderless`, `.nonactivatingPanel` `NSPanel` at `CGWindowLevelForKey(.dockWindow)` with `canBecomeKey` overridden to `false`, so clicking a tile never steals focus from the frontmost app.
- The panel spans the full width of its display and is only as tall as a fully magnified tile needs. Magnification therefore never resizes the window, which would flicker. `hitTest` returns `nil` outside the bar, so the rest of the strip is click-through.
- The blur is an `NSVisualEffectView` sized to the bar rect with a corner radius. Tiles live in a sibling view **above** it, because a manually added sublayer of the content view's own layer is drawn below subview layers.
- One `DockTileLayer` per tile, holding an icon layer, an indicator layer, a separator layer, and a drop-target highlight. Icons are rasterized once to a `CGImage` at `largesize × maximum backing scale` and assigned as layer contents, so magnification is a GPU transform with no CPU cost per frame.
- All hot-path layer mutation happens inside `CATransaction` with actions disabled. Without that, every position assignment schedules an implicit quarter-second animation.
- Magnification is driven by `mouseMoved:` from an `.activeAlways` tracking area over the bar. A stationary cursor produces no events and therefore no work, which is strictly better than a display link that would run at 120 Hz regardless.

## Geometry

`DockGeometry` is pure and takes a `DockLayoutInput`, so it is fully testable headless. It handles all three orientations through a single along-axis and across-axis abstraction.

Vertical placement is taken from the system rather than modelled: the display hosting the real Dock reserves a strip at its edge, visible as the difference between `frame` and `visibleFrame`, and Dockyard uses that measurement directly for its own bars. At `tilesize` 27 on macOS 26 that strip is 47 points; a ratio-based constant would have put the bar 7 points off. The ratios in `DockMetrics` are the fallback for when the Dock is auto-hidden or absent.

`Scripts/calibrate.swift` prints the live values those ratios are checked against.
