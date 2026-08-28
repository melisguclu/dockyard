# Security model

Dockyard is an always-running unsandboxed agent, which earns a real threat model rather than a privacy paragraph.

## Threat model

| Asset | Threat | Mitigation |
|---|---|---|
| The user's app list and usage patterns | Exfiltration | Zero network code. No `URLSession`, no sockets, no telemetry. Verifiable with `lsof -nP -a -p "$(pgrep -x Dockyard)" -i` and by reading the source. CI fails on the API class. |
| Arbitrary code execution | A hostile process writes a malicious `com.apple.dock` entry that Dockyard then launches | Strict validation of every entry. Note that a process able to write that domain can already do worse directly, so this is defence in depth, not a claimed security boundary. |
| Supply chain | A malicious binary published under the project name | Signed and notarized builds, published SHA-256, pinned CI action SHAs, zero runtime dependencies, signed tags. |
| Privilege escalation | The app requesting more access than it needs and becoming a target | No TCC permission is requested at launch or in the background. Accessibility is optional, off until the user grants it from Settings, and used for tile menus, minimized-window tiles, and the opt-in window clearing. Opening a stack over a protected folder can raise the system's own file-access prompt, on the user's click. No helper tool, no root, no privileged operation. |
| Local tampering | Modification of the installed bundle | Hardened Runtime with library validation left enabled, Gatekeeper, stapled notarization. |

## Permission posture

The core feature requires **no** TCC prompt:

- Reading `com.apple.dock`: permitted for an unsandboxed process reading its own user's preference domain.
- `NSWorkspace.runningApplications`: no permission.
- `NSWorkspace.icon(forFile:)`: no permission for paths the user can already read.
- Launching and activating applications: no permission.
- `CGWindowListCopyWindowInfo` bounds, layer, and owner name: no permission. Window **titles** and image capture are gated there, and Dockyard reads neither through that API.
- Reading two PNG files from `/System/Library/CoreServices/Dock.app/Contents/Resources/` for the Trash artwork: no permission. These are world-readable system files, read as image data only, never executed, and behind a fallback chain because the layout is undocumented.
- `getattrlist` for the Trash's entry count: no permission. Listing `~/.Trash` would need Full Disk Access, which is why Dockyard reads only the count and never the names.
- Drawing windows: no permission.
- Reading a pinned folder's contents to open its stack: no permission for an ordinary folder, and a **TCC prompt** for `~/Downloads`, `~/Documents`, and `~/Desktop`. See below.
- Reading `com.apple.springing.enabled` and `com.apple.springing.delay` from the global domain for the spring-loading delay: no permission.

Screen Recording is never requested.

## The one prompt the app can raise: a stack over a protected folder

Clicking a folder tile opens its stack, which is a directory listing. `~/Downloads`, `~/Documents`, and `~/Desktop` are TCC-protected, so the first click on a stack over one of them makes macOS ask *"Dockyard would like to access files in your Downloads folder."* The terms:

- **Nothing is read until the user clicks.** No folder is read at launch, on a snapshot rebuild, or while a stack is closed. There is no watcher on any folder and no pre-warming.
- **A directory listing, and nothing else.** The names, the kinds, the dates the sort needs, and whether each entry is a directory. No file is opened, no contents are read, and nothing is written.
- **Refusing costs one row.** With the prompt declined the stack shows a row saying the folder cannot be read. Every other feature is unaffected.
- **Nothing is persisted.** The listing lives in memory for as long as the stack is open and is released with the panel.

The rest of the app still asks for nothing, which is why the README says "no permission prompts for anything the bar does on its own" rather than "no permission prompts".

## Accessibility, the one optional permission

Three features need the Accessibility API, so it is the only TCC permission Dockyard can hold: tile menus that list a running app's windows, its own commands — *New Window*, *Next Track* — and its recent documents, the minimized-window tiles between the separator and the Trash, and the opt-in *Keep windows clear of the bar*. The terms are deliberately narrow:

- **Off by default and never prompted for.** The grant is requested only from a button in Settings that says what it is for. `AXIsProcessTrusted()` is checked before every read, and with no grant the tile menu is byte-for-byte what it was before the feature existed and the minimized-window region is absent.
- **Read-only, except for what the user clicks and the one setting they turn on.** The app reads the target's window titles, its menu-bar item titles, their identifiers, shortcuts, and enabled state, and the entries in the submenus of its File menu — which is where recent documents live, so recently opened file *names* are read. It writes nothing and presses nothing until the user picks a row, at which point exactly one `AXPress`, `AXRaise`, or `AXMinimized` clear is sent to the element that row named.
- **One setting writes to other applications' windows, and it is off by default.** *Keep windows clear of the bar* sets `kAXPosition` and `kAXSize` on standard windows that overlap a bar's strip, after a move or resize settles and never while a mouse button is down. It is the only write in the app that is not the direct result of a click, it does nothing at all until the user turns it on, and the Settings switch carries the warning. Nothing else about a window is read for it: role, subrole, minimized and full-screen state, position, and size, which is the same surface `CGWindowList` already exposes without any permission.
- **No keystroke or event synthesis.** No `CGEvent` posting, no global key monitor, no reading of text fields, documents, or web content. The menu bar and the window list are the whole surface. This is also why the bar is focused from a menu item rather than from the real Dock's own Ctrl+F3: a global shortcut would mean watching every keystroke on the machine. The `AXObserver`s the app registers are per application and carry window notifications only — miniaturized and deminiaturized always, and moved, resized, and created while window clearing is on — with nothing on keyboard or focus.
- **Nothing is persisted.** Window titles, command titles, and window geometry live in memory for as long as the app is running and are dropped when it exits. A minimized window's title is on screen the whole time it is minimized, which is the same exposure the real Dock's tooltip already gives it. They are never written to disk, and there is no network code to send them anywhere.

An Accessibility grant is genuinely powerful — it would let this process drive any app on the system — so the honest statement is that the user is trusting the binary, not a sandbox. The compensating controls are that the grant is optional, the features are worth exactly one menu and one row of tiles, and the code that uses it is confined to `Packages/DockCore/Sources/DockCore/AppMenu/` and `Packages/DockCore/Sources/DockCore/Windows/`.

## Why not sandboxed

App Sandbox blocks reading another application's preference domain and blocks icon resolution for paths outside the container. The core feature is impossible in a sandboxed build, so the app is not eligible for the Mac App Store. That is a real limitation, stated in the README rather than buried.

Compensating controls: Hardened Runtime with **no** entitlements granted. The entitlements file is committed as an empty dictionary so anyone can verify that the shipped binary asks for nothing:

| Entitlement | Granted | Reason |
|---|---|---|
| `com.apple.security.cs.allow-jit` | No | No JIT |
| `com.apple.security.cs.allow-unsigned-executable-memory` | No | No dynamic code |
| `com.apple.security.cs.disable-library-validation` | No | No plugins; keeps injection out |
| `com.apple.security.cs.allow-dyld-environment-variables` | No | Prevents `DYLD_INSERT_LIBRARIES` injection |
| `com.apple.security.cs.debugger` | No | Not a debugger |
| `com.apple.security.automation.apple-events` | No | No AppleScript, ever |
| `com.apple.security.network.client` | No | No network access |
| `com.apple.security.device.*` | No | No hardware access |

```bash
codesign -d --entitlements :- /Applications/Dockyard.app
codesign -dvvv --verbose=4 /Applications/Dockyard.app
spctl -a -vvv /Applications/Dockyard.app
```

## Input validation

The Dock preference plist is treated as untrusted input even though it normally comes from the system, because it can be corrupt, stale, hand-edited, or written by another process. Every rule below corresponds to a test in `TileValidationTests`:

1. Every cast is conditional. A shape mismatch drops that one tile rather than aborting the read.
2. `_CFURLString` must parse as a URL. File URLs only for `file-tile` and `directory-tile`; `http` and `https` only for `url-tile`, which is opened and never executed.
3. File URLs are resolved through symlinks and standardized before any check, so `..` segments cannot survive.
4. A launchable tile must have a `.app` extension **and** exist **and** load as a bundle **and** have a `CFBundleExecutable`. A bare executable or script at an arbitrary path is never launched.
5. Labels are display text only. They are trimmed, flattened to a single line, and clamped to 256 characters so a pathological label cannot produce an enormous layout.
6. Unknown `tile-type` values are dropped rather than defaulted to `file-tile`.
7. Numeric appearance values are clamped to sane ranges.

Symlink resolution and existence checks are injected through `TileEnvironment`, which keeps the tests hermetic and makes the validation rules themselves testable.

**Time-of-check to time-of-use.** Validating a path and later launching it is inherently racy. The mitigation is that launching goes through `NSWorkspace.openApplication(at:)`, which performs its own Launch Services validation, signature check, and Gatekeeper evaluation. Dockyard never executes a path directly, and it has no code path that can exec anything at all.

## Prohibited constructs

Enforced by `Scripts/lint-forbidden-apis.sh` in CI, not by convention: subprocess execution, AppleScript and Apple Events, networking APIs, `killall` and raw signals, observation timers, force unwrapping, `try!`, `as!`, `@unchecked Sendable`, and dynamic symbol lookup. The quit and force-quit menu actions use `NSRunningApplication.terminate()` and `forceTerminate()`, which go through the documented API rather than sending a signal.

## Data handling

- Nothing leaves the machine. No telemetry, no analytics, no crash reporting, no update check in v1.
- Persisted state is limited to Dockyard's own preferences: per-display enable flags and the suppression toggle, under Dockyard's own bundle identifier. No usage history, no launch timestamps.
- No Keychain use, because there are no secrets.
- Logging goes through `os.Logger`. Application paths and bundle identifiers are marked `.private`, so they are redacted in system logs unless a developer explicitly enables private data logging on their own machine.
- If an auto-updater is ever added it must use HTTPS only, verify signatures on both the feed and the archive, be disable-able, and the network entitlement must be called out in the release notes as a security-relevant change.

## What this cannot promise

- Dockyard runs unsandboxed with the user's full privileges. Installing it means trusting the maintainers and the build pipeline. The controls above shrink that trust surface; they do not remove it.
- Reading `com.apple.dock` is reading another application's preference domain. It is permitted and it is not a security boundary violation, but it is also not a stable contract.
- `com.apple.dock.prefchanged` is not documented API. The filesystem fallback exists precisely because it may stop working.
