# Performance

Performance is a correctness requirement here, not an optimisation. An always-running agent that costs measurable battery on a laptop gets uninstalled regardless of how good it looks.

## Budgets

| Metric | Budget | Measurement condition |
|---|---|---|
| Idle CPU | < 0.1% average over 60 s | 2 displays, 25 tiles, cursor outside every bar, no launches |
| Idle wakeups | < 2 per second | Same, via `powermetrics --samplers tasks` |
| Resident memory | < 60 MB | Same, after an hour of uptime |
| Peak CPU during magnification | < 8% of one core | Cursor swept across the bar at natural speed |
| Frame time during magnification | < 4 ms | Instruments Core Animation, Apple silicon, 120 Hz |
| Preference change to visible update | < 150 ms p95 | `defaults write` on the Dock domain, or the System Settings slider |
| Launch or quit to indicator update | < 100 ms p95 | |
| Display reconfiguration to repositioned bars | < 700 ms | Includes the 350 ms settle debounce |
| Cold start to first paint | < 200 ms | `os_signpost` interval `cold-start` |
| Network connections | exactly zero | `lsof -nP -a -p <pid> -i` |

## Measured

M1 MacBook Pro, macOS 26.5, built-in display plus Studio Display, 20 tiles, `tilesize` 27, one panel active because the external display hosts the real Dock:

```
Idle CPU              0.0%   (two 20 s samples)
Resident memory       37 MB
Network sockets       0
```

Idle wakeups and magnification frame time still need a `powermetrics` and Instruments run on real hardware; they are release-checklist items, not measured yet.

## The rules that produce these numbers

1. **No timers for observation.** Every state change has a push notification. The only permitted timers are user-initiated and short-lived: the reconfiguration settle debounce, the watcher debounces, and the magnification exit animation.
2. **Diff before publishing.** `didActivateApplicationNotification` fires on every app switch, and most switches do not change the rendered output. The store compares tiles and appearance and publishes nothing when they match. This single decision is responsible for most of the idle CPU budget.
3. **Diff before rendering.** A panel receiving a snapshot mutates only the layers that changed. Stable `DockTileID` identity is what makes that possible: a tile that moves keeps its layer and animates to a new position instead of being rebuilt.
4. **Rasterize once.** Icons become a `CGImage` at `largesize × maximum backing scale` one time and are cached. Magnification is then a GPU transform on that image. No `NSImage.draw` exists in any hot path. The maximum is taken across all attached displays so a tile does not need re-rasterizing when a panel moves between a Retina and non-Retina screen.
5. **Layer-backed, never view-drawn.** There is no `NSView.draw(_:)` override anywhere in the tile rendering path.
6. **Implicit animations disabled in hot paths.** Every layout pass runs inside `CATransaction` with actions disabled. Without that, each position assignment schedules a quarter-second implicit animation and the compositor never goes idle.
7. **Controller pooling.** A disappearing display's controller is retained for two minutes rather than deallocated, so closing and reopening a lid reuses a warm layer tree.
8. **Lazy settings.** The SwiftUI settings window and its dependencies are not instantiated until the user opens it. SwiftUI's first-use cost should not be paid by users who never open the window.
9. **Value types in the snapshot.** Nothing reference-counted crosses the actor boundary, so there is no retain and release traffic on the main thread and the snapshot is free to copy.
10. **Bounded caches.** The icon cache is an `NSCache` with an explicit `totalCostLimit` in bytes, so memory pressure evicts icons, which are cheap to regenerate, rather than the process growing.

## Measuring

```bash
Scripts/benchmark.sh
```

Prints resident memory, CPU, an explicit pass or fail on open network sockets, and, with `sudo`, a `powermetrics` task sample over 60 seconds. Override the window with `DURATION=120 Scripts/benchmark.sh`.

`os_signpost` intervals are compiled into release builds, because signposts are effectively free when nothing is recording and they let a user produce a usable trace from a bug report. The instrumented intervals are `cold-start`, `preference-read`, `snapshot-build`, `panel-layout`, and `icon-rasterize`, all under the subsystem `com.dockyard.app` and category `performance`.

See `Instruments/README.md` for the recording configurations.

## Why CI does not measure this

GitHub Actions macOS runners are headless. `NSScreen.screens` there is not representative of a real display arrangement and magnification cannot be measured at all. CI therefore covers correctness — unit tests, geometry, plist decoding, the forbidden-API lint — and performance is a manual pre-release checklist on real hardware with the results recorded in the release notes. That is stated plainly rather than papered over with an automated check that would prove nothing.
