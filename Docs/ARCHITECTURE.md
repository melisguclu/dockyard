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
- That extraction is where a bundle path is canonicalized: the observer stores `bundleURL` already standardized and symlink-resolved, so `RunningApplicationState.canonicalPath` must not resolve again. A second resolution reaches the real filesystem and bypasses the injected `TileEnvironment`, which is what a test substitutes to stay hermetic — it made path-based coalescing depend on whether the machine happened to symlink the bundle, so `/Applications/Xcode.app` matched on a developer's disk and failed on a CI runner that symlinks it to a versioned bundle.

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
- The panel is only as large as the region it has to receive events in. A window swallows every click inside its frame whether or not a view claims it: `hitTest` returning `nil` keeps the event out of the bar's own views, but the event is already the panel's and never reaches the application underneath. A panel spanning its display's whole edge therefore made a strip of every window behind it permanently dead — the traffic lights of a window under a side dock, the bottom of one under a bottom dock — which is the one thing a second Dock must not do. No public API shapes a window's event region, so the window is the shape.
- The panel therefore has two extents, both centred on the same point of the display's edge, so the bar lands on the same pixels in either. At rest it **is** the bar: `barLength` by `screenEdgeMargin + barThickness`, and the only pixels it can swallow are the ones it draws on. While the pointer is on it, it grows to hold the widest bar magnification can produce and the tallest tile it can raise.
- The two states are the display link's lifetime, not the pointer's position: the panel grows when the link starts and shrinks when the link stops with the ramp at zero, which is one resize on each side of a hover rather than one per frame. Resizing per frame would put a window-server round trip and a fresh backing surface inside the 16 ms the ramp already spends, and `Docs/PERFORMANCE.md` measures what resizing a window under a blur costs. Growing before the ramp begins is what keeps the magnified icons from being clipped by the window they are drawn in; shrinking only once the ramp is spent keeps the panel large while there is anything left to draw outside the bar.
- The bar's material is a `DockBackdrop`, which picks one of two views at construction and hides the difference behind `apply(bounds:barRect:cornerRadius:)`. Tiles live in a sibling view **above** it either way, because a manually added sublayer of the content view's own layer is drawn below subview layers.
- On macOS 26 the backdrop is an `NSGlassEffectView` with the **clear** style, no tint, and the layout's corner radius. The view **is** the bar: its frame is the bar rect. A mask would clip the effect's shape but not the refraction its edges produce, which is most of what separates glass from a blur, so the glass is never faked with layers.
- `.clear` rather than `.regular`, and the hairline border kept rather than dropped, are both measured rather than chosen. The two styles and the real Dock were photographed over the same known backgrounds — an opaque window of flat colour bands placed under each bar, so both docks sample identical pixels — and the bar body fitted to `output = a × background + b`:

| | `a` | `b` | edge |
|---|---|---|---|
| System Dock, macOS 26.5 | 0.720 | 17.2 | 2 px specular rim, +41 luma over the body |
| `NSGlassEffectViewStyleClear` | 0.710 | 25.5 | none |
| `NSGlassEffectViewStyleRegular` | 0.155 | 76.2 | drop shadow, no rim |

  `.regular` transmits 15% of what is behind it against the Dock's 72%, which is what makes it read as a dark plate rather than glass. `.clear` matches the Dock's transmission to within 1.5% but draws no rim at all, and the rim is most of what the eye uses: the app's own hairline is therefore kept on the glass path at white 22%, which lands the 2 px edge at 147 against the Dock's 150 over a mid-grey background. The remaining difference is a constant 7 luma — 2.7% of range — in the body, and `tintColor` does not close it; a low-alpha black tint measured *lighter*, not darker.
- Corner radius is the same measurement: the bottom-left arc spans 24 rows with a 20 px inset on the Dock and 22 rows with a 21 px inset on ours, so `cornerRadiusRatio` needs no glass-specific value.
- Below macOS 26 the backdrop is an `NSVisualEffectView` with `.hudWindow`, filling the panel and clipped to the bar by an app-owned mask layer, with its hairline at white 12%. It stays clipped rather than resized because AppKit suppresses implicit animations on a view's own backing layer: the view then had to be animated through `NSAnimationContext` while the tiles animated through `CATransaction`, the two interpolated independently, and icons briefly overflowed the bar's ends during the magnification ramp. The glass view does not need the same treatment because nothing animates any more — the display link sets every frame's geometry outright.
- One `DockTileLayer` per tile, holding an icon layer, an indicator layer, a separator layer, and a drop-target highlight. Icons are rasterized once to a `CGImage` at `largesize × maximum backing scale` and assigned as layer contents, so magnification is a GPU transform with no CPU cost per frame.
- All hot-path layer mutation happens inside `CATransaction` with actions disabled. Without that, every position assignment schedules an implicit quarter-second animation.
- Magnification is driven by a `CADisplayLink`. `mouseMoved:` from an `.activeAlways` tracking area only starts it; each vsync then samples the pointer with `NSEvent.mouseLocation` and lays out once. Driving layout from the events themselves looks cheaper and measured worse: event delivery does not align with the refresh, so a vsync that receives none shows stale geometry and a vsync that receives two throws one away. That measured 46 fps with 23% of frames stale on a 60 Hz display, against a solid 60 for the link. A stationary cursor still produces no work, because the link skips a layout whose geometry matches the presented frame and invalidates itself once that has held for twelve frames.
- A tile's context menu freezes the dock for as long as it is open: `rightMouseDown:` pins the cursor the layout is computed from, holds the magnification target at full, and leaves the tile dimmed until `popUp(positioning:at:in:)` returns. The real Dock does the same, and the reason is that the menu is anchored to the magnified tile — letting the display link keep sampling the pointer would shrink the icons out from under a menu that stays where it was, and the cursor has to leave the bar to reach the menu at all.

## Tile menus

- A tile's context menu is not an `NSMenu`. The Dock's menu is a speech balloon with a tail that points at the tile it belongs to, and no public API shapes an `NSMenu` that way, so `DockTileMenuController` presents a borderless `.nonactivatingPanel` at `.popUpMenu` level and draws the rows itself. The panel can become key without activating the app, which is what makes arrow keys and Escape work from a background agent.
- The balloon is measured from a screenshot of the real Dock's menu rather than guessed: an 11 pt corner radius and a tail that hangs 10.6 pt below the body and spans about 25 pt where it leaves it. The tail is drawn as three tangent arcs rather than a triangle — a 6.5 pt concave fillet at each shoulder, straight flanks aimed at a virtual apex 14 pt down, and a 4.2 pt cap that blunts the point 3.4 pt short of it. The Dock's own tail is a continuous-curvature blend rather than circular arcs, which is the only visible difference left at the shoulders. The tail is centred on the tile and clamped to stay clear of the corners; `DockMenuLayout` builds the outline once for a bottom dock and rotates it for the two side orientations, so all three read from the same measurements.
- The balloon is an `NSVisualEffectView` with the `.menu` material, masked to that outline, with the hairline stroked over it. This is the one place the app fakes glass on macOS 26: a tapered tail cannot be expressed as a rounded rectangle, so no arrangement of `NSGlassEffectView`s produces the shape, and a masked glass view keeps its refraction at the rectangle it was given rather than at the mask. Shape fidelity wins over material fidelity here because the tail is what identifies the menu as the Dock's.

## Tile labels

- Hovering a tile shows the tile's name the way the Dock does, in a balloon beside the magnified icon. `DockTileLabelController` draws it in its own borderless `.nonactivatingPanel` at `.popUpMenu` level, reusing the tile menu's backdrop: the `.menu` material masked to the outline with the hairline stroked over it. The panel sets `ignoresMouseEvents`, because a window that swallowed the pointer would cut the magnification out from under the icon the label belongs to.
- That panel is a fixed-size stage rather than a window the size of the balloon: it is as wide as the longest label the app will draw, the balloon is centred inside it, and only the balloon's own view is resized when the name changes. The window is moved, never resized, which is worth about a point of CPU during a sweep and is measured in `Docs/PERFORMANCE.md`. The window shadow is invalidated explicitly on every reshape, since the silhouette AppKit shadows now lives inside the window rather than being the window.
- It is the same speech balloon as the tile menu, with a different body and a different tail, so `DockMenuLayout` builds both from one `DockBalloonMetrics`: place the body, clamp it to the screen, centre the tail on the tile, and rotate the outline for the two side orientations. The menu is the only caller that needs that rotation, because the label has no tail to rotate once the dock moves to a side.
- Every number is measured from screenshots of the real Dock on macOS 26.5 rather than guessed. The body is 26 pt tall with a corner radius of exactly half that — a capsule, not a rounded rectangle — and its width is the title's advance rounded up plus 13 pt on each side. "Visual Studio Code" comes out 149 × 26 pt against the Dock's own 149 × 26. The text is the 14 pt system font at `labelColor`, centred on its cap height rather than on its line box; the two differ by 0.4 pt and the Dock uses the former.
- The tail is shorter and blunter than the menu's: it hangs 6.5 pt below the body against the menu's 10.6, off the same 9 pt base half-width and the same 6.5 pt concave shoulder fillet, with flanks aimed at a virtual apex 7.2 pt down and a 2.5 pt cap. Those flanks come out of the measured taper — the tail's half-width falls 1.25 pt for every point of depth, from 9 pt at the shoulder to 1 pt half a point before the tip — which is what makes it read as a wide beak rather than the menu's long spike.
- That tail only exists on a bottom dock. Move the dock to a side and the Dock puts the name beside the icon as a plain capsule, with nothing bridging the gap, so Dockyard draws it that way too: `DockTileLabelMetrics.balloon(for:)` hands the layout a tail length of zero for the two vertical orientations and moves those 6.5 pt into the tile gap, which leaves the body at the 17 pt it already stood at, and `DockMenuLayout` answers any balloon whose tail has no length with a rounded rectangle. The tile menu keeps its tail in all three orientations.
- The tip hangs 10.5 pt off the tile, so the body starts 17 pt out. That is measured against the **tile**, not against the icon's artwork: a Tahoe icon fills its canvas and sits 10.5 pt under its own label, while an icon carrying transparent padding, such as Visual Studio Code's, appears to sit five points further away. The real Dock does the same thing for the same reason, which is why the gap is not sanity-checked against what the eye measures off an app's visible pixels.
- A title is clamped to 420 pt with a tail ellipsis; the longest label the Dock was observed to render untruncated was a 341 pt window title.
- The label rides the display link that already drives magnification: `stepFrame` samples the pointer once per vsync and presents or dismisses the label from the same hit test, so no second tracking mechanism exists and a moving pointer costs one hit test per frame. The link still invalidates itself twelve frames after the geometry settles — a resting pointer with a label on screen measures 0.0% CPU — and the panel simply stays where it was put. `apply(_:)` re-runs the hit test whenever a new snapshot lands, so a tile appearing or disappearing under a resting pointer cannot leave a name pointing at the wrong icon.
- The label is dismissed when the pointer leaves the bar, while a file is dragged over it, and for as long as a tile menu is open, since the menu is anchored to the same tile and would otherwise be tailed into the label. Closing the menu with the pointer still on the tile brings the name back, which is what the real Dock does.

## App menus

The system Dock's menu for a running app carries items the app itself supplies — Chrome's *New Window*, Spotify's recently played tracks. Those come from `applicationDockMenu(_:)` (or an `NSDockTilePlugIn`) and the Dock collects them over a private Mach service, so **there is no way for another process to ask an app for its dock menu**. Dockyard reconstructs an equivalent menu from what the app already publishes over the Accessibility API instead: its window list, the commands in its own menu bar, and its recent documents.

### The rejected shortcut: borrowing the Dock's own menu

There is one way to get the real thing verbatim, and it was built and measured before being thrown away, so it is recorded here rather than rediscovered. The `com.apple.dock` process exposes its tiles over Accessibility, each with an `AXShowMenu` action, and performing it produces the genuine menu — Spotify's *Recently Played* with real track names, Xcode's recent projects, all of it — readable as a flat list where the app's section appears as a disabled header followed by items whose titles carry three leading spaces.

It is unusable because **the menu only exists while it is drawn**. `AXShownMenuUIElement` on a tile returns `kAXErrorNoValue` until a menu is open, the tile has no children before `AXShowMenu`, and no attribute yields the menu without displaying it. Harvesting therefore means showing the system Dock's menu and dismissing it, and that is visible: the open-read-dismiss cycle measured 32–140 ms warm, 47–438 ms on an app's first harvest, with one observed outlier at 1.5 s. A screen capture taken while the cycle was held open confirms a fully rendered menu, not a partial fade. Selecting one of the harvested rows needs a second cycle, since the elements do not survive the dismissal, so the interaction costs two flashes of a ghost menu on whichever display hosts the real Dock. Verbatim fidelity is not worth a menu that appears to open by itself, and the approach is also dead whenever the real Dock is absent or the tile cannot be matched.

That makes the feature the app's only optional permission. Without Accessibility access the tile menu is exactly what it was before; nothing degrades and nothing is nagged for. `AppMenuStore` checks `AXIsProcessTrusted()` before every refresh and the grant is picked up from the `com.apple.accessibility.api` distributed notification rather than by polling for it.

### Why the reads are cached rather than taken on right-click

Every Accessibility read is a synchronous IPC into the target app, and a two-level walk of a menu bar is hundreds of them. `Scripts/probe-app-menus.swift` prints the live numbers; on an M1 MacBook Pro, macOS 26.5:

| | entries | AX calls | first walk | second walk |
|---|---|---|---|---|
| Xcode | 288 | 1418 | 1021 ms | 104 ms |
| Chrome | 156 | 728 | 60 ms | 20 ms |
| Word | 146 | 769 | 507 ms | 56 ms |
| Finder | 119 | 574 | 118 ms | 12 ms |
| Terminal | 90 | 470 | 125 ms | 67 ms |
| Slack | 76 | 396 | 51 ms | 7 ms |
| Spotify | 49 | 261 | 49 ms | 7 ms |
| Docker Desktop | 14 | 70 | 32 ms | 2 ms |

Most of the first-walk cost is a one-time handshake with a process that has not been addressed over Accessibility before, and it is charged per process rather than per read: the window list alone costs 40 to 85 ms on first contact against 0.5 to 7 ms afterwards for the same app.

Neither column is affordable on a right-click. A tenth of a second before the menu appears is a visible stall and Xcode's first second reads as a hang, so `rightMouseDown:` never touches the Accessibility API at all: `DockTileMenuBuilder` composes the menu from whatever `AppMenuStore` already holds, and an app with no cached snapshot simply gets the base menu.

The cache is filled from the same `NSWorkspace` notifications that already drive the running set. A pid seen for the first time gets a full walk; the app that *becomes* frontmost gets its window list re-read, which is the part that goes stale as tabs and documents change. One in-flight task per pid, and both are dropped when the process exits.

"Becomes frontmost" is load-bearing, and getting it wrong is what a test now guards. `DockStateStore.rebuild()` runs on every workspace notification and on every write to the watched preferences directory — far more often than the rendered output changes, which is why it diffs before publishing. The first version of this cache refreshed the active app on every one of those calls, and the unified log showed the frontmost app being re-read every ten seconds while the machine sat idle: an accidental poll, in an app whose observation path has none. The store now compares the active pid against the previous one and does nothing when it matches, so twenty identical rebuilds cost zero Accessibility calls.

The price of having no timer is that window titles are only as fresh as the last activation: switch tabs in an already-frontmost Chrome and its tile menu still lists the previous title. The event-driven fix is an `AXObserver` per app on `kAXTitleChangedNotification`; the observer itself now exists for minimized windows, and this cache is not wired to it yet.

A snapshot is stored even when the walk yields nothing, so a silent app is not re-walked on every rebuild. An empty snapshot is retried in full the next time that app comes forward, which keeps one slow first contact from poisoning the tile for the rest of the session.

The walk runs inside an `actor`, which is what keeps it off the main thread. `AXUIElement` is not `Sendable`, so the actor is given a pid, creates its elements internally, and returns only value types; nothing else in the app ever holds an Accessibility reference. `AXUIElementSetMessagingTimeout` bounds a hung app to two seconds instead of the six-second default.

### Recent documents, and why `AXIdentifier` beats every other signal

`AXIdentifier` on a menu item is the item's **selector name**, and that is the strongest classifier available anywhere in this feature: unlike a title it is not localized, and unlike a shortcut it does not depend on what the user has rebound. AppKit's standard recent-documents menu populates its items with `_openRecentDocument:`, so a tile's menu can list an app's recent files by identity rather than by guessing at a menu called *Open Recent*:

| | identifiers present | recents found |
|---|---|---|
| Xcode | 59 of 62 real selectors | 9 |
| Preview | 34 of 38 | 10 |
| Finder, Terminal | all, but nib-generated (`_NS:693`) | — |
| Chrome, Slack, Cursor | all, but Electron's single `itemSelected:` | — |

That table is also the limit of the technique. A native document-based app gets its recent files for free and correctly; an Electron app publishes one selector for every item in its menus and cannot be read this way at all, which is why Cursor's 23 recent folders and Word's 11 recent documents — Word uses its own `galleryItemSelected:` — are visible in the menu bar but not surfaced. Reading them would mean matching English titles, and a rule that works only for English menus is worse than no rule.

Recents are the one place the walk goes three levels deep, into the submenus of the File-menu items, bounded at six submenus and forty entries each. That is silent: reading a submenu populates it over Accessibility without opening anything on screen, confirmed by a screen capture of the menu bar taken during a walk that read every submenu of six apps. It is not free — Xcode's full walk goes from 104 ms to about 735 ms with submenus included — which is affordable only because none of it happens on the right-click path.

### Why commands are matched on shortcuts, not titles

Menu titles are localized and app-specific; keyboard shortcuts are neither. A curated table of English titles would have surfaced nothing on a Turkish Chrome, so the selector is the shortcut:

- **Creation commands** are the enabled items in the menu next to the application menu — index 2, the File slot in every Cocoa app — whose shortcut is ⌘N, ⇧⌘N, ⌥⌘N, or ⌘T, ordered by that list rather than by menu position so window creation leads. Chrome yields *New Window*, *New Incognito Window*, *New Tab*, which is the system Dock's menu plus one.
- **Transport commands** come from whichever menu holds both ⌘← and ⌘→, which identifies a playback menu without naming one: Spotify's *Playback* yields *Play*, *Next*, *Previous*. The toggle is the menu's first shortcut-less item, since play/pause carries no shortcut of its own.

Positional indexing is what keeps this from misfiring on an app with no File menu. Docker Desktop's index 2 is *Edit*, and none of ⌘Z, ⌘X, ⌘C match a creation shortcut, so it contributes nothing rather than offering *Undo* from the dock.

Items that only open a submenu are skipped, and so is everything inside one. Terminal's *New Window* is a list of profiles, and pressing its parent does nothing; its children are excluded too, because *Window* and *Tab* read as nothing at all once they are lifted out of the menu that gave them their meaning. The cost is that an app which files all its creation commands under a submenu offers none: Xcode's *File ▸ New ▸* contributes nothing, and Xcode's tile is carried by its recent projects instead.

The shortcut cannot say what a command *means*, only that it creates something, and the two do come apart. Cursor binds ⌘N to *New Text File* and ⇧⌘N to *New Window*, so its rows lead with the file rather than the window. Ranking by shortcut still beats ranking by menu position, which would put *New Tab* above *New Window* on every browser, so the ordering is wrong for fewer apps this way rather than for none.

Commands are invoked with `AXPress` on the menu item, which runs the action without the menu ever appearing on screen and returns in about 2 ms. Titles are re-resolved against the live menu bar at that point and matched on title *and* shortcut, because a menu can hold several items with the same name — Finder's File menu has three called *Eject*. A recent document is resolved one level further, through the submenu title it was found under. Creation commands and recent documents activate the app first; transport commands deliberately do not, because skipping to the next track should not pull Spotify forward.

Window rows raise their window through `AXRaise` after clearing `AXMinimized`, and are matched on index *and* title so a window list that shifted between the cached read and the click aborts instead of raising the wrong window. Titles longer than 44 characters are shortened in the middle, and the balloon is capped at 320 points wide, because window titles are unbounded and a browser tab's title would otherwise stretch the menu across the display.

### Fitting the balloon on the display

Adding these sections took the menu from at most seven rows to a possible thirty-one — six commands, eight recent documents, twelve windows, and five of Dockyard's own — and `DockMenuLayout` clamps the balloon's *origin* to the screen but never its *size*, so an overlong menu would run off the top with its lower rows unreachable. Measured against `DockMenuMetrics.current`, the worst case is 821 pt against 834 pt of usable height on a 1440×900 built-in display: it fits by 13 pt, which is not a margin, it is a coincidence. A 1280×800 scaled mode overflows.

`DockTileMenuBuilder` therefore takes the available height and trims to it. Sections carry a trim priority and the builder drops one row at a time from the highest-priority section that still has any: recent documents first, then the window list, then the app's own commands. Dockyard's own rows have no priority and are never trimmed, so the menu degrades to *Show / Hide / Show in Finder / Quit / Force Quit* rather than to something unusable. The height is computed from the same metrics the content view lays out with, and the tail is always counted even for the side orientations that put it on the width, which errs 10.6 pt toward safety.

## Minimized windows

When `minimize-to-application` is off, which is the default, the system Dock gives every minimized window its own tile between the separator and the Trash. Reading the Dock's own list confirms the arrangement — `AXApplicationDockItem` … `AXSeparatorDockItem`, then one `AXMinimizedWindowDockItem` per window, then `AXTrashDockItem` — and the same set is reachable directly from each application: `kAXWindowsAttribute` on the app element, filtered on `kAXMinimized`. Dockyard reads it from the applications, not from the Dock, so the region is rendered whether or not the real Dock is on the display and without depending on the Dock's accessibility tree.

That makes minimized windows the second thing the optional Accessibility grant buys, alongside the tile menus. Without the grant the region is simply absent, exactly as it was before, and `MinimizedWindowStore` checks `AXIsProcessTrusted()` before every read.

### Observation, and why there is still no timer

Minimizing a window produces no `NSWorkspace` notification, so this is the first state in the app that the workspace centre cannot report. `MinimizedWindowObserver` registers one `AXObserver` per running application on `kAXWindowMiniaturized` and `kAXWindowDeminiaturized`, and adds its run loop source to the main run loop under `commonModes` so the notifications keep arriving while a tile menu is tracking. The observer set is rebuilt from the same running-applications list that already drives everything else, so an app that launches is registered and an app that exits is torn down without any separate bookkeeping.

The callback is a C function pointer and therefore captures nothing: it recovers the pid from the element with `AXUIElementGetPid`, and the store is reached through an unretained context pointer that is turned back into a reference inside `MainActor.assumeIsolated`. A notification only ever schedules a re-read of the one application it came from, through the same actor-isolated inspector the tile menus use, and one in-flight read per pid is coalesced with a pending flag so a burst of notifications collapses into two reads rather than ten.

Two things had to come *out* of that design before it was quiet, and both are the same mistake the app menu cache made first.

`kAXWindowCreated` looks like it belongs in the notification list and buys nothing: a window is never born minimized, so minimization always arrives as `kAXWindowMiniaturized` regardless. What it costs is not nothing. A harness registering the three notifications across nine applications counted **23 `AXWindowCreated` notifications in 60 idle seconds, all from Cursor**, which creates and destroys windows constantly the way Electron apps do, and every one of them would have driven a full window read of a six-window app for no change. With the notification dropped the same harness counts **zero** notifications over the same 60 seconds.

`update(with:)` re-read every running application on every `NSWorkspace` notification, which is roughly nine reads per app switch and eighteen across the deactivate/activate pair. It now reads an application the first time it is seen and re-reads only the one that *becomes* frontmost, which is the rule `AppMenuStore` already follows and for the same reason: the observers keep everything else current, and the activation re-read exists only to retire a window that was destroyed while minimized. `MinimizedWindowStoreTests` pins both, with the authorization check injected so the tests do not depend on the grant the machine happens to hold.

Measured on an M1 MacBook Pro with nine applications running and eight minimized windows, sampling only the seconds where the pointer was clear of every bar so the magnification display link does not contaminate the number:

| | idle CPU | resident memory |
|---|---|---|
| Before the feature | 0.001% | 42 MB |
| With `kAXWindowCreated` and the full re-read | 0.006% | 42 MB |
| Shipped | 0.001% | 42 MB |

Resident memory does not move because every window of an application shares one rasterized tile: the tile is keyed on the application, not on the window. Layout does not move either — `DockGeometry.layout` is 0.003 ms at 24 tiles and 0.003 ms at 32 against a 4 ms frame budget, and still 0.005 ms at 64 — which is measured by `LayoutBenchmark`, skipped unless `DOCKYARD_BENCH` is set. The round trip from ⌘M to a rendered tile is under a second.

### Why the tile is a drawn card and not a thumbnail

The real Dock draws the window's own miniaturized image, and the blocker is a permission rather than a technique. `CGWindowListCreateImage` was obsoleted in macOS 15 and is gone from the SDK, which leaves ScreenCaptureKit, and ScreenCaptureKit does capture a minimized window: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` lists it with `isOnScreen == false`, and `SCScreenshotManager.captureImage` on a `desktopIndependentWindow` filter returns its real contents at full size — measured against minimized Terminal, Activity Monitor, and Claude windows, all three legible. Every one of those calls is behind Screen Recording, which is the permission this app will not ask for, and the capture would have to happen on the miniaturize notification since the contents stop changing there. That is a product decision rather than a limit, and the decision is that the tile does not pretend to be a thumbnail. `MinimizedWindowTileRenderer` draws a window: a rounded card with a title bar and its three lights, with the application's icon badged over the bottom-right corner the way the Dock badges the real thing. It reads as *a window belonging to this app* at a glance, which is what the tile is for, and it never reads as a screenshot that failed to load.

The consequence is that two windows of the same application are told apart by their menu and their position, not by their contents.

### What the order can and cannot reproduce

The Dock orders this region by when each window was minimized. Dockyard assigns a token to a window the first time it sees it minimized and sorts on that, so every window minimized while Dockyard is running lands in the right place. The windows that were already minimized when Dockyard launched are seeded in enumeration order instead — by process, then by the app's own window order — because nothing in the Accessibility API reports when a window was minimized, and the Dock's own list cannot be used to seed it either: the Dock renders a window's title as the app publishes it to the window server, and Chrome's differ from the titles the same windows report over Accessibility, so matching them by title fails on exactly the apps that need it most.

A window destroyed while it is minimized is also not observable — `kAXUIElementDestroyed` would have to be registered per window — so its tile survives until that application next changes state. Clicking it does nothing rather than raising the wrong window, because the raise is matched on index *and* title.


## Geometry

`DockGeometry` is pure and takes a `DockLayoutInput`, so it is fully testable headless. It handles all three orientations through a single along-axis and across-axis abstraction.

Vertical placement is taken from the system rather than modelled: the display hosting the real Dock reserves a strip at its edge, visible as the difference between `frame` and `visibleFrame`, and Dockyard uses that measurement directly for its own bars. At `tilesize` 27 on macOS 26 that strip is 47 points; a ratio-based constant would have put the bar 7 points off. The ratios in `DockMetrics` are the fallback for when the Dock is auto-hidden or absent.

`Scripts/calibrate.swift` prints the live values those ratios are checked against.

`magnificationHeadroom` is how much longer than `barLength` the magnified bar can get, and it is
what the panel's magnified extent reserves at each end. The bar grows by the sum of every tile's
own growth, so the total is the raised cosine sampled at one tile pitch, maximised over the
sub-tile phase of the cursor; the whole of it can land on one side, because the cursor anchors the
tile under it and a cursor at one end of the strip pushes every other tile away from that end. It
is capped by what the tiles present can actually add — a dock of three icons cannot grow by four
tiles' worth — and carries one tile pitch of slack, since shorter tiles sit closer together than
the sampled pitch assumes. Reserving too little would not clip anything: the layout keeps the bar
inside the panel, so the bar would slide instead of growing. `DockGeometryTests` sweeps a cursor
across the strip and asserts the reservation covers the widest bar and the furthest excursion the
layout actually produces.

`magnificationWindowTiles` is measured rather than assumed. Screenshots of the real Dock at ten
known cursor positions give the centre of every icon; the distance between neighbouring centres
is `tilesize × scale + spacing`, so one magnified frame samples the falloff at every icon on the
bar at once. Fitting the raised cosine in `MagnificationCurve` to 128 such samples at `tilesize`
27 and `largesize` 48 on macOS 26 puts the window at 3.9 tiles, with anything from 3.45 to 4.05
within 5% of the best fit. The peak is confirmed at `largesize`: the fit prefers 49 against a
real 48, inside the noise, and the spacing between icons does not scale with magnification.

The 3.0 that value replaced was an assumption, and it was wrong in a way that showed. It matched
the peak but decayed too fast, leaving tiles two to four positions from the cursor measurably
smaller than the real Dock's — a systematic 4 to 6 point error across the whole mid-field rather
than random scatter. Residuals against the fitted window are unbiased. `DockMetrics.sonoma` keeps
3.0 because nothing has been measured on that release.
