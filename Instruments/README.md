# Instruments configurations

Instruments trace templates are binary Xcode documents and are deliberately not committed here; a template that drifts out of date is worse than instructions that do not. Each configuration below takes under a minute to build in Instruments and can be saved locally with `File > Save As Template`.

Dockyard emits `os_signpost` intervals in release builds under subsystem `com.dockyard.app`, category `performance`. Add the **os_signpost** instrument to every configuration and set its subsystem filter to that value. The intervals are:

| Interval | Covers |
|---|---|
| `cold-start` | `applicationDidFinishLaunching` end to end |
| `preference-read` | One `CFPreferences` domain read and decode |
| `snapshot-build` | Ordering plus the diff decision |
| `panel-layout` | One panel's geometry pass and layer application |
| `icon-rasterize` | One icon resolved and rasterized to a `CGImage` |

## Idle

Purpose: prove the process does nothing at rest.

Instruments: **Time Profiler**, **os_signpost**, **Energy Log**.

Method: attach to the running `Dockyard` process, move the cursor away from every bar, record 10 minutes without touching the machine. Expect a flat Time Profiler with no periodic samples, no signpost intervals after start-up, and energy impact at zero. Any repeating pattern means something is polling.

## Magnification

Purpose: verify frame time during a sweep.

Instruments: **Core Animation FPS**, **Time Profiler**, **os_signpost**.

Method: enable Dock magnification in System Settings, record while sweeping the cursor across a bar at natural speed for about 10 seconds. Expect `panel-layout` intervals under 4 ms on Apple silicon and no dropped frames. `panel-layout` durations that grow with tile count point at a layout regression; a rising Time Profiler cost inside image decoding means an icon is being re-rasterized per frame instead of cached.

Magnification is driven by a display link, so exactly one `panel-layout` interval per vsync is the healthy shape while the cursor moves, and none at all while it holds still. Two intervals inside one refresh period means something outside the link is forcing a layout. A gap longer than one refresh period while the cursor is still moving means the main thread missed a display-link callback, which is the only way this design can drop a frame.

## Memory

Purpose: catch leaks across display and preference churn.

Instruments: **Allocations**, **Leaks**, **VM Tracker**.

Method: record while cycling a display connect and disconnect five times, changing `tilesize` several times, and launching and quitting a handful of apps. Expect resident memory to return to its baseline after each cycle. Controllers are pooled for two minutes after a display disappears, so allow for that delay before concluding anything about growth. The icon cache is an `NSCache` with a byte cost limit, so it is expected to grow to that ceiling and then hold.
