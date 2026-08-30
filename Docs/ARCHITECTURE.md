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
| App begins and finishes launching | `NSWorkspace.willLaunchApplicationNotification`, `didLaunchApplicationNotification` | Start and stop that tile's bounce; no snapshot rebuild |
| Trash contents | none available | Entry count re-read on every rebuild, one syscall |
| Calendar day rollover | `NSCalendarDayChanged` | Re-request dynamic icons |
| Display add, remove, mode change | `CGDisplayRegisterReconfigurationCallback` | Hide panels on begin, reconcile 350 ms after the last end flag |
| Screen parameters, wake | `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.didWakeNotification` | Same settle path |
| Space switch | `NSWorkspace.activeSpaceDidChangeNotification` | One `CGWindowList` query, repeated once after a 350 ms settle, for full-screen coverage |
| Reduce Transparency, Increase Contrast | `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` | Two booleans pushed to every panel |
| Space switch, bar position | none needed | `.canJoinAllSpaces` handles it |

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

## Auto-hide

The Dock's `autohide` is followed rather than reproduced from a setting of Dockyard's own: turn hiding on in System Settings and every bar hides with the real one, on the same `autohide-delay` before it reveals and the same `autohide-time-modifier` on the slide.

- Each bar hides itself. The real Dock reveals on the display the pointer is on and leaves the others alone, so a `DockRevealController` per panel, driven by that display's own edge, is the behaviour rather than a simplification of it. Nothing coordinates between displays, which keeps the guiding principle intact: the snapshot says whether hiding is on, and each panel decides where its own window sits.
- **A hidden bar is watched by a one-point panel along the display's edge**, not by a global mouse monitor. The trigger's tracking area pushes `mouseEntered`, a cancellable `Task.sleep` waits out `autohide-delay`, and `mouseExited` cancels it. A monitor would have to see every mouse move on the machine, for the whole session, to answer a question the window server answers for free.
- That trigger panel is filled with 1% black rather than left clear. **A non-opaque window does not receive mouse events through its fully transparent pixels** — that is the same rule that lets the bar's own panel pass clicks through the empty space beside it — so a clear trigger would be a window the pointer could never enter. One percent is invisible against every background the edge of a screen can hold and is enough for the window server to route the pointer.
- **The panel hides by leaving the display, not by emptying itself.** Translating the content inside a panel that stays put would leave a window sitting over the edge of the screen for as long as the bar is hidden, and a window swallows the clicks inside its frame whether or not it draws anything there. Off the display it has no frame to swallow anything with; what remains on screen is the one-point trigger, which is the same strip the real Dock takes for its own reveal. `constrainFrameRect` is overridden to return what it is given, because AppKit otherwise pulls a window back onto the screen it was told to leave.
- The slide is an `NSAnimationContext` group over the window's frame. `autohide-time-modifier` multiplies a 0.32 s base, which is a fitted approximation and not a measurement of the Dock's own animation: the Dock exposes the modifier but not the duration it modifies. Every slide carries a token, so a geometry change arriving mid-slide cannot leave a stale completion to reposition the panel afterwards.
- **Hiding again reuses the display link that already drives magnification** rather than adding a second tracking mechanism. `stepFrame` samples the pointer once per vsync and reports the frame it leaves the panel; `mouseExited` reports the same thing when the link is not running. The link stops twelve frames after the geometry settles, and a pointer resting on a revealed bar costs nothing, exactly as it does when hiding is off.
- A reveal that completes with the pointer already gone hides straight back: the panel arrives under a pointer that never entered it, so the completion samples `NSEvent.mouseLocation` once instead of waiting for a tracking event that will never come.
- Nothing here runs on the display that hosts the real Dock, because no panel exists there to hide. The system Dock's own reveal is the only one on that screen.

## Full-screen spaces

- Take a window full-screen and the real Dock stops being a permanent fixture on that display: it hides, and pushing the pointer against the edge brings it back over the full-screen window. Dockyard does the same thing by putting that display's bar into the hiding mode described above, rather than ordering the panel out. Ordering it out would be simpler and would be wrong — the edge would stop answering, and reaching a tile would mean leaving full screen first.
- The trigger is what makes that work over another app's full-screen window: both the bar and its trigger carry `.fullScreenAuxiliary`, so both join the full-screen space instead of being left behind on the desktop one.
- Detection is `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`, keeping windows at layer 0 whose bounds match a display's **full frame** within a point. The full frame is the discriminator: a zoomed window fills `visibleFrame` and leaves the menu bar, a full-screen one covers the display. **Window bounds need no permission; window contents do**, which is why this stays permission-free where a screenshot-based check would not.
- The query runs on `NSWorkspace.activeSpaceDidChangeNotification` and once more after a 350 ms settle, because the notification can arrive while the transition animation is still moving windows into place. Two `CGWindowList` queries per space switch, each on the order of a millisecond, bound to a keystroke or a gesture. Nothing polls, and the result is compared before anything is acted on, so a space switch that changes no coverage costs the query and nothing else.
- `.optionOnScreenOnly` is doing more work than it looks: a full-screen window on a space the user has switched away from is not on screen, so leaving that space uncovers the display without needing a second signal.

## Reduce Transparency and Increase Contrast

- With **Reduce Transparency** on, the material stays and a **dimming wash** goes over it — black at 35% in Dark Appearance, white 87/255 at 46% in Light — on the same rounded rectangle. With **Increase Contrast** on, the hairline is replaced by a full-strength outline. Both are read from `NSWorkspace` and refreshed from `accessibilityDisplayOptionsDidChangeNotification`, which costs one observer and two booleans.
- **AppKit already answers Reduce Transparency; the bar only had the wrong tone.** `NSGlassEffectView` stops passing the desktop through when the setting is on and becomes a plate by itself, so there is nothing to hide and nothing to replace. Measured in Light Appearance on macOS 26.5, the glass alone answers `bar = 0.48 × backdrop + 70` where the real Dock answers `0.259 × backdrop + 78`: the same shape, too bright. The wash is solved from those two lines rather than picked, and puts Dockyard's bar at 146 over a white window against the Dock's 144.
- **The material was dropped once, and that was the wrong answer.** Measured over the wallpaper, hiding the glass and dimming straight onto the panel's own transparency matched the Dock better than anything else — `0.247 × backdrop + 78` against `0.259 × backdrop + 78`, closer than what shipped. It was still wrong, for the reason a wallpaper measurement cannot see: the real Dock blurs what it lets through and Dockyard cannot, because every route to the desktop's pixels is behind Screen Recording. Over a smooth gradient the difference is invisible; over a white window the text behind the bar reads straight through it. A bar that is the right colour and see-through is worse than one that is opaque and slightly off, so the material stays and only the tone is corrected. **A translucent surface has to be measured over something with detail in it, not over a gradient.**
- The Dock's own numbers, for the record: `0.203 × backdrop + 16` in the dark and `0.259 × backdrop + 78` in the light, against roughly `0.84 × backdrop` with the setting off — the control that proves the setting reaches the Dock at all. The real Dock never turns into a plate. Dockyard does, because it has no other way to stop being see-through.
- The hairline colours stay semantic, resolved against the panel's own `effectiveAppearance`: `separatorColor` under Reduce Transparency, `labelColor` for the increased-contrast outline. The wash is not, because no system colour is near it — `windowBackgroundColor` is pure white in Light Appearance, and a plate built on it put the bar at `0.168 × backdrop + 202` against the Dock's `+ 78`, a white shelf where the Dock has a grey one.
- **The dark wash is solved, not measured.** The light one was fitted against a capture of both docks; the dark one is arithmetic on an earlier, indirect reading of the glass and is still waiting for the same capture in Dark Appearance.
- `separatorColor` is 9.8% in every appearance, including the high-contrast ones, so it is not a substitute for the contrast outline; that is why Increase Contrast reaches for `labelColor` at 84.7% instead. Both numbers are from the system, printed rather than guessed.
- The wash is a layer rather than a second view, and it is resolved inside the layout pass that already runs, guarded by an equality check on the two flags and the appearance name. A pointer sweeping the bar therefore pays nothing for the feature being present.

## Drag and drop

- A file dragged onto an application tile opens with that application; a file dragged onto the Trash is moved there with `FileManager.trashItem(at:resultingItemURL:)`, which needs no permission for the user's own files and preserves the Put Back information that a plain delete would lose.
- What a tile accepts is a pure function of its kind and of the operations the drag's source is willing to allow. The Trash asks for `.move` and refuses a source that will not offer one: a source that only permits a copy is telling us the original is not ours to remove, and trashing it anyway would be the one drag-and-drop bug that cannot be undone by dragging back.
- Trashing does not tell the Trash tile anything. The tile's empty and full states come from the entry count that the snapshot build already reads, so the drop asks for a rebuild and the new artwork arrives on the next snapshot, on every display at once.
- A folder tile is still not a drop target, even now that its stack opens. Dragging a file onto it springs the stack open and leaves the drop to the Finder window behind it: accepting the drop would mean choosing between a move and a copy on the user's behalf, which is the one file operation that cannot be undone by dragging back.

## Stacks

Clicking a folder tile opens the folder the way the Dock does, in a fan, a grid, or a list, rather than opening a Finder window. `FolderPresentation` was modelled long before anything rendered it: `displayas`, `showas`, and now `arrangement` are read from the Dock's own `persistent-others` entry, so a folder set to *Grid* sorted *by Kind* in the real Dock opens as a grid sorted by kind here.

- **The contents are read off the main thread, once per opening.** `FolderStackReader` runs `contentsOfDirectory` inside a detached task with the resource keys the sort needs, and hands back a `FolderStackContents` value. Nothing watches the folder: a stack shows what was on disk when it was opened, which is what the Dock's own stack does between openings, and no `FSEvents` stream exists for a directory that is closed.
- **The panel exists only while it is open.** The stack is a borderless `.nonactivatingPanel` at `.popUpMenu` level, built when the read returns and released when it closes, reusing the tile menu's own backdrop — the `.menu` material masked to the speech-balloon outline with the hairline stroked over it, tail pointing back at the tile. Grid, fan, and list all get that tail, because the real Dock's stack points at its tile too.
- **Icons are charged to the cache that already exists.** Entries resolve through the same `IconProvider` actor and its `NSCache` cost limit as the tiles do, under a new `file` flavour, so a stack over a large folder cannot grow the resident set past the limit the icons already live under; memory pressure evicts them and they are cheap to redraw.
- **`automatic` resolves to a fan when the folder is small enough to be one.** The Dock's own rule is not published, so the one here is stated rather than reverse-engineered: a fan when the entry count fits the screen and is at most ten, a grid otherwise. An explicit *Fan*, *Grid*, or *List* in the Dock's settings is always honoured.
- **The fan is an approximation, and it is the one place in the app that admits it.** The real fan is a tapered sheet that narrows toward the tile; this one is the same balloon as the menu with its rows following the arc, offset along a quarter sine away from the nearer screen edge, item zero flush with the tile. The arc is what identifies a fan at a glance; the sheet's taper is not reproduced, and no arrangement of masked glass views produces it.
- **A folder too large for the screen ends in a row that says so.** The layout computes how many rows or cells the display can hold, and when the folder does not fit — or when the reader hit its own 200-entry ceiling — the last slot becomes *N more in Finder…*, which opens the folder. The alternative was a silently truncated stack, which reads as a complete one.
- Clicking a subfolder re-reads and re-presents in place, so a stack walks down a tree without ever leaving the balloon. Escape closes it, the arrow keys move through it, Return opens the highlighted row, and a click anywhere else dismisses it.
- **The magnification freeze is the tile menu's, reused.** An open stack holds the cursor the layout is computed from and keeps the tile dimmed, for the same reason a menu does: the balloon is anchored to the magnified tile and the pointer has to leave the bar to reach it.

**This is the one feature that can produce a permission prompt.** `~/Downloads`, `~/Documents`, and `~/Desktop` are TCC-protected, so the first time a stack over one of them is opened macOS asks. The prompt is triggered by the user's own click on their own folder, the read is a directory listing and nothing else, and a refusal degrades to a row saying the folder cannot be read. `README.md` and `Docs/SECURITY-MODEL.md` state it rather than leaving the no-prompts claim standing unqualified.

## Spring loading

Holding a dragged file over a tile does what it does in the Finder: a running application comes forward, a folder's stack opens, and the drag continues.

- The delay and the on/off switch are the system's own, `com.apple.springing.delay` and `com.apple.springing.enabled` in the global domain, not settings of Dockyard's. Turn springing off in the Finder and the bar stops springing.
- The timer is a cancellable `Task.sleep` started when the drag enters a tile and cancelled when it leaves, on the same grounds as the auto-hide reveal delay: user-initiated, short-lived, and gone the moment the drag is. It lives only for the duration of an active drag.
- What springs is a narrower question than what accepts a drop. A folder springs open but takes no drop; an application springs forward only if it is already running, because the real Dock does not launch an app to receive a hover.

## Launch bounce

The Dock's `launchanim` is followed like every other appearance key: turn *Animate opening applications* off in System Settings and the tiles stay still.

- **The window that reports the launch is the one that reports the end of it.** `NSWorkspace.willLaunchApplicationNotification` starts the bounce and `didLaunchApplicationNotification` stops it, which is the real Dock's own window: the second notification is posted when the application has finished launching, so the two bracket exactly the interval the Dock bounces over. `isFinishedLaunching` observed through KVO would answer the same question a second time, on a `NSRunningApplication` the app deliberately never stores. A launch that never finishes is capped at 30 seconds and a process that dies on the way up ends its own bounce through `didTerminateApplicationNotification`.
- **`willLaunch` is not a promise that `didLaunch` follows, and the first version trusted it.** Two shapes break the bracket, both seen on a real machine: something asks Launch Services to open an application that is *already up*, and something launches a process that never completes the registration `didLaunch` is posted from — a browser started by a test harness, for instance. In both cases the tile bounced for the full 30-second cap with the application sitting there perfectly launched, which is the one way the bounce can look broken rather than absent. So the state machine takes two more inputs: a `willLaunch` whose application already reports `isFinishedLaunching` **does not start a bounce at all**, because the real Dock does not bounce an app that is up; and an activation or unhide from an application that reports itself finished **ends** a bounce that `didLaunch` never closed. The 30-second cap stays underneath as the last resort rather than as the usual exit.
- The observer is now driven by a `LaunchActivityEvent` value rather than by the notification directly, which is what makes those rules testable without a workspace: the notification handler's whole job is to turn a `Notification` into one of four events.
- Nothing about a bounce reaches `DockSnapshot`. A launch is a transient state of a *tile*, not of the dock's contents, and putting it in the snapshot would push a new generation through the diff on every launch and again on every finish, for something no tile's geometry depends on. `LaunchActivityObserver` publishes a `Set<DockTileID>` straight to the panels instead, and the tiles the snapshot already carries are what it is matched against.
- **A tile that does not exist does not bounce.** The set is intersected with the application tiles the panel is actually rendering, so a background helper or an agent — neither of which the Dock shows — costs a set comparison and stops there. The consequence is the honest one: an application that is not pinned has no tile to bounce until it is running, by which point the bounce is over. The real Dock creates the tile at launch time; Dockyard's tiles come from the snapshot, and the snapshot cannot see a process that has not registered yet.
- The bounce is a single additive `CAKeyframeAnimation` on the icon layer's `position.y` — `position.x` for a side dock, negative for a dock on the right. Additive is what makes it survive the layout pass: `relayout` assigns the layer's frame on every magnified frame, and an animation that carried absolute positions would fight it. The press dim is animated with the same object so a tile pressed mid-launch does not leave its shadow behind on the dock line, and the running indicator is deliberately left out of it — the real Dock leaves the dot on the bar while the icon leaves.
- **A launch that ends mid-flight finishes its bounce.** Stopping used to mean removing the animation, which teleports the icon from wherever it is back onto the dock line — up to a full 15 pt jump in a single frame, and the one thing about the bounce that read as wrong. `finishLaunching` instead re-adds the same keyframes with the same `beginTime` and a `repeatCount` of the cycles already elapsed plus one, so the animation is unchanged in every visible respect and simply stops at the end of the cycle it is in, where the value is already zero. The real Dock does the same: its last bounce is a full one, measured falling to rest at 60 pt/s rather than being cut. The panel's `bouncing` extent is held for the remainder of that cycle, since a window is a hard clip and shrinking it on the notification would cut the icon in half on its way down.
- The panel grows before the icon does. The bar's window has a third extent alongside resting and magnified, and the extents compose: a tile bouncing under the pointer needs the magnified icon's height *plus* the travel, and a bounce with the pointer elsewhere needs the resting tile's plus the same. The order matters more than the arithmetic — `syncPanelExtent` runs before the animation is added, because a window is a hard clip and an icon that leaves a panel that has not grown yet is simply cut in half.
- **The travel and the timing are measured, not fitted.** 40% of a tile of travel over a 0.35 s rise, a 0.35 s fall, and a 0.01 s rest, eased out and then in, for a 0.71 s period. They were read off a 60 fps recording of the real Dock on macOS 26.5 launching a pinned application, tracking the tile by template match against its own resting frame: the icon leaves the bar at 1.11 s, holds its peak between 1.37 s and 1.55 s, lands at 1.81 s, and leaves again at 1.83 s. The peak is 24 device pixels on a 60-pixel icon — 12 pt on a 30 pt tile — and the near-linear ramps either side of the peak are what an ease-out into an ease-in produces. The first version of this was fitted rather than measured, at 65% of a tile over a 0.32 s rise, a 0.32 s fall and a 0.08 s rest, which is 60% too much travel and five times too long a pause at the bottom; both are visible next to the real Dock. **The recording was a development-time measurement on a developer's machine, not a capability of the app** — Dockyard still never asks for Screen Recording, and the same admission the old note made still applies to the auto-hide slide's base duration.
- **The travel is assumed proportional to the rendered tile, and that was measured at one size.** The 12 pt peak was read off a dock whose tiles the fit-to-display shrink had already taken from the requested 38 pt down to 30 pt, so the ratio is against what is drawn rather than against `tilesize`. A second measurement at a different Dock size would settle whether the real Dock scales the bounce or holds it at a fixed height; until one exists, the proportional reading is the one this app follows, because everything else the Dock draws scales that way.

## Tile menus

- The separator is the one non-interactive tile that still answers a right-click, and it answers with a single item: **Dock Settings…**, which opens the Desktop & Dock pane. The real Dock's separator menu also carries Turn Hiding On/Off, Turn Magnification On/Off, and Position on Screen; all three write `com.apple.dock`, which is the one thing this app will not do, and an item that silently did nothing would be worse than an item that is not there. `providesMenu` is therefore a separate question from `isInteractive`: the separator has a menu, no label, no click, and no drop target.
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

Minimizing a window produces no `NSWorkspace` notification, so this is the first state in the app that the workspace centre cannot report. `ApplicationWindowObserver` registers one `AXObserver` per running application on `kAXWindowMiniaturized` and `kAXWindowDeminiaturized`, and adds its run loop source to the main run loop under `commonModes` so the notifications keep arriving while a tile menu is tracking. The observer set is rebuilt from the same running-applications list that already drives everything else, so an app that launches is registered and an app that exits is torn down without any separate bookkeeping.

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

The memory column is resident size, which is what this comparison was taken with; it counts shared framework pages and overstates the process by more than double, and `Docs/PERFORMANCE.md` explains why the footprint of about 18 MB is the number to budget against. What matters here is that the column does not move: every window of an application shares one rasterized tile, because the tile is keyed on the application, not on the window. Layout does not move either — `DockGeometry.layout` is 0.003 ms at 24 tiles and 0.003 ms at 32 against a 4 ms frame budget, and 0.006 ms at 64 — which is measured by `LayoutBenchmark`, skipped unless `DOCKYARD_BENCH` is set. The round trip from ⌘M to a rendered tile is under a second.

### Why the tile is a drawn card and not a thumbnail

The real Dock draws the window's own miniaturized image, and the blocker is a permission rather than a technique. `CGWindowListCreateImage` was obsoleted in macOS 15 and is gone from the SDK, which leaves ScreenCaptureKit, and ScreenCaptureKit does capture a minimized window: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` lists it with `isOnScreen == false`, and `SCScreenshotManager.captureImage` on a `desktopIndependentWindow` filter returns its real contents at full size — measured against minimized Terminal, Activity Monitor, and Claude windows, all three legible. Every one of those calls is behind Screen Recording, which is the permission this app will not ask for, and the capture would have to happen on the miniaturize notification since the contents stop changing there. That is a product decision rather than a limit, and the decision is that the tile does not pretend to be a thumbnail. `MinimizedWindowTileRenderer` draws a window: a rounded card with a title bar and its three lights, with the application's icon badged over the bottom-right corner the way the Dock badges the real thing. It reads as *a window belonging to this app* at a glance, which is what the tile is for, and it never reads as a screenshot that failed to load.

The consequence is that two windows of the same application are told apart by their menu and their position, not by their contents.

### What the order can and cannot reproduce

The Dock orders this region by when each window was minimized. Dockyard assigns a token to a window the first time it sees it minimized and sorts on that, so every window minimized while Dockyard is running lands in the right place. The windows that were already minimized when Dockyard launched are seeded in enumeration order instead — by process, then by the app's own window order — because nothing in the Accessibility API reports when a window was minimized, and the Dock's own list cannot be used to seed it either: the Dock renders a window's title as the app publishes it to the window server, and Chrome's differ from the titles the same windows report over Accessibility, so matching them by title fails on exactly the apps that need it most.

A window destroyed while it is minimized is also not observable — `kAXUIElementDestroyed` would have to be registered per window — so its tile survives until that application next changes state. Clicking it does nothing rather than raising the wrong window, because the raise is matched on index *and* title.


## Reserved screen space

The real Dock's strip is removed from `visibleFrame`, so a maximized window stops above it. No third-party process can do that, which is why a Dockyard bar has a window pass under it, and it is the most-felt daily difference against the real Dock. **This is the one feature in the app that crosses a stated non-goal**, so it is off by default, behind its own switch in Settings, with the warning next to it.

- With it on, `ScreenSpaceReserver` shrinks the windows that overlap a bar rather than reserving anything: there is no reservation API to call. `DisplayCoordinator` publishes one `ReservedArea` per bar — the display's frame, the strip's thickness, and the edge it sits on, converted once into the top-left space the Accessibility API uses — and the reserver keeps every standard window of every regular application clear of it.
- **A window is only ever shrunk, never moved out of the way.** The edge over the bar is pulled off it and the opposite edge stays where the user put it, because a window that jumps is a window the user has to find again. A window that would end up smaller than 160 × 120 pt is left alone instead of being crushed, and a one-point overlap is inside the tolerance and costs nothing.
- **Nothing happens mid-drag.** AX move and resize notifications arrive dozens of times a second while a window is being dragged, and acting on each of them would fight the user's own hands. The reserver collects the process identifiers it has heard from, waits 150 ms, and holds that wait open for as long as a mouse button is down, so exactly one evaluation runs per gesture, after it ends. `ScreenSpaceGeometry` — the part that decides the new frame — is a pure function over rectangles and is where the tests are.
- **It is a second observer, not a second mechanism.** `ApplicationWindowObserver` is the same class that already carries the minimize notifications, registered again per application with `kAXWindowMoved`, `kAXWindowResized`, and `kAXWindowCreated`. Reading and writing a window's frame goes through an actor, off the main thread, with a 0.5 s messaging timeout so a hung application cannot stall the bar.
- **Turning it off does not put the windows back.** Nothing recorded where they were, and inventing a previous size would be worse than leaving them. That is in the warning, not just here.
- It will fight Rectangle, Magnet, and Stage Manager, each of which also believes it owns window geometry. The honest framing is that this is a window-manager feature living in an app that is not one, which is why it asks first.

## Keyboard access and VoiceOver

- Tiles are `CALayer`s, so there is nothing for an assistive client to find. `DockContentView` answers as a group whose children are `NSAccessibilityElement` proxies, one per tile, carrying the tile's label, a role description that says what kind of tile it is, whether the application is running or hidden, and a press action that does what a click does.
- **The proxies are built on first ask and not before.** Nothing exists until an assistive client requests `accessibilityChildren`, at which point they are created and then kept in step with the layout; with VoiceOver off the cost is one boolean tested inside the layout pass that already runs. The `NSAccessibilityShowMenu` action is wired to the same balloon menu a right-click opens, so the tile's own commands are reachable without a mouse.
- **Keyboard focus is granted, not assumed.** The bar's panel returns false from `canBecomeKey` at rest, because a panel that can take focus at any moment is a panel that can steal it. *Focus Dock* in the status menu flips that flag for one session: arrow keys walk the interactive tiles, Return or Space activates, the label balloon follows the focused tile, typing jumps to the tile whose name starts with what was typed, and Escape or Tab gives the focus back and returns the panel to not being focusable.
- The real Dock uses Ctrl+F3 for this. Dockyard does not, and will not: a global shortcut means a global key monitor, which means seeing every keystroke on the machine — the one thing the Accessibility section of the security model promises the app never does. A menu item is worth less than that promise.

## Settings window

- The window is an `NSTabViewController` in `.toolbar` style hosting one `NSHostingController` per pane, not a SwiftUI `TabView`. A `TabView` on macOS draws an inline segmented control inside the content area, drops the `tabItem` icons entirely, and leaves the window one fixed size for every pane; the toolbar style is what the rest of the system calls a settings window, and it is the only way to get the icon-over-label tabs, the pane name as the window title, and the animated resize between panes.
- Each pane sizes the window rather than the window clipping the pane. The hosting controllers set `sizingOptions = [.preferredContentSize]`, so the tab controller resizes the window to whatever the pane asks for — 607 pt for General against 283 pt for Displays. The previous fixed `480 × 380` frame cut the last footer off General mid-sentence and left half of Displays and About empty.
- Explanations live inside the row they explain. A `Toggle` whose label is two `Text` views renders as title plus secondary description in a grouped form, which is how System Settings writes the same thing; a `Section` footer is kept only where the text belongs to the section rather than to one control, as with the Accessibility paragraph that covers three separate features.
- About shows `NSApplication.shared.applicationIconImage` rather than an SF Symbol standing in for it, because the app has an icon and drawing something else in its place is the kind of detail that reads as unfinished.

## Localization

- Every string the user can read goes through `NSLocalizedString` against its own module's bundle: menu titles and stack text in `DockKit`, the Finder and Trash tile labels in `DockCore`, and the status menu and settings in the app target. Each of the three targets carries its own `.lproj` tables, and `Scripts/make-app.sh` already copies the packages' resource bundles into the app.
- English and Turkish ship as Dockyard's own tables, and `CFBundleLocalizations` declares exactly those two, so the per-app language picker in System Settings offers what the app can actually deliver. A missing key falls back to the key itself, which is visible in testing and harmless in release, and a missing language falls back to English.
- **The words the Dock also says are read from the Dock, not translated again.** `SystemDockStrings` maps Dockyard's own keys onto the tables inside `/System/Library/CoreServices/Dock.app` — `DockMenus.strings` for the eight menu commands, `Localizable.strings` for the Finder and Trash tile names and the empty stack, `Accessibility.strings` for the tile role descriptions — and macOS ships those in 38 languages. A Turkish Mac gets *Çıkmaya Zorla* rather than Dockyard's own *Zorla Çık*; a German one gets *Sofort beenden* without Dockyard carrying a German table at all. It is resource reading, not private API, and it costs nothing in the bundle.
- Every lookup passes Dockyard's own string as `NSLocalizedString(value:)`, so a key Apple renames degrades to the app's own table rather than to a raw key. `SystemDockStringsTests` asserts every mapped key still resolves against the installed Dock, which turns such a rename into a red build rather than a silent regression.
- What the Dock has no words for stays Dockyard's own: the Settings pane prose, *Dockyard cannot read this folder*, the running and hidden state, and the badge. Those are English and Turkish only, so a German Mac shows German tile menus and an English Settings window. That is the honest split — half a translation the system already paid for beats none.
- The Dock's own labels are not translated by Dockyard: a tile's name comes from the Dock's `file-label` or the bundle's own display name, which macOS has already localized. The two exceptions are Finder and Trash, which the app names itself because it synthesizes those tiles.

## The Dock's own item list

Everything above this line is inferred: the tiles are rebuilt from `com.apple.dock` plus the running-applications list, and the order they come out in is Dockyard's reading of how the Dock arranges them. The Dock's own accessibility tree is the ground truth for the same question, and reading it buys three things at once — the exact order including recents, the badge counts, and the order of the minimized-window region — for one walk of a list of about thirty elements.

What is actually there, probed on macOS 26.5: the Dock process has a single `AXList` child, and its children are `AXDockItem` elements carrying `AXSubrole` (`AXApplicationDockItem`, `AXFolderDockItem`, `AXURLDockItem`, `AXMinimizedWindowDockItem`, `AXSeparatorDockItem`, `AXTrashDockItem`), `AXTitle`, `AXURL` for everything that has a file or web location, `AXIsApplicationRunning`, and `AXStatusLabel`, which is the badge — `"1"` on System Settings with an update waiting. `AXProgressValue` exists and is always nil, which is why download progress stays out of scope rather than being attempted and dropped.

- **Matching is on `AXURL` first and the title second.** A tile and a dock item are the same thing when their locators agree — the standardized file path, or the absolute string for a web location — which is stable across localization and across two apps with the same name. Titles are the fallback for a tile with no URL, and are matched within one subrole so a minimized window called *Downloads* can never consume the Downloads folder's item. Each item is consumed once, so two windows with the same title take one item each in order.
- **The order is applied as a stable sort, not as a replacement.** Every matched tile takes the item's index as its key and every unmatched tile inherits the key of the tile it followed, so a tile the Dock does not list stays where the inference put it instead of being flung to one end. Spacers are not eligible at all: they are the Dock's own, they have no identity to match on, and they stay where the preference domain put them.
- **A list that matches almost nothing is thrown away.** If fewer than half the eligible tiles find an item, the order and the badges are both discarded and the inferred arrangement stands. This is the same defensive posture as `DockPreferencesDecoder`: when Apple changes the tree, badges disappear and the bars keep working.
- **Badges are untrusted text from other applications.** `AXStatusLabel` is whatever an app put in its dock tile. It is collapsed to a single line, clamped to six characters, and dropped when it is empty, before it reaches a layer. The renderer draws it once per string and size, at a size derived from `largesize` rather than from the current magnified frame, so a sweep across the bar is still a GPU transform on cached images.
- **The badge's shape is measured against the real Dock rather than guessed.** Screenshots of the same application, on the same `tilesize`, put the Dock's badge at 24 px on a 62 px tile — `0.387 × tile` — as a flat disc with **no white ring**, centred `0.216 × tile` in from the icon's right edge and `0.184 × tile` down from its top. It stays a circle for one and two characters, because that is what the Dock does with a two-digit count: the digits get tight rather than the disc getting wide. The renderer only grows a capsule when the glyphs genuinely do not fit, which is what a three-digit count needs. The digit is sized by its own glyph bounds — cap height `0.38 × diameter`, system font at regular weight — and centred on those bounds rather than on the line box, which is what makes a `1` and a `91` sit on the same optical centre. The fill is `sRGB(245, 67, 55)`, chosen so that the rendered pixels match the Dock's own badge on a P3 display to within two units per channel; the source colour is not published anywhere, so it was matched at the far end of the pipeline instead of copied.
- **What it fixes that inference could not.** The real Dock interleaves minimized windows with the pinned folders in the trailing region by when each was minimized; `TileOrdering` puts the whole minimized region first because it has no way to know. With the list read, the region comes out in the Dock's own order. Recents land where the Dock puts them rather than after the pinned run. The order is also now verifiable against ground truth rather than argued from the plist.

### Observation, and the one place the roadmap was wrong

The roadmap costed this as "entirely push-based". It is not, and the measurement is worth keeping. On the Dock's application element, `AXObserverAddNotification` succeeds for `kAXCreated` and `kAXUIElementDestroyed` and returns `kAXErrorNotificationUnsupported` (-25207) for `kAXValueChanged`, `kAXTitleChanged`, `kAXLayoutChanged`, and an invented `AXStatusLabelChanged`. Per-item registration returns the same error for all four. So tiles appearing and disappearing are push-based — a launch, a quit, a minimize, a reorder in the real Dock, all arrive — and **a badge changing on its own does not**.

The consequence is stated rather than papered over: a badge is re-read on every event the app already has — a dock item created or destroyed, an application launching, quitting, hiding or coming forward, a Dock preference change, a minimize or a restore — and never on a clock. In practice a badge that appears while its application is in the background lands on the next such event, which is usually within seconds and is not guaranteed. The alternative was a timer, and the no-timers rule is worth more than a badge that is instant instead of prompt.

The reads themselves follow the pattern the app menus already established: the walk happens on an actor off the main thread with a two-second messaging timeout, one read is in flight at a time with a pending flag collapsing a burst, notifications are coalesced for 120 ms before a read is started, and the result is compared before anything is published, so an event that changes nothing costs the walk and stops there. `AXIsProcessTrusted()` is checked before every read: without the grant `DockItemStore` holds an empty list, the inferred order stands, and no badge is ever drawn.

## App Exposé

Press and hold a running application's tile and the real Dock shows that app's windows. Dockyard opens the window list instead, in the same balloon a right-click uses, because a thumbnail grid needs the window's pixels and every route to those is behind Screen Recording.

- The trigger is the only new part. `mouseDown` starts a cancellable 0.65 s sleep, a drag out of the tile or a mouse-up cancels it, and when it fires the pointer is re-checked against the tile before anything is shown. A hold that opened the list swallows the click, so releasing the mouse over the tile does not also activate the application.
- The content is `appMenu.windows` and nothing else — no commands, no recents, no Dockyard rows — trimmed to what the display can hold the same way a tile menu is. An application with no windows, or one running without the Accessibility grant, gets nothing at all rather than an empty balloon.
- **The trackpad's two-finger swipe up is deliberately not wired.** The gesture would be `scrollWheel`, and getting its sign right means deciding between `scrollingDeltaY` and `isDirectionInvertedFromDevice` on a real trackpad with natural scrolling both on and off. Shipping it untested risks a menu that opens on the opposite gesture, which is exactly the self-opening UI this project refuses. Press and hold is the trigger until the swipe can be measured.

## Local tile order

Reordering tiles the way the real Dock does would mean writing `com.apple.dock` and restarting the Dock, which breaks G11 and the no-subprocess ban in one change. The third path is to keep the order in Dockyard's own preferences and apply it as a permutation over `TileOrdering`'s output, leaving the real Dock untouched. It is off by default, because with it on the bars deliberately disagree with the Dock about order, which is a documented dent in G3.

- **The override is a list of persistence keys, not indices.** A tile's key is its `DockTileID` — `bundle:com.apple.Safari`, `path:file:///Users/…/Downloads`, `builtin:trash` — so it survives relaunches, resolution changes, and the Dock adding or removing other tiles. Minimized windows and spacers have no key by design and are never recorded.
- **The separator seals two regions and nothing crosses it.** A drag is confined to the side of the separator it started on, the Trash is always last, and a drop onto the separator, the Trash, or a minimized window is refused rather than absorbed. `DockReorderPolicy` is the pure function that decides all of this, and is where the tests are.
- **A tile the Dock adds later is not flung to the end.** The same stable sort the Dock's own list uses applies here: a key the override does not know inherits the position of the tile it follows, so a newly pinned app appears next to where the Dock put it and stays there until it is dragged.
- **The icon follows the pointer and the row opens around it.** The pressed tile is grabbed at the fraction of itself the pointer landed on, so it stays under the cursor as magnification grows it, and its layer is drawn at the pointer's position with a raised `zPosition` while its *slot* stays in the row — which is what the hit test reads, so crossing into a neighbour's slot is what swaps them. The tiles that give way slide rather than jump: each swap records how far every tile moved, and the residual is decayed per frame by the display link that magnification already runs, over 0.22 s. Nothing is handed to Core Animation and no implicit animation is enabled, so the slide obeys the same rule as the magnification ramp. On drop the dragged tile inherits the same residual and glides into its slot instead of snapping.
- **The icon is not lifted clear of the bar.** It travels along the bar's axis only. The real Dock lifts the icon out and can drop it away from the Dock entirely, which removes it — that is a write to the Dock's own preferences, which this feature exists specifically not to do, and a bar-shaped window has nowhere to lift an icon to.
- The drop is committed once, to the app's preferences, and the store rebuilds from it, so every bar on every display adopts the new order in the same snapshot. Turning the setting off restores the Dock's order without discarding what was recorded, so turning it back on returns to the user's arrangement.

## Stage Manager

Stage Manager keeps a strip of window thumbnails along one screen edge, and the roadmap's premise was that the strip sits on the left and a bar on that edge has to be inset past it. **Measured, that premise is wrong, and the code that acted on it was removed.**

The measurement, on a two-display machine with Stage Manager on and the Dock moved to the left edge: `CGWindowListCopyWindowInfo` reports WindowManager's own *App Icon Window* elements at x = 2502 on a 2560-point display — the **right** edge — while the Dock's window sits on the left edge of the other display. macOS puts the strip on the edge opposite the Dock, and it does so on every display, not only on the one hosting the Dock. Since a Dockyard bar mirrors the Dock's own edge, the strip is always on the other side of the screen from it, and there is nothing to step aside from.

What is left is a caveat rather than a feature, and it lives in the README: with the Dock at the bottom, the strip runs down the left edge and stops above the real Dock on the display that hosts it. On the other displays macOS does not know a bar is there, so the lowest thumbnail can sit behind one. Insetting the bar would not fix that — the bar would have to move up, not sideways — and shifting it off the screen's centre line would break the thing the whole project is for, which is that the bar is where the Dock would be.

`com.apple.WindowManager` is therefore not read at all. The honest form of this item is a measurement and a decision, not a constant.

## Geometry

`DockGeometry` is pure and takes a `DockLayoutInput`, so it is fully testable headless. It handles all three orientations through a single along-axis and across-axis abstraction.

Vertical placement is taken from the system rather than modelled: the display hosting the real Dock reserves a strip at its edge, visible as the difference between `frame` and `visibleFrame`, and what that strip leaves over its bar is the margin Dockyard puts under its own. At `tilesize` 27 on macOS 26 the strip is 47 points against a 41-point bar, a 6-point margin; a ratio-based constant would have put the bar 7 points off. The ratios in `DockMetrics` are the fallback for when the Dock is auto-hidden or absent.

The subtraction has to use the bar the Dock actually drew, which is why `SystemDockLocator.edgeMargin` fits the tile to the *host* display before it subtracts. The strip is one measurement from one display, and Dockyard's panels are on the others: a bar fitted to a 1440-point laptop screen is nowhere near the size of the one the Dock drew on the 2560-point display beside it, and subtracting the laptop's thickness from the wide display's strip left tens of points over. That surplus went straight into the margin, and the bar climbed off the bottom of the screen as `tilesize` went up.

`Scripts/calibrate.swift` prints the live values those ratios are checked against.

The real Dock also stops growing before its bar reaches the ends of the display, so `tilesize` is
what the user dragged to rather than what gets drawn. Measured from the Dock's own Accessibility
geometry on a 2560-point display on macOS 26, the item pitch is `tilesize` plus a constant while
the bar still fits, and then holds: at `tilesize` 128 a bar of 26 tiles settled at a 93.7-point
pitch and one of 34 tiles at 72.6, an effective tile of 89.7 and 68.6 points. `fittedTileSize`
reproduces both to within a point by shrinking the tile until the resting bar plus
`fitSlackTiles` — one tile, the slack the Dock keeps across the two ends — fits the display.
Without it a dragged-up `tilesize` ran off both ends of the screen, because the layout only ever
slides an overlong bar, it never scales it.

The fit is a bisection rather than a division because spacing, padding and separator lengths are
each rounded and floored, which leaves the bar length monotonic in the tile size but not
proportional to it. It is computed when a snapshot arrives or a panel changes display rather than
per frame, and every display fits to its own width, so a bar that fits a 5K display is not the
size drawn on the laptop screen beside it. The fitted size is what the rest of the panel is built
from — bar, panel frame, and the pixel size icons are rasterised at all follow it.

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
