# Tab Groups

Tab Groups is a native macOS menu bar utility for grouping windows from different apps into a shared screen area.

## Use

1. Open Tab Groups and enable Accessibility access for it in System Settings.
2. Hold Shift and drag one app window onto another to create or extend a group.
3. Select a tab in the floating strip to raise that window at the group’s shared size and position.
4. Resize the active window to update the group bounds. Remove a tab with its close button or by dragging it away from the strip.

Groups are saved in `~/Library/Application Support/TabGroups/groups.json`. On launch or wake, Tab Groups reconnects to matching windows that are already open. It does not launch apps or reopen documents. If a saved window cannot be matched uniquely, assign it from the Groups window.

Some apps restrict Accessibility window operations. When an app rejects the requested bounds, Tab Groups reports the accepted size and uses it for the group. The app requires macOS 14 or later.

## Project

Open `TabGroups.xcodeproj` in Xcode. The `TabGroups` scheme includes focused persistence and window matching tests.
