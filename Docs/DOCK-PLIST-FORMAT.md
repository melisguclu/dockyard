# The `com.apple.dock` preference format

Reference documentation for the macOS Dock's preference domain, as consumed by `DockCore`. This is a description of an undocumented format observed across macOS 14 to 26. It is not an Apple contract and can change.

Domain: `com.apple.dock`. Backing file: `~/Library/Preferences/com.apple.dock.plist`.

**Read it through `CFPreferences`, not by parsing the file.** `cfprefsd` caches domains per process, so `UserDefaults` can return a value from before another process modified the domain with no reliable invalidation hook. `CFPreferencesAppSynchronize` discards the cached copy and forces a re-read. Parsing the file directly is worse still: it bypasses managed preferences and the fallback chain, and it races with the atomic rename that preference writes use.

## Tile arrays

| Key | Type | Contents |
|---|---|---|
| `persistent-apps` | array of dict | Pinned applications, in display order |
| `persistent-others` | array of dict | Pinned folders, stacks, and files, shown after the separator |
| `recent-apps` | array of dict | Recently used applications, shown when `show-recents` is true |

**Finder and the Trash are not in any of these arrays.** Both are built into the Dock, Finder always first and the Trash always last, and both must be synthesized. There is also always a separator before the Trash region, whether or not `persistent-others` has anything in it.

Selecting the Trash's empty or full artwork means knowing whether `~/.Trash` has anything in it, and that directory is TCC-protected: `FileManager.contentsOfDirectory` and `open(_:O_EVTONLY)` both fail with "Operation not permitted" without Full Disk Access. `getattrlist` with `ATTR_DIR_ENTRYCOUNT` returns the entry count with no permission at all, which is what Dockyard uses. There is no way to *watch* the directory without the permission, so the count has to be re-read on some other event.

## Entry structure

```xml
<dict>
    <key>GUID</key>
    <integer>1234567890</integer>
    <key>tile-type</key>
    <string>file-tile</string>
    <key>tile-data</key>
    <dict>
        <key>bundle-identifier</key>
        <string>com.apple.Safari</string>
        <key>file-label</key>
        <string>Safari</string>
        <key>file-data</key>
        <dict>
            <key>_CFURLString</key>
            <string>file:///Applications/Safari.app/</string>
            <key>_CFURLStringType</key>
            <integer>15</integer>
        </dict>
        <key>file-type</key>
        <integer>41</integer>
        <key>file-mod-date</key>
        <integer>...</integer>
        <key>parent-mod-date</key>
        <integer>...</integer>
        <key>dock-extra</key>
        <false/>
        <key>is-beta</key>
        <false/>
    </dict>
</dict>
```

`_CFURLStringType` of 15 indicates an absolute file URL. Other values exist; validate the URL itself rather than trusting the field.

URL tiles keep their URL under `tile-data.url._CFURLString` rather than `file-data`, and label it `label` rather than `file-label`.

## `tile-type` values

| Value | Meaning | How Dockyard handles it |
|---|---|---|
| `file-tile` | Application or file | Launchable only if it resolves to an existing `.app` bundle with a `CFBundleExecutable` |
| `directory-tile` | Folder or stack | Opened in Finder; must resolve to an existing directory |
| `url-tile` | Web URL | Opened with `NSWorkspace.open(_:)`; `http` and `https` only, never treated as executable |
| `spacer-tile` | Full-width spacer | Rendered as a tile-width gap |
| `small-spacer-tile` | Half-width spacer | Rendered as a half-tile gap |
| `flex-spacer-tile` | Flexible spacer | Rendered as a tile-width gap in v1 |
| anything else | Unknown | Tile dropped, logged at debug level |

## Folder-specific `tile-data` keys

| Key | Type | Values |
|---|---|---|
| `showas` | integer | 0 automatic, 1 fan, 2 grid, 3 list |
| `displayas` | integer | 0 stack, 1 folder |
| `arrangement` | integer | 1 name, 2 date added, 3 date modified, 4 date created, 5 kind |
| `preferreditemsize` | integer | -1 for automatic |

## Global appearance keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `tilesize` | real | 48 | Base tile edge length in points |
| `largesize` | real | 128 | Magnified tile edge length |
| `magnification` | bool | false | Magnification enabled |
| `orientation` | string | `bottom` | `bottom`, `left`, `right` |
| `autohide` | bool | false | Auto-hide enabled |
| `autohide-delay` | real | 0.5 | Seconds before the Dock reveals |
| `autohide-time-modifier` | real | 1.0 | Animation duration multiplier |
| `show-process-indicators` | bool | true | Running indicator dots |
| `show-recents` | bool | true | Show the recent applications section |
| `minimize-to-application` | bool | false | Minimized windows fold into the app tile |
| `mineffect` | string | `genie` | `genie`, `scale`, `suck` |
| `launchanim` | bool | true | Bounce on launch |
| `static-only` | bool | false | Show only running apps |
| `mru-spaces` | bool | true | Rearrange Spaces by most recent use |
| `expose-group-apps` | bool | — | Mission Control grouping |

A key that the user has never changed is absent from the domain entirely, and the Dock falls back to its built-in default. A decoder must supply the defaults above rather than treating absence as an error. Values can also arrive as strings rather than numbers, so accept both.

## Ordering

The order the Dock renders, which `TileOrdering` reproduces:

1. `persistent-apps` in array order. A pinned app that is running gets an indicator rather than a second tile.
2. Running applications with `activationPolicy == .regular` that are not pinned, in launch order.
3. `recent-apps` when `show-recents` is true, excluding anything already shown.
4. A separator, if there is anything after it.
5. One tile per minimized window when `minimize-to-application` is false, in the order the windows were minimized.
6. `persistent-others` in array order.
7. The Trash.

Matching a running application to a pinned entry is done on bundle identifier first and on canonicalized bundle path second, because some applications report no bundle identifier.

Minimized windows do not come from this domain at all; they are read from each application over the Accessibility API, which is why step 5 is present only when that grant is held. Their placement was confirmed against the Dock's own accessibility tree, where `AXMinimizedWindowDockItem` sits between `AXSeparatorDockItem` and `AXTrashDockItem`. Whether they precede or follow `persistent-others` was not confirmable on a machine whose `persistent-others` is empty; Dockyard places them first, which keeps a pinned stack adjacent to the Trash.

## Change notification

`com.apple.dock.prefchanged` is posted on the distributed notification center when the Dock mutates its own preferences. It is not documented API. Layer a watcher on the **directory** `~/Library/Preferences` underneath it as a fallback: preference writes are atomic, the inode changes on every write, and a file-level watcher therefore stops firing after the first one.
