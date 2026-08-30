# Limitations

The complete list. The ones you are most likely to notice on the first day are repeated in the README; everything else lives here, including the ones you would only reach in an edge case.

These are real and are not going away. Where a limitation exists because of a rule the project sets for itself — no timers, no subprocesses, no permission it does not need, never writing `com.apple.dock` — the rule is named, so you can judge the trade for yourself.

## Contents

- [What it fundamentally is](#what-it-fundamentally-is)
- [Fidelity gaps](#fidelity-gaps)
- [Behaviour](#behaviour)
- [Windows, space, and other apps](#windows-space-and-other-apps)
- [Writes it will not make](#writes-it-will-not-make)

## What it fundamentally is

- **Dockyard renders a copy, not an extension.** No public or private API extends the real Dock to a second display. Fidelity work closes the gap; it does not eliminate it.
- **It cannot be sandboxed,** because reading another application's preference domain and resolving icons at arbitrary paths are both sandbox-blocked. It is therefore not on the Mac App Store.
- **Reading `com.apple.dock` is not a documented contract.** Apple can change the format. The decoder is defensive and fixture-tested, and `com.apple.dock.prefchanged` has a filesystem-watcher fallback underneath it.

## Fidelity gaps

- **Minimize animations do not fly into Dockyard's bars.** The genie effect targets the system Dock's own window.
- **Minimized window tiles are drawn, not captured.** The real Dock shows the window's own miniaturized image. Every route to a window's pixels is behind Screen Recording, so Dockyard draws a window card badged with the app's icon instead. Two windows of one app are told apart by their menu and their position, not by their contents.
- **Minimize order is right for most windows, not for every window.** With Accessibility granted, the region takes the order from the Dock's own item list. A window is matched to its dock item by title, and a few applications — Chrome among them — publish a different title to the window server than they report over Accessibility, so those windows fall back to the order they were seen minimized in. Without the grant, only the windows minimized while Dockyard is running are in the Dock's order.
- **Clock does not tick.** The Dock draws Calendar and Clock through each app's dock tile plugin, loaded inside the Dock process. Dockyard will not load third-party code, so it draws Calendar's date itself and leaves Clock as its static bundle icon; a live second hand would need a timer, which the project bans.
- **Click and hold shows a window list, not window previews.** The real Dock's App Exposé draws each window; every route to a window's pixels is behind Screen Recording, which Dockyard does not ask for. The real Dock's two-finger swipe up is also not wired, because the gesture's direction cannot be verified without a trackpad test and a menu that opens on the wrong swipe is worse than no gesture.
- **The fan is the Dock's arc, not the Dock's sheet.** The real fan is a tapered sheet narrowing toward the tile; Dockyard draws the same balloon as a tile menu with the rows following the arc. No public API produces the taper.
- **The separator's menu carries one item, not four.** Right-click the real Dock's separator and it offers Turn Hiding On/Off, Turn Magnification On/Off, Position on Screen, and Dock Settings…. The first three write `com.apple.dock`, so Dockyard offers the fourth alone rather than an item that would silently do nothing.

## Behaviour

- **The Trash tile updates on app activation, not instantly.** `~/.Trash` needs Full Disk Access to watch, which Dockyard does not request. Its entry count is readable without any permission, so the state is recomputed whenever the snapshot rebuilds, which in practice means as soon as Finder comes forward.
- **Clicking a running app brings its existing windows forward wherever they already are,** which may be a different display from the bar you clicked. This is exactly what the real Dock does; moving windows between displays is a window-manager feature and an explicit non-goal.
- **An application with no tile of its own does not bounce while it launches.** The real Dock creates a tile the moment a launch begins; Dockyard's tiles come from the Dock's own state, which does not list a process that has not registered yet, so an app that is neither pinned nor already running appears when it is running rather than bouncing its way in.
- **Badges are prompt, not instant, and need Accessibility.** They come from the Dock's own item list, and the Dock's accessibility tree posts no notification when a badge changes — only when items appear and disappear. A badge is therefore re-read on every Dock or application event the app already sees, which in practice is seconds, and never on a timer.
- **A stack is a snapshot of its folder, not a live view.** It reads the directory when you open it, like the real Dock's own stack, and nothing watches the folder while it is closed. A folder larger than the screen ends in a row that opens the rest in Finder, and a folder past 200 entries counts the remainder into the same row.

## Windows, space, and other apps

- **A bar does not push windows aside unless you ask it to.** The real Dock's strip is removed from `visibleFrame` and no third-party app can do that, so by default a maximized window passes under the bar. *Keep windows clear of the bar* in Settings resizes the overlapping windows through Accessibility instead, after a move or resize settles; it is off by default, it will fight Rectangle, Magnet, and Stage Manager, and turning it off does not put the windows back.
- **Stage Manager's strip and the bars do not fight, and Dockyard does nothing about it.** macOS puts the strip on the edge opposite the Dock, on every display, so it is never on the same edge as a bar that mirrors the Dock. The one leftover: with the Dock at the bottom, the strip runs to the bottom of a display that has no real Dock, so a bar can cover its lowest thumbnail. Moving the bar sideways would not fix that and would put it somewhere the real Dock never sits.
- **Mirrored displays** get one bar, on the mirror-set primary, not one per mirrored display.

## Writes it will not make

- **Drag-to-reorder never reaches the real Dock.** *Let me drag tiles into my own order* in Settings reorders Dockyard's bars and keeps the order in Dockyard's own preferences; the real Dock keeps its own, because changing that would mean writing `com.apple.dock` and restarting the Dock. It is off by default, a drag cannot cross the separator or move the Trash, and a tile the Dock adds later appears where the Dock puts it until you drag it. Unlike the real Dock, a tile cannot be dragged out of the bar to remove it, since removal is exactly the write this avoids.
- **A folder tile takes no drop.** Dragging a file onto it springs the stack open rather than moving the file in, because accepting the drop would mean choosing between a move and a copy for you.
- **The keyboard reaches the bar from the status menu, not from Ctrl+F3.** The real Dock's shortcut is global, and a global shortcut needs a global key monitor. Dockyard will not watch keystrokes, so *Focus Dock* is a menu item.
