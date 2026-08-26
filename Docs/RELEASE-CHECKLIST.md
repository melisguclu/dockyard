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
| Drag a file onto an app tile | File opens with that app | [ ] |
| Full-screen app on one display | Other display's bar unaffected | [ ] |
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
