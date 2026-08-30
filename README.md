# Dockyard

A native macOS menu bar agent that renders a faithful, interactive copy of the system Dock on **every** connected display, simultaneously and permanently. It mirrors the real Dock. It never modifies it.

![License](https://img.shields.io/badge/license-MIT-blue) ![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## Why

macOS renders the Dock on exactly one display at a time. On a multi-display setup the Dock either stays pinned to the primary display or migrates to whichever display the cursor last pushed against the bottom edge. There is no System Settings toggle and no public or private API to change this.

Dockyard does not try to move the real Dock. It reads the Dock's own configuration and draws an additional bar on the displays that do not have one, so a MacBook connected to an external display has a dock at the bottom of both screens, always.

## Install

Build from source until the first signed release is published:

```bash
git clone https://github.com/melisguclu/dockyard.git
cd dockyard
Scripts/make-app.sh release
cp -R build/Dockyard.app /Applications/
open /Applications/Dockyard.app
```

Dockyard is a menu bar agent with no Dock icon of its own. Its status item offers Settings, Focus Dock, Refresh, Launch at Login, and Quit.

## Features

- A dock-like bar at the bottom of every connected display, at the same time
- Mirrors pinned apps, pinned folders and stacks, recents, and running applications live
- Permanent Finder and Trash tiles and the separator before the Trash region, like the real Dock
- The Trash's own empty and full artwork, and Calendar showing today's weekday and date
- Running indicators, hidden-app dimming, and the Trash tile with its empty and full states
- Click to launch or activate, right-click for Show in Finder / Hide / Quit / Force Quit
- Hover a tile for its name, in the Dock's own balloon with the tail pointing back at the icon
- Right-click a running app for its own windows, commands, and recent documents — New Window, New Incognito Window, Next Track, Xcode's recent projects — read from the app's menu bar (optional, needs Accessibility)
- A tile for every minimized window, between the separator and the Trash, like the real Dock; click one to bring that window back (optional, needs Accessibility)
- Badge counts — Mail's unread total, System Settings' pending update — read from the Dock's own item list and drawn to match it, down to the disc's size, position, digit weight, and red (optional, needs Accessibility)
- Tile order taken from the Dock itself rather than inferred, which puts recents and the minimized-window region exactly where the real Dock puts them (optional, needs Accessibility)
- Click and hold a running app for its windows, the way the real Dock opens App Exposé, as a list rather than as thumbnails
- Optionally drag tiles into your own order, kept in Dockyard's own preferences and applied to every bar, with the real Dock left untouched
- Click a pinned folder for its stack, as a fan, a grid, or a list, following the Dock's own *Display as*, *Show content as*, and *Sort by* settings; click a subfolder to walk down into it
- Drag files onto an app tile to open them with that app, or onto the Trash to move them there
- Spring loading: hold a dragged file over a running app to bring it forward, or over a folder to open its stack, on the system's own springing delay
- Bouncing icons while an application launches, following the Dock's own `launchanim` setting
- Right-click the separator for Dock Settings, the one item there that does not write the Dock's own preferences
- Hides over full-screen applications the way the real Dock does, revealing again when the pointer reaches the edge
- Follows Reduce Transparency and Increase Contrast: the bar turns opaque and takes a full-strength outline
- Dock magnification, using the system's own `tilesize` and `largesize`
- Auto-hide: turn hiding on and every bar hides with the real Dock, revealing on the same `autohide-delay` when the pointer reaches its display's edge and sliding back out when it leaves
- Full keyboard access and VoiceOver: *Focus Dock* in the status menu, arrow keys, type-select, Return to open, and an accessibility element per tile with its own press and show-menu actions
- English and Turkish, with every user-visible string in a string table rather than in the source
- Optionally keeps windows clear of the bar, off by default and behind its own warning, since macOS gives no third-party app a way to reserve screen space
- Reads `tilesize`, `largesize`, `magnification`, `orientation`, `autohide`, `autohide-delay`, `autohide-time-modifier`, `launchanim`, `show-process-indicators`, `show-recents`, `minimize-to-application`, and a folder's `displayas`, `showas`, and `arrangement` from the system, so it changes when the Dock changes
- Suppresses its own bar on the display currently hosting the real Dock (configurable)
- Per-display enable and disable, remembered across disconnects by display hardware identity, not by the volatile `CGDirectDisplayID`
- Handles display connect, disconnect, resolution change, rearrangement, sleep, and wake
- Launch at login via `SMAppService`

## Performance

Dockyard is event-driven. There is no polling anywhere in the observation path: preference changes arrive through a distributed notification with a filesystem watcher as a backstop, application state through `NSWorkspace` notifications, minimize and restore through one `AXObserver` per application, and display changes through `CGDisplayRegisterReconfigurationCallback`. Snapshots are diffed before they are published and again before they are rendered, so the frequent notifications that do not change the rendered output cost nothing.

Measured on an M2 MacBook Pro with a Studio Display, macOS 26.5.2, 25 tiles, `tilesize` 31, one bar because the Studio Display hosts the real Dock:

```
CPU at rest               0.0002% of one core   (0.2 ms of CPU in 120 s)
Idle wakeups at rest      0                     (none at all in 120 s)
Memory footprint          18.4 MB
CPU while magnifying      0.58% of one core     (pointer swept at 500 pt/s)
Magnification frame rate  59.8 /s on a 60 Hz display, one layout pass per vsync
Cold start to first paint 117 ms
Network connections       0, and no networking symbol linked into the binary
```

Reproduce with `Scripts/benchmark.sh` for the rest and memory figures and `Scripts/frame-trace.sh` for the frame figures, both while Dockyard is running. Neither needs `sudo`. `Docs/PERFORMANCE.md` has the full set, the method behind each number, and the twenty-three rules that produce them.

## Privacy and security

- **No network code.** No `URLSession`, no sockets, no telemetry, no crash reporting, no update ping. CI greps for the whole class of APIs and fails the build on any hit.
- **No permission prompts for anything the bar does on its own.** No Screen Recording, no Full Disk Access, no helper tool, no root. Two things can ask, both on an action you took: opening a stack over `~/Downloads`, `~/Documents`, or `~/Desktop` reaches a TCC-protected folder, so macOS asks the first time you click one — the read is a directory listing, and a refusal leaves a row saying the folder cannot be read. Accessibility is the one permission Dockyard can hold, it is off until you grant it from Settings, and it buys four things: a tile's menu listing the app's windows and its own commands, the minimized-window tiles, the Dock's own tile order and badge counts, and the optional keeping of windows clear of the bar. See `Docs/SECURITY-MODEL.md`.
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
- **Minimized window tiles are drawn, not captured.** The real Dock shows the window's own miniaturized image. Every route to a window's pixels is behind Screen Recording, so Dockyard draws a window card badged with the app's icon instead. Two windows of one app are told apart by their menu and their position, not by their contents.
- **Minimize order is right for most windows, not for every window.** With Accessibility granted, the region takes the order from the Dock's own item list. A window is matched to its dock item by title, and a few applications — Chrome among them — publish a different title to the window server than they report over Accessibility, so those windows fall back to the order they were seen minimized in. Without the grant, only the windows minimized while Dockyard is running are in the Dock's order.
- **Clock does not tick.** The Dock draws Calendar and Clock through each app's dock tile plugin, loaded inside the Dock process. Dockyard will not load third-party code, so it draws Calendar's date itself and leaves Clock as its static bundle icon; a live second hand would need a timer, which the project bans.
- **The Trash tile updates on app activation, not instantly.** `~/.Trash` needs Full Disk Access to watch, which Dockyard does not request. Its entry count is readable without any permission, so the state is recomputed whenever the snapshot rebuilds, which in practice means as soon as Finder comes forward.
- **Clicking a running app brings its existing windows forward wherever they already are,** which may be a different display from the bar you clicked. This is exactly what the real Dock does; moving windows between displays is a window-manager feature and an explicit non-goal.
- **An application with no tile of its own does not bounce while it launches.** The real Dock creates a tile the moment a launch begins; Dockyard's tiles come from the Dock's own state, which does not list a process that has not registered yet, so an app that is neither pinned nor already running appears when it is running rather than bouncing its way in.
- **Drag-to-reorder never reaches the real Dock.** *Let me drag tiles into my own order* in Settings reorders Dockyard's bars and keeps the order in Dockyard's own preferences; the real Dock keeps its own, because changing that would mean writing `com.apple.dock` and restarting the Dock. It is off by default, a drag cannot cross the separator or move the Trash, and a tile the Dock adds later appears where the Dock puts it until you drag it. Unlike the real Dock, a tile cannot be dragged out of the bar to remove it, since removal is exactly the write this avoids.
- **Badges are prompt, not instant, and need Accessibility.** They come from the Dock's own item list, and the Dock's accessibility tree posts no notification when a badge changes — only when items appear and disappear. A badge is therefore re-read on every Dock or application event the app already sees, which in practice is seconds, and never on a timer.
- **Click and hold shows a window list, not window previews.** The real Dock's App Exposé draws each window; every route to a window's pixels is behind Screen Recording, which Dockyard does not ask for. The real Dock's two-finger swipe up is also not wired, because the gesture's direction cannot be verified without a trackpad test and a menu that opens on the wrong swipe is worse than no gesture.
- **Stage Manager's strip and the bars do not fight, and Dockyard does nothing about it.** macOS puts the strip on the edge opposite the Dock, on every display, so it is never on the same edge as a bar that mirrors the Dock. The one leftover: with the Dock at the bottom, the strip runs to the bottom of a display that has no real Dock, so a bar can cover its lowest thumbnail. Moving the bar sideways would not fix that and would put it somewhere the real Dock never sits.
- **The separator's menu carries one item, not four.** Right-click the real Dock's separator and it offers Turn Hiding On/Off, Turn Magnification On/Off, Position on Screen, and Dock Settings…. The first three write `com.apple.dock`, so Dockyard offers the fourth alone rather than an item that would silently do nothing.
- **Reading `com.apple.dock` is not a documented contract.** Apple can change the format. The decoder is defensive and fixture-tested, and `com.apple.dock.prefchanged` has a filesystem-watcher fallback underneath it.
- **A bar does not push windows aside unless you ask it to.** The real Dock's strip is removed from `visibleFrame` and no third-party app can do that, so by default a maximized window passes under the bar. *Keep windows clear of the bar* in Settings resizes the overlapping windows through Accessibility instead, after a move or resize settles; it is off by default, it will fight Rectangle, Magnet, and Stage Manager, and turning it off does not put the windows back.
- **A stack is a snapshot of its folder, not a live view.** It reads the directory when you open it, like the real Dock's own stack, and nothing watches the folder while it is closed. A folder larger than the screen ends in a row that opens the rest in Finder, and a folder past 200 entries counts the remainder into the same row.
- **The fan is the Dock's arc, not the Dock's sheet.** The real fan is a tapered sheet narrowing toward the tile; Dockyard draws the same balloon as a tile menu with the rows following the arc. No public API produces the taper.
- **A folder tile takes no drop.** Dragging a file onto it springs the stack open rather than moving the file in, because accepting the drop would mean choosing between a move and a copy for you.
- **The keyboard reaches the bar from the status menu, not from Ctrl+F3.** The real Dock's shortcut is global, and a global shortcut needs a global key monitor. Dockyard will not watch keystrokes, so *Focus Dock* is a menu item.
- **Mirrored displays** get one bar, on the mirror-set primary, not one per mirrored display.

## How it works

One source of truth, N render targets. `DockStateStore` publishes an immutable `DockSnapshot`; each display's panel subscribes to it and applies a diff. Panels never talk to each other, which is what makes "every bar shows the same state" and "one bar cannot break another" fall out of the design instead of needing coordination logic.

See `Docs/ARCHITECTURE.md`.

## Build from source

Requirements: macOS 14 or later to run, Xcode 26 or later to build. The glass backdrop compiles against the macOS 26 SDK, and `#available` guards it at runtime.

```bash
swift build                                   # the app
Scripts/make-app.sh debug                     # assemble build/Dockyard.app
(cd Packages/DockCore && swift test)          # 136 tests
(cd Packages/DockKit  && swift test)          # 145 tests
Scripts/lint-forbidden-apis.sh                # the CI-enforced bans
Scripts/calibrate.swift                       # measure the real Dock's geometry
```

The project is three Swift packages: `DockCore` (model, preference reading, ordering, icons; no window code), `DockKit` (panels, rendering, geometry, display management), and the thin `Dockyard` app target.

## Contributing

`CONTRIBUTING.md` covers the two rules that matter most: no timers for state observation, and nothing from the forbidden-API list.

## License

MIT. See `LICENSE`.
