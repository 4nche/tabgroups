# Tab Groups

Tab Groups is a native macOS menu bar utility for grouping windows from different apps into a shared screen area.

## Use

1. Open Tab Groups and enable Accessibility access for it in System Settings.
2. Choose **Create a Group…** from the menu bar and select at least two windows.
3. Click **Group**. The first selected window sets where the group sits; the other windows are moved and resized to match.
4. A bar spans the top of the group with one tab per window. Click a tab to switch windows; its close button removes that window from the group.
5. Drag the bar to move the whole group. Moving or resizing any window in the group does the same, whether you drag it or a window manager such as Rectangle Pro repositions it.

The bar sits directly above the group's windows. When a window is snapped against the top of the screen, the bar takes the top 36 points of that area and the window sits just below it.

Groups are saved in `~/Library/Application Support/TabGroups/groups.json`. On launch or wake, Tab Groups reconnects to matching windows that are already open. It does not launch apps or reopen documents. If a saved window cannot be matched uniquely, assign it from the Groups window.

Some apps restrict Accessibility window operations. When an app rejects the requested bounds, Tab Groups reports the accepted size and uses it for the group. The app requires macOS 14 or later.

## Project

Open `TabGroups.xcodeproj` in Xcode. The `TabGroups` scheme includes tests for persistence, window matching and the group geometry rules.

### Local Accessibility permission

For local development builds, select a stable **Team** under the app target’s **Signing & Capabilities** in Xcode. Without a development signing identity, Xcode signs the app ad hoc; macOS can then treat each rebuilt binary as a different app and leave the old Accessibility toggle visible while the new build is untrusted. After switching signing identities, remove the old Tab Groups entry from **System Settings → Privacy & Security → Device Control and Data Access**, run the newly signed app, enable it, and relaunch it.
