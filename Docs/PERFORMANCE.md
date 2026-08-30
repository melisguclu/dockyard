# Performance

Performance is a correctness requirement here, not an optimisation. An always-running agent that costs measurable battery on a laptop gets uninstalled regardless of how good it looks.

## How this is measured

Every number below comes from `Scripts/`, on real hardware, from a release build. None of it needs `sudo`, so anyone with the repository can reproduce it.

**CPU, wakeups, memory and energy come from `proc_pid_rusage`, not from `ps` or `top`.** `ps` reports a decayed average with one-second resolution, which cannot distinguish 0.5% from 0.0% and cannot see a process that uses 200 microseconds in two minutes. `proc_pid_rusage` with `RUSAGE_INFO_V6` returns the exact nanoseconds of user and system time the kernel charged the process, the exact number of wakeups it caused, the cycles and instructions it retired, and the energy attributed to it. Sampling it at both ends of a window and dividing gives a real number rather than an estimate. `Scripts/measure.swift` does that.

**Memory is the physical footprint, not the resident size.** `ri_phys_footprint` is what Activity Monitor shows in its Memory column and what the kernel charges against the process under pressure. Resident size counts shared framework pages that every AppKit process maps and would be charged to Dockyard whether it existed or not; for this app it reads about 40 MB against a footprint of 18 MB. Earlier revisions of this document quoted resident size and so overstated Dockyard's memory by more than double. The budget below is a footprint budget.

**Idle wakeups no longer need `powermetrics`.** `ri_pkg_idle_wkups` is the same counter Activity Monitor calls Idle Wake Ups, and it is readable without privileges. The previous revision of this document listed idle wakeups as a budget that had never been measured because it was waiting on a `sudo powermetrics` run; it is measured now, on every `Scripts/benchmark.sh` invocation.

**Frame data comes from the `os_signpost` intervals that are compiled into release builds**, recorded with `xctrace` and summarised by `Scripts/frame-stats.py`. Nothing temporary is added to the app to measure it. `Scripts/frame-trace.sh` records a trace while `Scripts/sweep-cursor.swift` drives the pointer across the bar at a fixed speed, which removes the largest source of run-to-run variance in the old numbers: a human hand.

**Latency is measured end to end, from the outside.** `Scripts/latency.swift` writes a Dock preference or launches an application and then polls the bar's own window frame through `CGWindowListCopyWindowInfo` until it changes. It measures what a user sees, not what the app believes it did.

### The machine

MacBook Pro (Mac14,7), Apple M2, 16 GB, macOS 26.5.2 (25F84). Built-in Retina display at 1440 × 900 and a Studio Display at 2560 × 1440, both 60 Hz. The Studio Display is the main display and hosts the real Dock, so Dockyard draws one bar, on the built-in display. `tilesize` 31, `largesize` 51, magnification on. Twenty-five tiles: nineteen pinned applications, Finder, a running application that is not pinned, the separator, the Downloads stack, one minimized window, and the Trash. Accessibility is granted, so the Dock's own item list, badges and minimized-window tiles are all live.

## Budgets

| Metric | Budget | Measured | Measurement condition |
|---|---|---|---|
| CPU at rest | < 0.1% of one core | **0.0002%** | Pointer off every bar, 120 s |
| Idle wakeups | < 2 per second | **0** | Same window, zero wakeups in 120 s |
| Memory footprint | < 60 MB | **18.4 MB** | Same |
| CPU with the pointer resting on a bar | < 0.5% | **0.0020%** | Pointer motionless over a tile, 60 s |
| CPU during magnification | < 8% of one core | **0.58%** | Pointer swept across the bar at 500 pt/s for 30 s |
| Layout pass during magnification | < 4 ms | **p50 0.23 ms, worst 2.29 ms** | Same, from `panel-layout` |
| Magnification frame rate | every changed frame on the next vsync | **59.8 /s on a 60 Hz display** | Same |
| Cold start to first paint | < 200 ms | **117 ms** | `cold-start` signpost |
| Preference change to visible update | < 150 ms p95 | **p50 23 ms, p95 49 ms** | `defaults write` on the Dock domain, 10 repeats |
| Quit to the tile leaving | < 100 ms p95 | **p50 96 ms, p95 128 ms** | 10 repeats |
| Network connections | exactly zero | **zero, and no networking symbol linked** | `lsof`, `nm -u` |

Every budget is met except the last latency line, which is over at p95 and is discussed below.

## At rest

Two minutes with the pointer parked on the display that has no bar, nothing launching, nothing changing:

```
CPU, share of one core      0.0002 %      (0.2 ms of CPU in 120 s)
Idle wakeups                0             (none at all in the window)
Interrupt wakeups           0.025 /s
Cycles per second           136,000
Instructions per second     97,000
Energy attributed           0.00 mW
Memory footprint            18.4 MB
Peak footprint, lifetime    18.8 MB
Threads                     3
Disk read / written         0 / 0
Page-ins                    0
```

Zero idle wakeups over two minutes is the number that matters on a laptop, and it is the direct consequence of there being no timer anywhere in the observation path. Ninety-seven thousand instructions per second is roughly what a process that is asleep costs to keep alive.

With the pointer resting motionless on a tile, magnified, for sixty seconds:

```
CPU, share of one core      0.0020 %      (1.2 ms of CPU in 60 s)
Idle wakeups                0
Memory footprint            18.2 MB
Threads                     3
```

The display link stops itself twelve frames after the geometry stops changing, so a parked pointer costs the same as no pointer. The 1.2 ms is those twelve frames plus the tracking area.

## Magnification

Thirty seconds with the pointer swept back and forth across 714 points of bar at 500 pt/s, which is faster than a natural sweep and never stops. Frame figures come from the `panel-layout` signpost; the CPU figures come from a second run of the same sweep with no tracer attached, because a tracer of its own costs CPU.

```
panel-layout                1789 intervals over 29.93 s, 59.8 per second
  duration                  p50 0.234 ms   p95 0.405   p99 0.951   worst 2.290
  interval                  p50 16.67 ms   p95 18.43   p99 19.64   worst 47.17
  pacing                    8 intervals over 1.5 refresh periods
                            10 missed vsyncs, 0.56% of the display's frames

CPU, share of one core      0.58 %        (174 ms of CPU in 30 s)
Energy attributed           76 mW average
Idle wakeups                0.83 /s
Memory footprint            18.7 MB, peak 18.8 MB
```

59.8 layout passes per second on a 60 Hz display is one pass per vsync, and the median interval between them is 16.67 ms, exactly one refresh period. No pass came close to the 4 ms frame budget; the worst was 2.29 ms. Ten vsyncs out of about 1,800 were missed over thirty seconds of continuous motion.

**This used to be twice as expensive, and the fix is worth recording.** Until this measurement the same sweep produced 114.5 layout passes per second, two per vsync, with intervals alternating between 1.8 ms and 18 ms. The display link ran one pass, and then AppKit's window display cycle ran `layout()` on the content view and it ran the whole pass again, repeating work that was already on screen. `DockContentView.layout()` now records the bounds it last laid out for and returns without relaying out when they have not changed, which is the only reason `layout()` needs to run at all; the display link owns everything else. The pass got cheaper per frame as well, because half of the old passes were re-doing warm work: 2 × 0.148 ms became 1 × 0.234 ms.

The Instruments notes have said for some time that "exactly one `panel-layout` interval per vsync is the healthy shape" and that "two intervals inside one refresh period means something outside the link is forcing a layout". That was written as a diagnostic rule and it was never checked against a recording. It is checked now, and `Scripts/frame-stats.py` prints the pacing line so a regression shows up as a number rather than as a feeling.

### What the hover label costs

Earlier revisions of this document reported that a live hover label cost "about 1.6 points of CPU on a bar that is being swept continuously", from figures between 7.5% and 17.1% that moved by a third between runs. Those numbers were taken with `ps`, on a machine doing other work, and they measured the sampling method more than they measured the label. They are withdrawn.

The whole magnification path, hover label included, costs 0.58% of one core during a continuous sweep and 0.0020% once the pointer stops. The label is inside that. Its placement cost is separately measurable and is essentially zero: a hit test plus the balloon geometry is 0.0000 ms at p50 and 0.0011 ms at p99 against a 4 ms frame, and the title is measured once per tile rather than once per frame, at 0.016 ms. Reproduce with `DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter labelCost`.

The design rule that came out of the original investigation still holds and is still worth keeping: the label's window is a fixed-size stage that is moved rather than resized, because a window resize behind a translucent effect view reallocates a surface and rebuilds a backdrop group. That is rule 12 below.

## Start-up

From a trace of a launch, so the numbers carry a tracer's overhead and are an upper bound:

```
cold-start                  116.9 ms      (budget 200 ms)
first preference-read       1.3 ms
first snapshot-build        5.4 ms
icon-rasterize              24 intervals, 162.9 ms in total, p50 4.0 ms each
```

Rasterizing the icons is the largest single cost of starting up, and it is the one thing that is not on the main thread: `IconProvider` is an actor and the bar paints before the icons arrive. Twenty-four rasterizations at 4 ms each is 163 ms of work that would be visible as a stall if it were done inline.

## Latency

Ten repeats each, measured from the outside by polling the bar's window frame.

```
Dock preference write to a resized bar        p50 23 ms   p95 49 ms
Application asked to launch to its tile        p50 212 ms  p95 290 ms
  of which the tile was on screen before
  the application had finished launching, by   p50 59 ms   p95 78 ms
Application gone to its tile leaving           p50 96 ms   p95 128 ms
```

The launch figure needs reading carefully. Two hundred milliseconds is mostly LaunchServices and the application itself; Dockyard's own contribution is bounded above by the fact that the tile is already bouncing on screen a median of 59 ms **before** the application finishes launching. Dockyard reacts to the launch starting, not to the launch finishing, exactly as the real Dock does. A budget of "100 ms from launch to indicator" was never the right shape for that path and has been restated above as the quit path, which is the one where Dockyard is genuinely the slow party.

Quitting is over budget at p95: 128 ms against 100 ms, with a median of 96 ms that is only just inside it. The termination notification arrives immediately and the snapshot rebuild is a few milliseconds, so the time is spent between the rebuild and the window server showing a narrower bar. This is recorded rather than fixed.

One measurement artefact is worth writing down because it cost an hour. Launching an application *hidden and in the background*, which is what `open -gj` does, produces no bounce and no early tile, and the tile then appears only at the next rebuild, 750 to 900 ms later. That is a real behaviour, but it is not the path a user takes, and quoting it as "launch latency" would have been wrong. `Scripts/latency.swift` launches in the foreground for that reason.

## Scaling and leaks

Layout cost against tile count, release build, 20,000 passes each:

```
24 tiles                    p50 0.0030 ms   p99 0.0041 ms
32 tiles                    p50 0.0031 ms   p99 0.0041 ms
64 tiles                    p50 0.0060 ms   p99 0.0091 ms
```

Reproduce with `DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter layoutCost`. Doubling the tiles from 32 to 64 doubles the cost, which is the expected linear shape, and 64 tiles still costs 0.15% of a 4 ms frame.

After a session containing ten `tilesize` changes, ten application launch and quit cycles, and several thirty-second magnification sweeps, the footprint was 18.5 MB against an 18.4 MB baseline, with a lifetime peak of 18.9 MB. Nothing accumulated.

## Static

```
Open network sockets        0
Networking symbols linked   0             (nm -u, no URLSession, CFNetwork, NWConnection, CFSocket, getaddrinfo)
Application bundle          3.2 MB
arm64 binary                2.2 MB
Swift source                11,692 lines
```

The linked-symbol check is stronger than the socket check: a process with no sockets open right now might open one later, but a binary that never links a networking symbol cannot. `Scripts/benchmark.sh` runs both and prints an explicit pass or fail, and `Scripts/lint-forbidden-apis.sh` fails the build if the source ever names one.

## The rules that produce these numbers

1. **No timers for observation.** Every state change has a push notification. The only permitted timers are user-initiated and short-lived: the reconfiguration settle debounce, the watcher debounces, the auto-hide reveal delay — a cancellable `Task.sleep` started by the pointer arriving at a screen edge and cancelled when it leaves — the App Exposé press-and-hold, and the 120 ms that coalesces a burst of Dock item notifications into one read.
2. **Diff before publishing.** `didActivateApplicationNotification` fires on every app switch, and most switches do not change the rendered output. The store compares tiles and appearance and publishes nothing when they match. This single decision is responsible for most of the idle CPU budget.
3. **Diff before rendering.** A panel receiving a snapshot mutates only the layers that changed. Stable `DockTileID` identity is what makes that possible: a tile that moves keeps its layer and is repositioned instead of being rebuilt.
4. **Rasterize once.** Icons become a `CGImage` at `largesize × maximum backing scale` one time and are cached. Magnification is then a GPU transform on that image. No `NSImage.draw` exists in any hot path. The maximum is taken across all attached displays so a tile does not need re-rasterizing when a panel moves between a Retina and non-Retina screen.
5. **Layer-backed, never view-drawn.** There is no `NSView.draw(_:)` override anywhere in the tile rendering path.
6. **Implicit animations disabled everywhere.** Every layout pass runs inside `CATransaction` with actions disabled. Without that, each position assignment schedules a quarter-second implicit animation and the compositor never goes idle.
7. **Magnification is driven by a display link, not by mouse events.** `mouseMoved` only starts the link; each vsync samples the pointer with `NSEvent.mouseLocation` and lays out once. Tying frame production to event delivery instead means a vsync that receives no event shows stale geometry and a vsync that receives two throws one away, which measured as 46 fps and a visible beat on a 60 Hz display. The magnification ramp is advanced per frame from the frame delta rather than handed to Core Animation, so a moving cursor never restarts an in-flight animation and there is no discontinuity when the ramp ends.
8. **Nothing is recommitted unchanged, and AppKit's layout pass is not a second chance to lay out.** The link skips the layout pass when neither the pointer position nor the ramp has moved since the last presented frame, and invalidates itself once that has held for twelve frames. A pointer parked on a bar therefore costs nothing; `mouseMoved` and `mouseExited` restart the link. `layout()` is called by AppKit's own window display cycle once per frame whether or not anything moved, so it records the bounds it last laid out for and does nothing when they are unchanged. Without that guard the display link's work is done twice per vsync, which is what this document measured before the guard existed.
9. **Controller pooling.** A disappearing display's controller is retained for two minutes rather than deallocated, so closing and reopening a lid reuses a warm layer tree.
10. **Lazy settings.** The SwiftUI settings window and its dependencies are not instantiated until the user opens it. SwiftUI's first-use cost should not be paid by users who never open the window.
11. **Value types in the snapshot.** Nothing reference-counted crosses the actor boundary, so there is no retain and release traffic on the main thread and the snapshot is free to copy.
12. **The hover label's window is moved, never resized.** It is a fixed-size stage as wide as the longest title the app will draw, with the balloon centred inside it, so a name change costs a view frame and a path instead of a window resize. The pointer's own tracking is the display link that magnification already runs; the label is presented from the same per-vsync hit test and inherits the rule above, so a resting pointer with a label on screen still costs nothing.
13. **Full-screen detection is one window-list query per space switch.** `CGWindowListCopyWindowInfo` is asked for on-screen window bounds when the active space changes and once more after a 350 ms settle, and the answer is compared before anything is acted on. Nothing watches windows continuously, and nothing samples the screen: a switch that changes no coverage costs the query and stops there.
14. **The auto-hide trigger is a window, not a mouse monitor.** A hidden bar is watched by a one-point panel along its display's edge whose tracking area pushes an enter and an exit. A global `NSEvent` monitor would see every mouse move on the machine for the whole session to answer a question the window server can answer for free. Idle cost is zero: a tracking area is push-based, and the panel draws one nearly transparent row. Its resident cost has not been measured separately and is charged against the memory budget as one extra empty window per hidden bar.
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

Prints the build under test, an explicit pass or fail on open sockets and on networking symbols in the binary, and then a full `proc_pid_rusage` window: CPU as a share of one core, cycles and instructions, idle and interrupt wakeups, attributed energy, footprint, lifetime peak, footprint drift, threads, disk I/O and page-ins. Sixty seconds by default; `DURATION=120 LABEL="idle" Scripts/benchmark.sh` to change it.

```bash
Scripts/frame-trace.sh
```

Records an `xctrace` trace while driving the pointer across the bar for thirty seconds, then prints per-interval duration and pacing percentiles for every signpost the app emits. It takes over the pointer for the duration. `DURATION=10 SPEED=300 Scripts/frame-trace.sh` to change the sweep, `OUT=/some/dir` to keep the trace.

```bash
swift Scripts/latency.swift 10
```

Writes `com.apple.dock tilesize`, waits for the bar to resize, and restores the original value; then launches and quits TextEdit and times the tile appearing and leaving. It changes a real Dock preference and puts it back.

```bash
DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter layoutCost
DOCKYARD_BENCH=1 swift test --package-path Packages/DockKit -c release --filter labelCost
```

Pure geometry, no window server, so these two are the only performance numbers here that CI could run.

`os_signpost` intervals are compiled into release builds, because signposts are effectively free when nothing is recording and they let a user produce a usable trace from a bug report. The instrumented intervals are `cold-start`, `preference-read`, `snapshot-build`, `panel-layout`, `icon-rasterize`, and `stack-read`, all under the subsystem `com.dockyard.app` and category `performance`.

See `Instruments/README.md` for recording the same data in the Instruments GUI.

## Why CI does not measure this

GitHub Actions macOS runners are headless. `NSScreen.screens` there is not representative of a real display arrangement, magnification cannot be measured at all, and there is no window server to ask for a bar's frame. CI therefore covers correctness — unit tests, geometry, plist decoding, the forbidden-API lint — plus the two pure-geometry benchmarks above, and everything else is a manual pre-release step on real hardware with the results recorded in the release notes. That is stated plainly rather than papered over with an automated check that would prove nothing.
