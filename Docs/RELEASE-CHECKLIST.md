# Release checklist

Run every section on real hardware before tagging. Record the results in the release notes, including the machine and macOS version.

## 1. Build and static checks

- [ ] `swift build` clean, no warnings
- [ ] `(cd Packages/DockCore && swift test)` green
- [ ] `(cd Packages/DockKit && swift test)` green
- [ ] `Scripts/lint-forbidden-apis.sh` all `ok`
- [ ] `swiftlint --strict` clean
- [ ] `swift-format lint --strict --recursive Packages Dockyard` clean
- [ ] `Dockyard/Dockyard.entitlements` still an empty dictionary
- [ ] Version bumped in `Dockyard/Info.plist`

## 2. Signing and notarization

- [ ] `Scripts/build-release.sh` with `DEVELOPER_ID_APPLICATION` set
- [ ] `Scripts/notarize.sh build/Dockyard-<version>.dmg` succeeds and staples
- [ ] `spctl -a -vvv` accepts the app
- [ ] `codesign -d --entitlements :-` shows nothing granted
- [ ] SHA-256 recorded in the release body

## 3. Display configuration matrix

| Scenario | Expected | Pass |
|---|---|---|
| Built-in only | One bar, unless it hosts the real Dock and suppression is on | [ ] |
| Built-in plus external, external primary | Bar on both, real Dock's screen suppressed per setting | [ ] |
| Built-in plus external, built-in primary | Same | [ ] |
| Clamshell, external only | Exactly one bar, on the external | [ ] |
| Lid opened from clamshell | Second bar appears within budget, correct position | [ ] |
| Display disconnected while the cursor is inside its bar | No crash, no stuck magnification, other bar unaffected | [ ] |
| Display reconnected | Bar returns, per-display settings preserved | [ ] |
| External placed to the left of built-in, negative x | Both bars correctly positioned | [ ] |
| External placed above built-in | Both bars correctly positioned | [ ] |
| Resolution changed on one display | That bar repositions and rescales, other untouched | [ ] |
| Scaled resolution change | Icons re-rasterize at the correct scale, no blurring | [ ] |
| Retina plus non-Retina pair | Each bar crisp on its own display | [ ] |
| Mirrored displays | One bar, not two stacked | [ ] |
| Three or more displays | One bar each, all in sync | [ ] |
| iPad as a Sidecar display | Bar appears, no crash | [ ] |
| Display sleep and wake | Bars restored correctly | [ ] |
| System sleep and wake | Full reconcile, correct state | [ ] |
| Rapid unplug and replug | Debounce prevents flicker, at most one reposition | [ ] |

## 4. Dock state matrix

| Scenario | Expected | Pass |
|---|---|---|
| App added to the real Dock | Appears on all bars within 150 ms | [ ] |
| App removed | Disappears from all bars | [ ] |
| Apps reordered | Order updates, layers reused not rebuilt | [ ] |
| `tilesize` slider moved | All bars resize live and stay aligned with the real Dock | [ ] |
| Magnification toggled | All bars adopt it | [ ] |
| Orientation changed to left or right | Bars follow | [ ] |
| Auto-hide turned on | Every bar slides out and stays out, the real Dock's screen unaffected | [ ] |
| Pointer to the edge of a display with a hidden bar | Bar reveals after `autohide-delay`, not before | [ ] |
| Pointer leaves a revealed bar | Bar slides back out, magnification does not stick | [ ] |
| Pointer touches the edge and leaves before the delay | Nothing reveals | [ ] |
| `autohide-time-modifier` changed | Slide speed follows on the next reveal | [ ] |
| Auto-hide turned back off | Every bar slides in and stays in | [ ] |
| Click at the very edge of a display with a hidden bar | The one-point trigger takes it, nothing else moves | [ ] |
| Auto-hide on with the dock on the left or right | Reveals from that edge, not the bottom | [ ] |
| Auto-hide on, display disconnected while a bar is revealed | No stuck panel, no orphaned trigger | [ ] |
| Animate opening applications turned off | No tile bounces on any bar | [ ] |
| Animate opening applications turned back on | Bounces return on the next launch | [ ] |
| `show-recents` toggled | Recents section appears and disappears | [ ] |
| Dock moved to another display by the cursor gesture | Suppression follows the real Dock | [ ] |
| User restarts the Dock themselves | Dockyard recovers without a restart | [ ] |

## 5. Application state matrix

| Scenario | Expected | Pass |
|---|---|---|
| Launch a pinned app | Indicator appears, no duplicate tile | [ ] |
| Launch a non-pinned app | New tile after the pinned section | [ ] |
| Quit an app | Indicator clears or tile disappears | [ ] |
| App crashes or is force-quit | Same as quit, no stale tile | [ ] |
| Hide an app | Tile dims | [ ] |
| Switch frontmost app | Active state updates on all bars | [ ] |
| App updated in place | Icon refreshes | [ ] |
| App deleted while pinned | Tile drops out, click is inert, no crash | [ ] |
| App on an ejected volume | Graceful degradation | [ ] |
| 50 or more tiles | No layout overflow off-screen | [ ] |
| Click a tile | Target app activates and Dockyard does not take focus | [ ] |
| Right-click a tile | Menu correct for running and non-running | [ ] |
| Right-click the separator | One item, Dock Settings, and it opens Desktop & Dock | [ ] |
| Right-click a spacer | Nothing opens | [ ] |
| Launch a pinned app from a Dockyard tile | The icon bounces on every bar until the app is up, then stops | [ ] |
| Launch the same app from Spotlight or Finder | Same bounce, same displays | [ ] |
| Launch with the dock on the left or right | The icon bounces away from that edge, not upwards | [ ] |
| Launch an app while the pointer magnifies its tile | The magnified icon clears the panel, nothing is clipped | [ ] |
| Launch an app that fails or is killed on the way up | The bounce stops, no tile is left animating | [ ] |
| Launch a background agent or helper | Nothing bounces and no bar resizes | [ ] |
| Launch an app while its display's bar is hidden | Nothing is left mid-bounce when the bar reveals | [ ] |
| Drag a file onto an app tile | File opens with that app | [ ] |
| Full-screen app on one display | That display's bar hides, other display's bar unaffected | [ ] |
| Pointer to the edge under a full-screen app | Bar reveals over the full-screen window | [ ] |
| Leaving full screen | Bar returns, unless auto-hide is on | [ ] |
| Space switched away from a full-screen space | Bar returns on that display | [ ] |
| Zoomed, not full-screen, window | Bar stays put; a maximized window is not full screen | [ ] |
| Reduce Transparency on | Every bar turns opaque, light and dark | [ ] |
| Increase Contrast on | The bar's outline strengthens | [ ] |
| Both turned back off | The material and the measured hairline return | [ ] |
| File dragged onto the Trash | File moves to the Trash, tile switches to full artwork on every bar | [ ] |
| Locked or read-only file dragged onto the Trash | Refused without a crash, nothing is deleted | [ ] |
| File dragged onto the Trash from a copy-only source | Drop is refused, original untouched | [ ] |
| Click a pinned folder set to Fan, Grid, and List in turn | Each mode opens as the real Dock's does, tail on the tile | [ ] |
| Click a folder set to Automatic, with few and with many items | Fan for the small one, grid for the large one | [ ] |
| Click a folder sorted by Name, Date Added, and Kind | Order matches the real Dock's stack | [ ] |
| Click a subfolder inside a stack | Walks into it in place, Escape closes the whole stack | [ ] |
| Click a stack over `~/Downloads` on a clean install | The system asks once, and refusing leaves a row saying so | [ ] |
| Click a folder with more items than the screen can hold | Last row offers the rest in Finder and opens it | [ ] |
| Click an empty folder | One row saying so, no empty balloon | [ ] |
| Open a stack, then click a tile on another display | Stack dismisses, the other bar is unaffected | [ ] |
| Hold a dragged file over a running app tile | App comes forward, drag continues | [ ] |
| Hold a dragged file over a folder tile | Stack opens, drag continues, nothing is moved | [ ] |
| Same with springing turned off in the Finder | Nothing springs | [ ] |
| Focus Dock from the status menu, then arrow keys and Return | Focus walks the tiles, Return opens, Escape returns focus | [ ] |
| Type the first letters of a tile's name while the bar is focused | Focus jumps to that tile | [ ] |
| VoiceOver on, cursor into a bar | Each tile is announced with its name and state, VO-space activates it | [ ] |
| Keep windows clear of the bar on, window dragged over a bar | Window shrinks once, after the drag ends, and not during it | [ ] |
| Same with the dock on the left or right | Window loses width on that edge and keeps the opposite one | [ ] |
| Same with a window smaller than the minimum after shrinking | Window is left alone | [ ] |
| Keep windows clear turned back off | Nothing further is resized, windows are not restored | [ ] |
| Keep windows clear on with auto-hide on, or over a full-screen space | Nothing is reserved on that display | [ ] |
| System language set to Turkish | Menus, Settings, and stack text are Turkish; tile names stay the system's | [ ] |
| Space switch | Bars stay put | [ ] |

## 6. Robustness

| Scenario | Expected | Pass |
|---|---|---|
| Corrupt or empty `com.apple.dock` | Bars render with just the Trash, error logged, no crash | [ ] |
| Malformed URL in one entry | That tile dropped, others render | [ ] |
| Entry pointing outside an app bundle | Not launchable, not rendered | [ ] |
| `tilesize` set to 0 or 10000 | Clamped | [ ] |
| Login-time launch storm | Coalesced, no per-launch rebuild | [ ] |
| Cursor swept across the bar at maximum speed | No dropped frames, no runaway animation | [ ] |
| Window placed under a bar, beside the bar, at either end of the edge | Every part of it the bar does not cover stays clickable | [ ] |
| Same with a left or right dock, window's traffic lights beside the bar | Close, minimise, and zoom still hit | [ ] |
| Cursor parked in the space the magnified bar reaches but the resting bar does not | The click lands in the window behind, not in the panel | [ ] |

## 7. Performance

- [ ] `Scripts/benchmark.sh` over 60 s idle: CPU, memory, wakeups within budget
- [ ] `lsof -nP -a -p <pid> -i` empty
- [ ] Instruments Core Animation during a magnification sweep within frame budget
- [ ] Activity Monitor energy impact 0.0 after 10 minutes idle
- [ ] Numbers pasted into the release notes with the hardware and macOS version
