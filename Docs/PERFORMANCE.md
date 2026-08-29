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
| Magnification frame rate | every changed frame presented on the next vsync | Cursor swept across the bar at natural speed |
| CPU with the cursor resting on a bar | < 0.5% | Pointer motionless over the bar for 10 s |
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

Tier 2 measured on the same machine with both displays attached, 30 tiles, one of them badged,
Dockyard's bar on the display that does not host the real Dock, taken with `Scripts/benchmark.sh`
at rest:

```
Idle CPU              0.0%
Resident memory       38 MB
Network sockets       0
```

The megabyte over the line above is the Dock's own item list, its observer, and the badge image
cache. The Dock's list is 30 elements read on events; the badge cache holds one image per distinct
string and size, bounded at 64 entries.

Magnification, same machine, 33 seconds of sustained cursor sweeping across a bar on a
60 Hz display, sampled by a temporary display-link probe counting vsyncs, pointer samples
and layout passes:

```
Render rate             p50 59.0 fps, mean 57.5, min 49.0    (60 Hz ceiling)
Frames needing a redraw that missed their vsync   0
Interval between presented frames   p95 17.25 ms, worst 19.52 ms
Display link                        60.0 Hz throughout, no dropped callbacks
panel-layout                        p50 0.17 ms, worst 4.6 ms
CPU, pointer motionless on the bar  0.0%
CPU, pointer away from every bar    0.0%
```

The render rate sits below 60 whenever the pointer holds still for a frame, because a frame
whose geometry is identical to the presented one is skipped rather than recommitted. The
number that matters is the second line: no frame that had something new to show was ever
late. Before magnification was moved onto a display link the same sweep measured a mean of
46.4 fps with 22.9% of vsyncs showing stale geometry.

Hover labels, M1 MacBook Pro, macOS 26.5, release build, 120 Hz built-in display, 31 tiles.
The pointer is swept across the bar by a script at 500 pt/s and never stops, which is harsher
than the natural sweep the magnification budget is quoted against; the number that means
something is the difference between the columns of a single run, not the absolute value,
because run-to-run variance from the rest of the machine is larger than the effect measured:

```
                                        run A     run B
Sweep, label never shown                 7.5%       -
Sweep, label shown once, never updated   7.5%       -
Sweep, label live, window resized       10.1%     12.4%
Sweep, label live, fixed stage           9.1%      9.3%
Pointer resting on a tile, label up      0.1%
Pointer away from every bar              0.1%
Resident memory                          39 MB
```

The same pair measured again later, with the rest of the machine busier, read 13.1% for the
build without the label and 17.1% for the one with it: the absolute numbers move by a third
between runs, the ratio between the two builds does not move much, and both builds sit at
0.0% once the pointer stops. Only measurements taken inside one run, alternating builds, are
worth quoting.

So a live label costs about 1.6 points of CPU on a bar that is being swept continuously, and
nothing at all once the pointer stops. Roughly a point of that was bought back by making the
label's window a fixed-size stage: the first version resized the window on every tile change,
about fifteen times a second during a sweep, and a window resize behind an `NSVisualEffectView`
reallocates a surface and rebuilds a backdrop group. Placement itself is free — a hit test plus
the balloon geometry measures 0.001 ms against a 4 ms frame, and the title is measured once per
tile rather than once per frame (0.016 ms) — which is why the remaining cost is compositing a
translucent window that sits over animating icons, and why a label that never updates costs the
same as one that does.

Reproduce the placement numbers with `DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter labelCost`.

Idle wakeups still need a `powermetrics` run on real hardware; that is a release-checklist
item, not measured yet.

## The rules that produce these numbers

1. **No timers for observation.** Every state change has a push notification. The only permitted timers are user-initiated and short-lived: the reconfiguration settle debounce, the watcher debounces, the auto-hide reveal delay — a cancellable `Task.sleep` started by the pointer arriving at a screen edge and cancelled when it leaves — the App Exposé press-and-hold, and the 120 ms that coalesces a burst of Dock item notifications into one read.
2. **Diff before publishing.** `didActivateApplicationNotification` fires on every app switch, and most switches do not change the rendered output. The store compares tiles and appearance and publishes nothing when they match. This single decision is responsible for most of the idle CPU budget.
3. **Diff before rendering.** A panel receiving a snapshot mutates only the layers that changed. Stable `DockTileID` identity is what makes that possible: a tile that moves keeps its layer and is repositioned instead of being rebuilt.
4. **Rasterize once.** Icons become a `CGImage` at `largesize × maximum backing scale` one time and are cached. Magnification is then a GPU transform on that image. No `NSImage.draw` exists in any hot path. The maximum is taken across all attached displays so a tile does not need re-rasterizing when a panel moves between a Retina and non-Retina screen.
5. **Layer-backed, never view-drawn.** There is no `NSView.draw(_:)` override anywhere in the tile rendering path.
6. **Implicit animations disabled everywhere.** Every layout pass runs inside `CATransaction` with actions disabled. Without that, each position assignment schedules a quarter-second implicit animation and the compositor never goes idle.
7. **Magnification is driven by a display link, not by mouse events.** `mouseMoved` only starts the link; each vsync samples the pointer with `NSEvent.mouseLocation` and lays out once. Tying frame production to event delivery instead means a vsync that receives no event shows stale geometry and a vsync that receives two throws one away, which measured as 46 fps and a visible beat on a 60 Hz display. The magnification ramp is advanced per frame from the frame delta rather than handed to Core Animation, so a moving cursor never restarts an in-flight animation and there is no discontinuity when the ramp ends.
8. **Nothing is recommitted unchanged.** The link skips the layout pass when neither the pointer position nor the ramp has moved since the last presented frame, and invalidates itself once that has held for twelve frames. A pointer parked on a bar therefore costs nothing; `mouseMoved` and `mouseExited` restart the link.
9. **Controller pooling.** A disappearing display's controller is retained for two minutes rather than deallocated, so closing and reopening a lid reuses a warm layer tree.
10. **Lazy settings.** The SwiftUI settings window and its dependencies are not instantiated until the user opens it. SwiftUI's first-use cost should not be paid by users who never open the window.
11. **Value types in the snapshot.** Nothing reference-counted crosses the actor boundary, so there is no retain and release traffic on the main thread and the snapshot is free to copy.
12. **The hover label's window is moved, never resized.** It is a fixed-size stage as wide as the longest title the app will draw, with the balloon centred inside it, so a name change costs a view frame and a path instead of a window resize. The pointer's own tracking is the display link that magnification already runs; the label is presented from the same per-vsync hit test and inherits the rule above, so a resting pointer with a label on screen still costs nothing.
13. **Full-screen detection is one window-list query per space switch.** `CGWindowListCopyWindowInfo` is asked for on-screen window bounds when the active space changes and once more after a 350 ms settle, and the answer is compared before anything is acted on. Nothing watches windows continuously, and nothing samples the screen: a switch that changes no coverage costs the query and stops there.
14. **The auto-hide trigger is a window, not a mouse monitor.** A hidden bar is watched by a one-point panel along its display's edge whose tracking area pushes an enter and an exit. A global `NSEvent` monitor would see every mouse move on the machine for the whole session to answer a question the window server can answer for free. Idle cost is zero: a tracking area is push-based, and the panel draws one nearly transparent row. Its resident cost has not been measured separately and is charged against the 60 MB budget as one extra empty window per hidden bar.
15. **A launch bounce is one animation and two window resizes.** The bounce is an additive keyframe animation handed to Core Animation once and left to the compositor; nothing is recommitted per frame and no timer advances it. The panel grows to hold the icon at its peak when the launch starts and shrinks when it ends, so a launch costs two window resizes rather than one per frame, and an application that is not launching costs nothing at all. The tracking of which application is launching is two `NSWorkspace` notifications and a set comparison, with no snapshot rebuild behind it: a launch that concerns no rendered tile stops at the comparison.
16. **Bounded caches.** The icon cache is an `NSCache` with an explicit `totalCostLimit` in bytes, so memory pressure evicts icons, which are cheap to regenerate, rather than the process growing.
17. **A stack costs nothing until it is opened and nothing after it closes.** The folder is read once per opening, inside a detached task so the main thread never waits on the filesystem, and the panel and its view are built when that read returns and released when it closes. Nothing watches the folder, and the entry icons are charged to the icon cache's existing cost limit rather than to a cache of their own. The read is capped at 200 entries and the layout at what the display can hold, so a folder with ten thousand files costs a bounded listing and a bounded panel.
18. **Spring loading is one cancellable sleep per drag, not a tracker.** `draggingUpdated` already arrives from the drag session; the only addition is a `Task.sleep` that is started when the pointer settles on a tile and cancelled when it leaves, the drag ends, or the target changes. Nothing exists between drags.
19. **Window clearing evaluates once per gesture, never per notification.** AX move and resize notifications arrive dozens of times a second during a drag. The reserver records which process they came from, waits 150 ms, and extends that wait for as long as a mouse button is held, so one evaluation runs after the gesture instead of one per event. Reading and writing frames happens on an actor off the main thread with a 0.5 s messaging timeout. Idle cost is zero because nothing polls and no window moves at rest; the whole feature is inert until it is turned on, and its second `AXObserver` per application is registered only then.
20. **Accessibility proxies are built when an assistive client asks, and not before.** With VoiceOver off the feature is one boolean tested inside the layout pass that already runs, and no proxy objects exist. With it on there is one small element per tile, whose frame is refreshed by the same layout pass rather than by a mechanism of its own.
21. **The Dock's own item list is read on events, never on a clock.** One walk of about thirty elements happens on an actor off the main thread, coalesced 120 ms behind the Dock's item-created and item-destroyed notifications and behind the application and preference events the app already handles, with one read in flight at a time and the result compared before it is published. The Dock's tree supports no notification for a badge change — `kAXValueChanged` returns `kAXErrorNotificationUnsupported` on the Dock's application element and on each item — so a badge is prompt rather than instant, which is the price of not adding a timer. Badges rasterize once per string at a size derived from `largesize`, so magnification stays a GPU transform.
22. **Local reordering is a map lookup in the snapshot build, and its drag rides the existing display link.** The override is a stable sort keyed on persistence keys, run once per rebuild; with the setting off it is one `isEmpty` check. While a tile is being dragged the pointer is sampled by the same link magnification uses, and the tiles that slide out of the way are advanced by a per-frame decay rather than by an implicit animation, so a drag costs the layout pass that was already running and the link stops itself once the last residual is under half a point.
23. **Localization is a bundle lookup, not a runtime cost.** Strings resolve through `NSLocalizedString` against each module's own bundle at the point of use, and the point of use is a menu being built or a settings window being opened. Nothing on the render path reads a string table.

## Measuring

```bash
Scripts/benchmark.sh
```

Prints resident memory, CPU, an explicit pass or fail on open network sockets, and, with `sudo`, a `powermetrics` task sample over 60 seconds. Override the window with `DURATION=120 Scripts/benchmark.sh`.

Minimized-window tiles add no steady-state cost: sampling only the seconds where the pointer is clear of every bar, idle CPU is 0.001% with and without the feature and resident memory is 42 MB in both. `DockGeometry.layout` is 0.003 ms at 24 tiles and 0.003 ms at 32, against a 4 ms frame budget; reproduce with `DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter layoutCost`. The trap is on the observation side rather than the render side, and is written up in `Docs/ARCHITECTURE.md`: registering `kAXWindowCreated` costs 23 pointless Accessibility reads a minute against a single Electron app, and re-reading every application on every workspace notification costs about eighteen per app switch.

`os_signpost` intervals are compiled into release builds, because signposts are effectively free when nothing is recording and they let a user produce a usable trace from a bug report. The instrumented intervals are `cold-start`, `preference-read`, `snapshot-build`, `panel-layout`, and `icon-rasterize`, all under the subsystem `com.dockyard.app` and category `performance`.

See `Instruments/README.md` for the recording configurations.

## Why CI does not measure this

GitHub Actions macOS runners are headless. `NSScreen.screens` there is not representative of a real display arrangement and magnification cannot be measured at all. CI therefore covers correctness — unit tests, geometry, plist decoding, the forbidden-API lint — and performance is a manual pre-release checklist on real hardware with the results recorded in the release notes. That is stated plainly rather than papered over with an automated check that would prove nothing.
