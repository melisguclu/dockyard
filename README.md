# Dockyard

A native macOS menu bar agent that renders a faithful, interactive copy of the system Dock on **every** connected display, simultaneously and permanently. It mirrors the real Dock. It never modifies it.

![License](https://img.shields.io/badge/license-MIT-blue) ![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## Why

macOS renders the Dock on exactly one display at a time. On a multi-display setup the Dock either stays pinned to the primary display or migrates to whichever display the cursor last pushed against the bottom edge. There is no System Settings toggle and no public or private API to change this.

Dockyard does not try to move the real Dock. It reads the Dock's own configuration and draws an additional bar on the displays that do not have one, so a MacBook connected to an external display has a dock at the bottom of both screens, always.

## Install

Build from source until the first signed release is published:

```bash
git clone https://github.com/<owner>/dockyard.git
cd dockyard
Scripts/make-app.sh release
cp -R build/Dockyard.app /Applications/
open /Applications/Dockyard.app
```

Dockyard is a menu bar agent with no Dock icon of its own. Its status item offers Settings, Refresh, Launch at Login, and Quit.

## Features

- A dock-like bar at the bottom of every connected display, at the same time
- Mirrors pinned apps, pinned folders and stacks, recents, and running applications live
- Permanent Finder and Trash tiles and the separator before the Trash region, like the real Dock
- The Trash's own empty and full artwork, and Calendar showing today's weekday and date
- Running indicators, hidden-app dimming, and the Trash tile with its empty and full states
- Click to launch or activate, right-click for Show in Finder / Hide / Quit / Force Quit
- Drag files onto an app tile to open them with that app
- Dock magnification, using the system's own `tilesize` and `largesize`
- Reads `tilesize`, `largesize`, `magnification`, `orientation`, `show-process-indicators`, and `show-recents` from the system, so it changes when the Dock changes
- Suppresses its own bar on the display currently hosting the real Dock (configurable)
- Per-display enable and disable, remembered across disconnects by display hardware identity, not by the volatile `CGDirectDisplayID`
- Handles display connect, disconnect, resolution change, rearrangement, sleep, and wake
- Launch at login via `SMAppService`

## Performance

Dockyard is event-driven. There is no polling anywhere in the observation path: preference changes arrive through a distributed notification with a filesystem watcher as a backstop, application state through `NSWorkspace` notifications, and display changes through `CGDisplayRegisterReconfigurationCallback`. Snapshots are diffed before they are published and again before they are rendered, so the frequent notifications that do not change the rendered output cost nothing.

Measured on an M1 MacBook Pro with a Studio Display, macOS 26.5, 20 tiles, `tilesize` 27:

```
Idle CPU              0.0%
Resident memory       37 MB
Network connections   0
Panels                1 (external display hosts the real Dock, so it is suppressed there)
```

Reproduce with `Scripts/benchmark.sh` while Dockyard is running. Idle-wakeup and frame-time numbers require `sudo powermetrics` and Instruments on real hardware; see `Docs/PERFORMANCE.md`.

## Privacy and security

- **No network code.** No `URLSession`, no sockets, no telemetry, no crash reporting, no update ping. CI greps for the whole class of APIs and fails the build on any hit.
- **No permission prompts** in the default configuration. No Accessibility, no Screen Recording, no Full Disk Access, no helper tool, no root.
- **No subprocesses and no AppleScript.** Dockyard never spawns a process, never calls `killall`, and never sends an Apple Event.
- **Never writes to `com.apple.dock`** and never restarts the Dock. The only state it persists is its own preferences.
- **Hardened Runtime** with an entitlements file that grants nothing. Verify a build yourself:

```bash
codesign -d --entitlements :- /Applications/Dockyard.app
codesign -dvvv --verbose=4 /Applications/Dockyard.app
spctl -a -vvv /Applications/Dockyard.app
lsof -nP -a -p "$(pgrep -x Dockyard)" -i
```

The Dock preference domain is treated as untrusted input: every entry is validated, and a tile is only launchable if it resolves to an existing `.app` bundle with a real executable. See `Docs/SECURITY-MODEL.md`.

## Limitations

These are real and are not going away:

- **Dockyard renders a copy, not an extension.** No public or private API extends the real Dock to a second display. Fidelity work closes the gap; it does not eliminate it.
- **It cannot be sandboxed,** because reading another application's preference domain and resolving icons at arbitrary paths are both sandbox-blocked. It is therefore not on the Mac App Store.
- **Minimize animations do not fly into Dockyard's bars.** The genie effect targets the system Dock's own window.
- **Minimized windows are not listed.** The real Dock gives each minimized window its own tile when `minimize-to-application` is off. Those come from the window server and need Accessibility to enumerate, which is deliberately not requested.
- **Clock does not tick.** The Dock draws Calendar and Clock through each app's dock tile plugin, loaded inside the Dock process. Dockyard will not load third-party code, so it draws Calendar's date itself and leaves Clock as its static bundle icon; a live second hand would need a timer, which the project bans.
- **The Trash tile updates on app activation, not instantly.** `~/.Trash` needs Full Disk Access to watch, which Dockyard does not request. Its entry count is readable without any permission, so the state is recomputed whenever the snapshot rebuilds, which in practice means as soon as Finder comes forward.
- **Clicking a running app brings its existing windows forward wherever they already are,** which may be a different display from the bar you clicked. This is exactly what the real Dock does; moving windows between displays is a window-manager feature and an explicit non-goal.
- **Drag-to-reorder does not persist,** because that would mean writing `com.apple.dock` and restarting the Dock.
- **Reading `com.apple.dock` is not a documented contract.** Apple can change the format. The decoder is defensive and fixture-tested, and `com.apple.dock.prefchanged` has a filesystem-watcher fallback underneath it.
- **Auto-hide and left/right orientation** are read and modelled, but the auto-hide reveal behaviour is not implemented in v1.
- **Mirrored displays** get one bar, on the mirror-set primary, not one per mirrored display.

`Docs/EMPIRICAL-FINDINGS.md` records what has actually been verified on hardware, including two places where macOS 26 behaves differently from earlier releases.

## How it works

One source of truth, N render targets. `DockStateStore` publishes an immutable `DockSnapshot`; each display's panel subscribes to it and applies a diff. Panels never talk to each other, which is what makes "every bar shows the same state" and "one bar cannot break another" fall out of the design instead of needing coordination logic.

See `Docs/ARCHITECTURE.md`.

## Build from source

Requirements: macOS 14 or later, Xcode 16 or later (Swift 6).

```bash
swift build                                   # the app
Scripts/make-app.sh debug                     # assemble build/Dockyard.app
(cd Packages/DockCore && swift test)          # 47 tests
(cd Packages/DockKit  && swift test)          # 30 tests
Scripts/lint-forbidden-apis.sh                # the CI-enforced bans
Scripts/calibrate.swift                       # measure the real Dock's geometry
```

The project is three Swift packages: `DockCore` (model, preference reading, ordering, icons; no window code), `DockKit` (panels, rendering, geometry, display management), and the thin `Dockyard` app target.

## Contributing

`CONTRIBUTING.md` covers the two rules that matter most: no timers for state observation, and nothing from the forbidden-API list.

## License

MIT. See `LICENSE`.
