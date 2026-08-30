# Roadmap

Where Dockyard stands against the market, and what closes the remaining gap to the real Dock.

Written 2026-08-27 against the state of the tree at that date. The ordering is deliberate: fundamentals first, specifics last. Every entry carries its cost against the budgets in `Docs/PERFORMANCE.md` and the design rules in §8.2 of `PLAN.md`, because in an always-running agent a feature that breaks the idle budget is not a feature.

## Contents

- [1. Market position](#1-market-position)
- [2. What competitors have that Dockyard does not](#2-what-competitors-have-that-dockyard-does-not)
- [3. What Dockyard has that competitors do not](#3-what-dockyard-has-that-competitors-do-not)
- [4. Tier 0 — Baseline parity](#4-tier-0--baseline-parity)
- [5. Tier 1 — Behavioural depth](#5-tier-1--behavioural-depth)
- [6. Tier 2 — Deep fidelity](#6-tier-2--deep-fidelity)
- [7. Tier 3 — Specific and contested](#7-tier-3--specific-and-contested)
- [8. Performance ledger](#8-performance-ledger)
- [9. Suggested order](#9-suggested-order)

---

## 1. Market position

### Direct competitors — a dock on every display

Two kinds of product address the same problem. The paid, closed-source utilities draw a second dock with settings of their own — one on a subscription or a lifetime licence, one as a low one-off price on the App Store with an independent set of apps per display. The open-source attempts are a handful: one reads the plist and stops at a shallow feature set, one was archived in 2023, and one solves a different problem by pinning the real Dock to a single monitor.

### Adjacent market — Dock replacements

Full Dock replacements, most of them paid and closed source, two of them GPL-3 and well-starred, plus a customization niche of icon, theme, and layout tools.

### Reading

The niche is real and badly served. Open-source gravity in this category sits on window previews, not on mirroring, so Dockyard is not competing with the category's most popular project — it is filling a space next to it. No maintained, permission-free, MIT-licensed "dock on every display" project exists.

The strategic implication runs through the whole of this document: do not chase the replacement apps' feature lists. Widgets, themes, Launchpad, and app groups are their ground, and following them there puts Dockyard in a crowded field where it has no advantage. Dockyard's differentiator is fidelity plus honesty — an exact copy of the real Dock that asks for nothing and costs nothing.

---

## 2. What competitors have that Dockyard does not

1. **Live window previews on hover** — the replacements' headline feature. Requires Screen Recording.
2. **Reserving screen space so windows cannot slide underneath** — one replacement offers this as a setting. Dockyard now offers it too, off by default and behind a warning (§5.3), because macOS gives no third-party app a real reservation API; a bar left at the default still has windows pass under it.
3. **Appearance settings of their own** — tile size, position, theme, colour, opacity, per display. Dockyard exposes none; even a size override is absent.
4. **Independent content per display** — the per-display docks allow a different set of apps per screen.
5. **Widgets** — clock, calendar, media controls, battery, weather.
6. **Launchpad, search, application launcher** — the replacements.
7. **Project-based groups and presets** — the replacements and the customization tools.
8. **Shortcuts and scripted actions** — the replacements and the per-display docks. Ruled out here by the no-subprocess and no-Apple-Event bans.
9. **Custom icons and themes** — the replacements and the customization tools.
10. **Global keyboard shortcuts** — window switcher, auto-hide toggle.
11. **Badge counts and progress bars** — one replacement.
12. **Drag-to-reorder that persists** — free for replacements, which own their own layout.
13. **Signed, notarized releases and a Homebrew cask.** Dockyard is build-from-source only.

## 3. What Dockyard has that competitors do not

1. **Real mirroring fidelity.** `tilesize`, `largesize`, `magnification`, `orientation`, `show-process-indicators`, `show-recents`, and `minimize-to-application` are read from the system and followed live. No competitor reads this deeply.
2. **Permanent Finder and Trash tiles, the separator, the Trash's own empty and full artwork, Calendar's real date.**
3. **Minimized-window tiles** in the correct region, as the real Dock places them.
4. **The Dock's own balloon label**, tail pointing back at the icon, orientation-aware.
5. **An app's own menu-bar commands and recent documents** in the tile's context menu, via Accessibility.
6. **Self-suppression on the display hosting the real Dock.** Nobody else does this; competitors leave two docks stacked on one screen.
7. **Zero-polling, event-driven architecture** — 0.0002% CPU and zero idle wakeups at rest, 18 MB, measured and published.
8. **No network code**, enforced by a CI grep. No subprocess, no AppleScript, no `killall`.
9. **No permission prompts by default.** Accessibility is optional and off.
10. **Never writes `com.apple.dock`** and never restarts the Dock.
11. **Per-display state keyed by EDID hardware identity**, not `CGDirectDisplayID`.
12. **MIT licensed** — the popular open-source replacements are GPL-3.
13. **281 tests**, a fixture-tested plist decoder covering corrupt and malicious input, a written threat model, hardened runtime with empty entitlements.
14. **An honest limitations list.** Rare in this category, and a selling point.

---

## 4. Tier 0 — Baseline parity

Without these, the claim to be a copy of the real Dock is weak. **All six are shipped.** What is left of the gap to the real Dock now starts at Tier 1.

### 4.1 Auto-hide and edge reveal — done

**Shipped.** `DockRevealController` per panel, a one-point trigger panel per hidden bar, `autohide-delay` on the reveal and `autohide-time-modifier` on the slide. Recorded in `Docs/ARCHITECTURE.md` under *Auto-hide*. The gap and the approach as written below are kept for the record.

**Gap.** When the user turns auto-hide on, the real Dock hides and Dockyard's bars stay. `autoHide` is decoded but used in exactly one place, `Packages/DockKit/Sources/DockKit/Displays/SystemDockLocator.swift:36`, purely to work out which display hosts the real Dock. `autoHideDelay` and `autoHideTimeModifier` are decoded and unused.

**Approach.** Do not use a global mouse monitor. Place a one-pixel trigger panel along the relevant screen edge, take `mouseEntered`, wait `autoHideDelay`, then slide the bar in over `autoHideTimeModifier`. Reverse on exit.

**Cost.** Idle CPU zero — tracking areas are push-based. One small extra panel per display, under 0.5 MB. The reveal delay and the slide animation are the two timers that §8.2 Rule 1 already permits by name. No architectural violation.

**Risk.** Low. This is planned behaviour that was deferred, not new ground.

### 4.2 Hiding over full-screen applications — done

**Shipped.** Full-screen coverage is detected from `CGWindowList` on every space change and puts that display's bar into the hiding mode 4.1 built, so the bar reveals over the full-screen window instead of disappearing until the space ends. `FullScreenDetector`, recorded in `Docs/ARCHITECTURE.md` under *Full-screen spaces*. The gap and the approach as written below are kept for the record.

**Gap.** `.fullScreenAuxiliary` in `Packages/DockKit/Sources/DockKit/Panel/DockPanel.swift` keeps the bar above a full-screen app. The real Dock hides. Take a window full-screen today and Dockyard's bar sits on top of it.

**Approach.** Listen to `NSWorkspace.activeSpaceDidChangeNotification`, then query `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` for a window on that display at layer 0 whose frame matches the screen frame. Window *contents* require Screen Recording; window *bounds* do not, so this stays permission-free.

**Cost.** Idle zero. One `CGWindowList` query per space change, 1–3 ms, tied to a user action. No resident growth.

**Risk.** Low. Add a test-matrix row for "Displays have separate Spaces" turned off, where the semantics differ.

### 4.3 Reduce Transparency and Increase Contrast — done

**Shipped.** Both are read from `NSWorkspace` and refreshed from `accessibilityDisplayOptionsDidChangeNotification`; the bar turns opaque and takes a full-strength outline. Recorded in `Docs/ARCHITECTURE.md` under *Reduce Transparency and Increase Contrast*, including the admission that the colours are semantic rather than photographed. The gap and the approach as written below are kept for the record.

**Gap.** There is not one reference to `accessibilityDisplayShouldReduceTransparency` in the tree. With the setting on, the real Dock turns opaque and Dockyard keeps its glass backdrop — an immediately visible mismatch, and an accessibility failure.

**Approach.** Read `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`, observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, and fall back to an opaque material in `DockMaterial`.

**Cost.** Zero. One observer and one boolean. The best effort-to-value ratio on this list.

### 4.4 Dropping onto the Trash — done

**Shipped.** `FileManager.trashItem(at:resultingItemURL:)`, refused when the drag's source will not offer a move, with a snapshot rebuild afterwards so the Trash artwork changes on every bar. Recorded in `Docs/ARCHITECTURE.md` under *Drag and drop*. The gap and the approach as written below are kept for the record.

**Gap.** Drag-onto-app works (`Packages/DockKit/Sources/DockKit/Rendering/DockContentViewDragging.swift`); dropping on the Trash does not. It is the real Dock's most-used drop target.

**Approach.** `FileManager.default.trashItem(at:resultingItemURL:)`. No permission needed for the user's own files. The existing snapshot rebuild already refreshes the Trash's empty/full state afterwards.

**Cost.** Zero idle. One syscall at drop time.

### 4.5 Launch bounce — done

**Shipped.** `launchanim` is decoded, `LaunchActivityObserver` brackets a launch between `willLaunchApplicationNotification` and `didLaunchApplicationNotification`, and the tile answers with an additive `CAKeyframeAnimation` inside a panel that grows to hold the icon at its peak. Recorded in `Docs/ARCHITECTURE.md` under *Launch bounce*. Two deviations from the approach below are worth keeping: the start signal is `willLaunch`, not `didLaunch`, because `didLaunch` **is** the app reporting that it finished launching and the two would have collapsed into one instant; and the bounce is kept out of `DockSnapshot` entirely, since a launch changes no tile's geometry and would otherwise push a generation through the diff twice per launch. The gap and the approach as written below are kept for the record.

**Gap.** `launchanim` is never read. Applications launch without the icon bouncing, which is the main reason the bar feels inert next to the real one.

**Approach.** Add `launchanim` to `DockPreferencesDecoder`, then drive a `CAKeyframeAnimation` on the tile layer's `position.y` from `NSWorkspace.didLaunchApplicationNotification`, stopping when the app reports finished launching.

**Cost.** Idle zero. A single animating layer, cheaper per frame than magnification, which animates the whole row. Rules 4, 5, and 6 are unaffected. Measured against the shipped version: two window resizes per launch, one when the panel grows and one when it shrinks, and nothing at all when no application is launching.

**Known limit.** An application that is neither pinned nor already running has no tile to bounce until it is running. The real Dock creates the tile at launch time; Dockyard's tiles come from the Dock's own state, which does not list a process that has not registered yet. Recorded in the README's limitations list.

### 4.6 Dock Settings in the separator menu — done

**Shipped.** The separator answers a right-click with **Dock Settings…** and nothing else. `DockTile.providesMenu` splits the question of having a menu from `isInteractive`, which stays false for the separator: it has a menu, no label, no click, and no drop target. Recorded in `Docs/ARCHITECTURE.md` under *Tile menus*. The gap and the approach as written below are kept for the record.

**Gap.** Right-clicking the real Dock's separator offers Turn Hiding On/Off, Turn Magnification On/Off, Position on Screen, and Dock Settings. Dockyard's separator is not interactive at all — `DockTile.isInteractive` returns false for it.

**Approach.** Add only **Dock Settings…**, opening `x-apple.systempreferences:com.apple.Desktop-Settings.extension`. The other three write `com.apple.dock` and violate G11; leave them out.

**Cost.** Zero.

---

## 5. Tier 1 — Behavioural depth

Noticeable in daily use. **All five are shipped.** What is left of the gap to the real Dock now starts at Tier 2.

### 5.1 Stack popups: fan, grid, and list — done

**Shipped.** `FolderStackReader` reads the folder off the main thread, `DockStackGeometry` resolves the mode and the geometry, and `DockStackController` presents it in the tile menu's own balloon. `arrangement` was added to the decoder alongside `displayas` and `showas`, so a folder sorted *by Kind* in the real Dock opens sorted by kind here. Recorded in `Docs/ARCHITECTURE.md` under *Stacks*, including two deviations worth keeping: the fan is the Dock's arc in the menu's balloon rather than the Dock's tapered sheet, which no public API produces; and a folder larger than the screen — or than the reader's 200-entry ceiling — ends in a row that opens the rest in Finder rather than being silently truncated. The permission consequence was carried into `README.md` and `Docs/SECURITY-MODEL.md` in the same change, as the note below demanded. The gap and the approach as written below are kept for the record.

**Gap.** `FolderPresentation` with `displayAs` and `showAs` is fully modelled in `Packages/DockCore/Sources/DockCore/Model/DockTile.swift` and never rendered. A folder tile just opens Finder — `Packages/DockKit/Sources/DockKit/Panel/DockPanelController.swift:117`. It is the one place where a solved model has no counterpart in the UI.

**Approach.** A transient `NSPanel` on click, `FileManager.contentsOfDirectory`, `NSWorkspace.icon(forFile:)`. `DockMenuBackdrop` and `DockMenuBalloon` are reusable for the chrome. Deallocate on close.

**Cost.** Idle zero; the popup exists only while open. Folder icons are transient — charge them to the existing `NSCache` `totalCostLimit` so resident growth stays at zero. Read the directory off the main thread.

**This one changes the permission story.** `~/Downloads`, `~/Documents`, and `~/Desktop` are TCC-protected. The first time a stack over one of them is opened, macOS shows *"Dockyard would like to access files in your Downloads folder."* That directly affects the README's claim of no permission prompts in the default configuration. The prompt is triggered by the user's own click, which makes it defensible, but `README.md` and `Docs/SECURITY-MODEL.md` must be updated in the same change. Do not ship this quietly.

### 5.2 Spring loading — done

**Shipped.** The hover is measured inside `draggingUpdated` with one cancellable `Task.sleep`, on the system's own `com.apple.springing.enabled` and `com.apple.springing.delay` rather than a setting of Dockyard's. A running application comes forward, a folder's stack opens, and a folder still takes no drop — recorded in `Docs/ARCHITECTURE.md` under *Spring loading* and in the README's limitations, since accepting the drop would mean choosing between a move and a copy on the user's behalf. The gap and the approach as written below are kept for the record.

**Gap.** Hovering a dragged file over an app icon should bring that app forward; over a folder it should open the stack.

**Approach.** Measure hover duration inside `draggingUpdated`. The timer is a Rule 1 exception on the same grounds as the auto-hide delay: user-initiated and short-lived.

**Cost.** Idle zero. A single timer that lives only for the duration of an active drag.

### 5.3 Reserving screen space — done, opt-in

**Shipped.** Off by default, behind *Keep windows clear of the bar* in Settings, with the warning beside it and disabled until Accessibility is granted. `DisplayCoordinator` publishes one `ReservedArea` per bar and `ScreenSpaceReserver` keeps standard windows clear of it, coalescing every AX move and resize into one evaluation 150 ms after the gesture ends and never acting while a mouse button is down. `ScreenSpaceGeometry` is a pure function over rectangles and carries the tests. Three decisions are worth keeping: a window is only ever **shrunk**, with the far edge left where the user put it, because a window that jumps is a window they have to find again; a window that would end up smaller than 160 × 120 pt is left alone rather than crushed; and turning the setting off does not put windows back, because nothing recorded where they were. Recorded in `Docs/ARCHITECTURE.md` under *Reserved screen space*, in `Docs/SECURITY-MODEL.md` as the one Accessibility write that is not the direct result of a click, and in the README's limitations. The gap and the approach as written below are kept for the record.

**Gap.** Maximized windows pass under the bar. The real Dock has its area removed from `visibleFrame`; a third-party app cannot do that. One replacement ships this as an option, so a competitor is differentiating on it.

**Approach.** Accessibility is the only route: resize overlapping windows through `kAXSizeAttribute` and observe `kAXWindowMovedNotification` and `kAXWindowResizedNotification`.

**Cost — the most expensive item on this list.** Idle stays at zero because nothing polls, but AX callbacks arrive dozens of times per second while a window is being dragged. Without coalescing this becomes measurable non-idle CPU. Act only on move and resize *end*, with roughly 150 ms of coalescing, and never mid-drag. One `AXObserver` per application, on infrastructure that `MinimizedWindowObserver` already establishes, so marginal resident growth is under 2 MB.

**Risk — high.** This crosses the "not a window manager" non-goal in §1.3 and will fight Rectangle, Magnet, and Stage Manager. It should not ship without being off by default, behind its own Settings toggle, with an explicit warning.

### 5.4 Keyboard access and VoiceOver — done

**Shipped.** One `NSAccessibilityElement` proxy per tile, built the first time an assistive client asks for `accessibilityChildren` and kept in step by the layout pass that already runs, carrying the tile's label, what kind of tile it is, whether the app is running or hidden, a press action, and a show-menu action wired to the same balloon menu a right-click opens. Keyboard focus is granted rather than assumed: the panel returns false from `canBecomeKey` at rest, *Focus Dock* in the status menu flips it for one session, and arrow keys, type-select, Return, and Escape work from there. **The real Dock's Ctrl+F3 is deliberately not reproduced** — a global shortcut means a global key monitor, and the security model promises the app never watches keystrokes. Recorded in `Docs/ARCHITECTURE.md` under *Keyboard access and VoiceOver*. The gap and the approach as written below are kept for the record.

**Gap.** There is no `NSAccessibility` call anywhere in the tree, and the panel sets `canBecomeKey` to false. The real Dock takes focus with Ctrl+F3, navigates with arrow keys, supports type-select, and is fully labelled for VoiceOver. For a public open-source release this is a credibility item as much as a functional one.

**Approach.** Because rendering is layer-based rather than view-based, tiles need `NSAccessibilityElement` proxies. Build them lazily, only once an assistive client attaches. Keyboard focus is separate work: a non-activating panel has to be allowed to become key temporarily.

**Cost.** Idle zero, and zero memory while VoiceOver is off thanks to lazy construction. With VoiceOver on, a small object per tile, under 100 KB. No runtime cost; moderate implementation complexity.

### 5.5 Localization — done

**Shipped.** Every user-visible string goes through `NSLocalizedString` against its own module's bundle — menu titles and stack text in `DockKit`, the Finder and Trash labels in `DockCore`, the status menu and Settings in the app target — with English and Turkish tables in each. `.lproj` tables rather than a String Catalog, because SwiftPM compiles the former and the app is assembled by `Scripts/make-app.sh` from `swift build` output, which already copies each package's resource bundle. Recorded in `Docs/ARCHITECTURE.md` under *Localization*. The gap and the approach as written below are kept for the record.

**Gap.** No `NSLocalizedString` anywhere. "Show in Finder", "Quit", and "Force Quit" are hardcoded English. The real Dock speaks the user's language.

**Approach.** A String Catalog covering menu titles, Settings, and balloon text.

**Cost.** Zero at runtime. A few KB of bundle per language.

---

## 6. Tier 2 — Deep fidelity

These required an architectural decision, not just implementation. **All four are shipped.** What is left of the gap to the real Dock is now Tier 3, which is where it should stay.

### 6.1 Reading the Dock's own accessibility tree — done

**Shipped.** `DockItemInspector` walks the Dock's single `AXList` off the main thread, `DockItemStore` keeps it current, and `DockItemMatching` folds the result into the snapshot: order from the item indices, badges from `AXStatusLabel`. Recorded in `Docs/ARCHITECTURE.md` under *The Dock's own item list*. The badge's own artwork was calibrated against the real Dock from screenshots rather than designed: diameter, centre, digit size, and fill colour are measured constants, and the first attempt — a white-ringed capsule that widened for a second digit — was visibly not the Dock's badge. Three further findings are worth keeping. Matching is on `AXURL` rather than on `AXTitle`, which the probe showed is present on every application, folder, and URL item — titles are the fallback, and are matched inside one subrole. A list that matches fewer than half the eligible tiles is discarded whole, so a change in Apple's tree costs the badges and nothing else. And **the cost line below was wrong**: `AXObserverAddNotification` on the Dock's application element supports `kAXCreated` and `kAXUIElementDestroyed` and returns `kAXErrorNotificationUnsupported` (-25207) for `kAXValueChanged`, `kAXTitleChanged`, `kAXLayoutChanged`, and for the same notifications registered per item. Items appearing and disappearing are push-based; a badge changing is not, so badges are re-read on the events the app already has and a badge is prompt rather than instant. That is in the README's limitations. The gap and the approach as written below are kept for the record.

**Gap and payoff.** One mechanism buys three things: **badge counts** (Mail's red 12), **exact tile order** including recents, which turns `TileOrdering` from an inference into something verifiable against ground truth, and **minimize order**, currently a documented limitation in the README.

**Approach.** `AXUIElementCreateApplication(dockPID)`, walk `AXChildren`, read each dock item's `AXTitle` and `AXStatusLabel`. Attach an `AXObserver` to the Dock process for changes.

**Cost.** Idle zero — entirely push-based. Badge changes are infrequent even for Mail and Messages. One additional `AXObserver`, under 1 MB. It falls under the Accessibility permission that already exists and optional, so **it requires no new permission**.

**Risk.** `AXStatusLabel` is undocumented and can break across Dock versions. Apply the same defensive posture as `DockPreferencesDecoder`: degrade to nil gracefully, cover it with fixtures. When it breaks, badges disappear and nothing crashes.

**This is the single highest-return fidelity item on the list.**

### 6.2 App Exposé on click-and-hold — done

**Shipped.** A cancellable 0.65 s sleep started in `mouseDown` opens the tile's window list in the balloon a right-click already uses, `DockTileMenuBuilder.windowItems` builds the rows, and a hold that opened the list swallows the click that follows. Recorded in `Docs/ARCHITECTURE.md` under *App Exposé*. One deviation: the real Dock's two-finger swipe up is deliberately not wired, because the gesture's sign depends on `isDirectionInvertedFromDevice` and could not be verified without a trackpad test, and a menu that opens on the opposite swipe is the self-opening UI this project refuses. The gap and the approach as written below are kept for the record.

**Gap.** Press and hold a running app's icon and the real Dock shows that app's windows. Two-finger swipe up on a trackpad does the same.

**Approach.** A real thumbnail grid needs Screen Recording — do not build it. Open the window list menu instead. `AppMenuStore`'s `appMenu.windows` and `DockMenuContentView` are already in place; only the trigger is new.

**Cost.** Zero. Reuse of existing infrastructure plus a click-and-hold timer.

### 6.3 Drag-to-reorder as a local override — done, opt-in

**Shipped.** Off by default, behind *Let me drag tiles into my own order* in Settings. `TileOrderOverride` is a list of `DockTileID` persistence keys applied as a permutation over `TileOrdering`'s output inside the snapshot build, and `DockReorderPolicy` is the pure function that decides which drags are legal. Recorded in `Docs/ARCHITECTURE.md` under *Local tile order*. Three decisions are worth keeping: the separator seals two regions and nothing crosses it, the Trash is always last, and a drop on a fixed tile is refused rather than absorbed; a key the override does not know inherits the position of the tile it follows, so an app pinned later appears where the Dock put it instead of at the end; and a tile cannot be dragged out of the bar to remove it, because removal is exactly the write to `com.apple.dock` this design exists to avoid. The gap and the approach as written below are kept for the record.

**Gap.** Tiles cannot be reordered. Persisting an order means writing `com.apple.dock` and restarting the Dock, which violates G11 and the no-subprocess ban at once.

**Approach.** A third path: keep the order in Dockyard's own preferences and apply it as a permutation layer over `TileOrdering`'s output. The real Dock is never touched.

**Cost.** Zero at runtime — a map lookup inside the snapshot build.

**Risk.** It breaks G3, that every bar shows the real Dock's state, in the specific dimension of order: the bars would be ordered differently from the real Dock. Ship only as opt-in, labelled explicitly as applying to Dockyard's bars alone.

### 6.4 Stage Manager geometry — done, and the answer was to do nothing

**Shipped as a measurement.** The approach below was implemented — `GloballyEnabled` and `AutoHide` from `com.apple.WindowManager`, an inset in `DockPanelGeometry` — put on screen, and then **removed**, because the premise it rests on is false. With Stage Manager on and the Dock moved to the left edge, `CGWindowListCopyWindowInfo` puts WindowManager's own thumbnail windows at the **right** edge of a display that does not host the Dock, while the Dock sits on the left of another one. macOS places the strip opposite the Dock's edge, on every display. A Dockyard bar mirrors the Dock's edge, so the strip is always on the far side of the screen from it and there is nothing to avoid. Shipping the inset made this visible in the worst way: the bar floated 96 points off the edge while the strip sat on the other side. Recorded in `Docs/ARCHITECTURE.md` under *Stage Manager*, with the window-bounds evidence, and in `PLAN.md` as L9. The one real interaction left is a caveat in the README: a bottom bar can cover the lowest thumbnail of a left-edge strip on a display macOS does not know has a dock, and moving the bar sideways would not fix that.

**Gap.** Stage Manager reserves a strip along the left edge and the bar's geometry ignores it. Recorded as L9 in `PLAN.md` and still untested.

**Approach.** Read `GloballyEnabled` from the `com.apple.WindowManager` domain and inset in `DockPanelGeometry`.

**Cost.** Zero. One more preference read on the existing watcher.

---

## 7. Tier 3 — Specific and contested

### 7.1 Live tile content, such as a ticking Clock

**Status.** Already a documented limitation. Calendar has a bespoke renderer in `Packages/DockCore/Sources/DockCore/Icons/CalendarTileRenderer.swift`; Clock stays a static bundle icon.

**Cost.** It **violates Rule 1 directly**, since it needs a timer. The cheapest form is a `DispatchSourceTimer` at a 60-second period with 10 seconds of leeway, alive only while a Clock tile is visible and the display is awake: roughly 0.01–0.02% CPU and one wakeup per minute, against a budget of two per second.

**Recommendation.** Technically almost free, but it punctures the project's clearest rule. Either leave it alone or document it as the one sanctioned exception in `PLAN.md`. Leaving it alone is the better trade: the no-timers claim is worth more than a ticking second hand.

### 7.2 Progress bars and download indicators

No public API exposes another application's dock tile progress, and the accessibility tree is not reliable for it either. Keep it out of scope and keep it in the limitations list.

### 7.3 Live window previews on hover

The most popular open-source replacement's headline feature, and what its stars are for. It needs ScreenCaptureKit, therefore Screen Recording, therefore continuous GPU and CPU work — ending both the no-prompts claim and the 0.0% idle claim in one change.

**Recommendation.** Do not build it. Being the app that coexists cleanly with it is a better position than being a worse copy of it.

### 7.4 Distribution

Signed and notarized releases, a Homebrew cask, and a screenshot or GIF in the README. Zero runtime cost, and more effect on adoption than the other eighteen items combined. Today the only route is building from source.

---

## 8. Performance ledger

| # | Feature | Idle CPU | Idle wakeups | RSS | Rule violation |
|---|---|---|---|---|---|
| 4.3 | Reduce Transparency — done | 0 | 0 | 0 | — |
| 4.4 | Trash drop — done | 0 | 0 | 0 | — |
| 4.6 | Dock Settings item — done | 0 | 0 | 0 | — |
| 5.5 | Localization — done | 0 | 0 | 0 | — |
| 6.4 | Stage Manager geometry — measured, nothing to do | 0 | 0 | 0 | — |
| 4.1 | Auto-hide and reveal — done | 0 | 0 | one empty window per hidden bar | Permitted by Rule 1 |
| 4.2 | Hiding over full-screen — done | 0 | 0 | 0 | — |
| 4.5 | Launch bounce — done | 0 | 0 | 0 | Two window resizes per launch |
| 5.2 | Spring loading — done | 0 | 0 | 0 | Permitted by Rule 1 |
| 6.2 | App Exposé — done | 0 | 0 | 0 | — |
| 6.3 | Local reordering — done | 0 | 0 | 0 | G3, opt-in |
| 5.4 | VoiceOver and keyboard — done | 0 | 0 | 0 while off | — |
| 5.1 | Stack popups — done | 0 | 0 | ~0 resident | **TCC prompt, on the user's click** |
| 6.1 | Dock accessibility tree — done | 0 | 0 | +1 MB | **Badges are not push-based** |
| 5.3 | Screen space reservation — done | 0 idle, one evaluation per gesture | 0 | +2 MB while on | **Non-goal, opt-in** |
| 7.1 | Ticking Clock | +0.02% | +0.017/s | 0 | **Rule 1** |

Everything from Tier 0 through Tier 2 shipped without breaking the idle budget, because all of it is either push-based or bound to a user action. The one correction to the table as first written is 6.1: the Dock's accessibility tree pushes item creation and destruction but not badge changes, so a badge is re-read on the events the app already has rather than the instant an application sets it. The alternative was a timer, which Rule 1 refuses. Total resident growth is around 5 MB — 37 MB becomes roughly 42 MB, still under the 60 MB budget.

The real cost is not performance. It is four policy decisions, three from Tier 1 and one from Tier 2: the TCC prompt that stack popups introduce (5.1), screen-space reservation drifting into window-manager territory (5.3), and a ticking Clock puncturing the no-timers rule (7.1). The fourth is local reordering (6.3), which makes the bars disagree with the real Dock about order — a deliberate dent in G3, off by default and labelled as applying to Dockyard's bars alone. The first two are now taken — the prompt is raised only by the user's own click on their own folder, and the reservation is off by default behind an explicit warning — and both are stated in `README.md` and `Docs/SECURITY-MODEL.md` rather than left implicit. The ticking Clock is still declined. The other twelve items are free.

## 9. Suggested order

~~4.1~~ → ~~4.3~~ → ~~4.5~~ → ~~4.4~~ → ~~4.6~~ → ~~4.2~~ → ~~5.1~~ → ~~5.2~~ → ~~5.3~~ → ~~5.4~~ → ~~5.5~~ → ~~6.1~~ → ~~6.2~~ → ~~6.4~~ → 7.4, with ~~6.3~~ last.

Tier 1 was taken in its own order rather than the interleaved one above: 6.1 was left for Tier 2 so that the whole of Tier 1 could ship together, and 5.3 shipped with the rest rather than last, because being opt-in and warned about is what makes it safe to ship, not being late. Tier 2 then went in the order suggested here, 6.3 last for the same reason it was put last: it is the only one of the four that makes a bar disagree with the Dock.

What remains is 7.4, distribution — signing, notarization, a Homebrew cask, and a screenshot in the README — which is now the highest-value item left on the whole document, and the three declined items in Tier 3.

## Sources

Market data gathered 2026-08-27 from the vendors' own pages and repositories. The real Dock's settings are enumerated from [Apple's own documentation](https://support.apple.com/en-me/guide/mac-help/mchlp1119). Competitor feature claims are their marketing copy, not verified by testing.
