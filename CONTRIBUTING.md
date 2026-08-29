# Contributing to Dockyard

Thanks for considering a contribution. This document covers the setup, the two hard rules, and what a reviewable pull request looks like.

## Setup

Requirements: macOS 14 or later to run and Xcode 26 or later to build. The deployment target stays macOS 14, but `DockBackdrop` references `NSGlassEffectView`, which only exists in the macOS 26 SDK, so an older Xcode cannot compile it.

```bash
swift build                            # app target plus both packages
Scripts/make-app.sh debug              # assemble build/Dockyard.app and run it
(cd Packages/DockCore && swift test)
(cd Packages/DockKit  && swift test)
Scripts/lint-forbidden-apis.sh
```

There is no Xcode project file. The repository is a root SwiftPM package for the app target plus two local packages under `Packages/`. `Scripts/make-app.sh` wraps the built executable in an `.app` bundle, which is required because the agent needs `LSUIElement` and a bundle identifier.

If you use Xcode, open the folder itself (`File > Open`) rather than looking for a `.xcodeproj`.

## The two hard rules

**1. No timers for state observation.** Every state Dockyard cares about has a push notification: `com.apple.dock.prefchanged` plus a filesystem watcher for preferences, `NSWorkspace.shared.notificationCenter` for applications, `CGDisplayRegisterReconfigurationCallback` for displays. Polling is what turns a menu bar agent into a battery complaint. `Scripts/lint-forbidden-apis.sh` fails the build on `Timer.scheduledTimer`, `DispatchSourceTimer`, `NSTimer`, and `CVDisplayLink`. Debouncing with a cancellable `Task.sleep` is fine and is how the existing watchers coalesce. One state genuinely has no push notification: the Dock's accessibility tree posts nothing when a tile's badge changes, so badges are re-read on the Dock and application events the app already receives. A badge that is prompt rather than instant is the price of this rule, and the right trade.

**2. Nothing from the forbidden list.** Also enforced by the same script:

| Banned | Why |
|---|---|
| `Process`, `posix_spawn`, `NSTask`, `system()` | No subprocess execution, ever |
| `NSAppleScript`, `OSAScript`, Apple Event descriptors | Would require an entitlement and a TCC prompt |
| `URLSession`, `Network`, sockets, reachability | Enforces the zero-network guarantee mechanically |
| `killall`, `kill()`, raw signals | Quit goes through `NSRunningApplication.terminate()` |
| Force unwrap, `try!`, `as!` | Crash prevention in an always-running agent |
| `@unchecked Sendable` | Swift 6 strict concurrency is respected, not bypassed |
| `dlopen`, `dlsym`, `NSClassFromString` | No private API, no dynamic lookup |

If you believe an exception is genuinely required, open an issue before writing the code.

## Design constraints worth knowing before you start

- **`DockCore` must not import window code.** No `NSWindow`, no `NSView`, no `CALayer`. That is what keeps it testable without a display attached, and it is the part of the project most likely to be published as a standalone package.
- **Everything crossing an actor boundary is a `Sendable` value type.** `NSRunningApplication` is converted to `RunningApplicationState` at the observation boundary and never stored in a snapshot.
- **Geometry lives in `DockGeometry` and is pure.** Coordinate conversion lives in `CoordinateSpace` and nowhere else. Cocoa is bottom-left origin anchored to the primary display; CoreGraphics is top-left. Mixing them by hand is the single most common source of "the bar is on the wrong screen" bugs, so all conversion goes through those two functions and they are unit-tested against negative-origin arrangements.
- **Diff before publishing and diff before rendering.** `didActivateApplicationNotification` fires on every app switch. Most of those changes are invisible, and they must therefore be free.
- **Appearance constants come from the system.** If you need a number, read it from `com.apple.dock` first. If the Dock does not expose it, add it to `DockMetrics` with a value derived by `Scripts/calibrate.swift` and record how you derived it in the commit message, including what you measured it against.
- **The code carries no comments.** Names, small functions, and tests carry the explanation; prose that belongs to a reader lives in `Docs/`. Please match that.

## Tests

- `DockCore` changes need tests. Preference decoding is fixture-driven: add a captured `com.apple.dock` plist under `Packages/DockCore/Tests/DockCoreTests/Fixtures/` and assert against it. Never make a test depend on the machine's real Dock or real filesystem; inject a `TileEnvironment`.
- Geometry and magnification changes need tests. They run headless, and they are cheap.
- Rendering and panel code is not coverage-gated, because a meaningful test needs a display. Say in the pull request which rows of the matrix in `Docs/RELEASE-CHECKLIST.md` you exercised by hand.

## Pull requests

- One logical change per pull request.
- Note any display configuration you tested on, including macOS version and whether an external display was attached.
- CI runs both test suites, builds the app, runs the forbidden-API lint, and checks that the entitlements file still grants nothing.

## Performance testing is manual, honestly

GitHub Actions macOS runners are headless. `NSScreen.screens` there is not representative and magnification cannot be measured, so CI covers correctness only. Performance is a pre-release checklist item run on real hardware with `Scripts/benchmark.sh` and the Instruments configurations described in `Instruments/README.md`, and the numbers go in the release notes. We would rather state that plainly than ship a meaningless automated check.
