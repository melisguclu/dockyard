# Security Policy

## Reporting a vulnerability

Report privately through GitHub's **Report a vulnerability** button on the Security tab of this repository. Do not open a public issue for a security report.

Expected response: an acknowledgement within 72 hours, an assessment within 7 days, and a fix or a documented decision within 30 days for anything confirmed. Credit is given in the release notes unless you ask otherwise.

## Scope

In scope:

- Code execution reachable through a crafted `com.apple.dock` entry or a crafted filename or label.
- Any network traffic originating from Dockyard. The project claims zero, so a single packet is a valid report.
- Any write outside `~/Library/Preferences/com.dockyard.app.plist`.
- Anything that modifies, disables, or restarts the system Dock.
- Privilege escalation, injection into the Dockyard process, or use of a permission the app claims not to request.
- A missing or incorrect signature, entitlement, or notarization state on a published release artifact.

Out of scope:

- The fact that Dockyard runs unsandboxed with the user's privileges. This is documented, unavoidable for the core feature, and the reason the app is not on the Mac App Store.
- Reading `com.apple.dock`, which is another application's preference domain. It is permitted for an unsandboxed process running as that user.
- Denial of service that requires an attacker who can already write the user's preference domain, since such an attacker can already do worse directly.
- Cosmetic differences from the real Dock.

## What the project guarantees mechanically

`Scripts/lint-forbidden-apis.sh` runs in CI and fails the build on any occurrence of subprocess execution, AppleScript, networking APIs, signals to other processes, observation timers, force unwrapping, force casts, `@unchecked Sendable`, or dynamic symbol lookup. The entitlements file is committed, grants nothing, and is verified during release.

## What it cannot guarantee

Installing Dockyard means trusting the maintainers and the build pipeline. Signing, notarization, published SHA-256 hashes, pinned CI actions, and zero runtime dependencies reduce that trust surface. They do not remove it.
