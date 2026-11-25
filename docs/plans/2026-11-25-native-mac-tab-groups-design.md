# Native Mac Tab Groups Design

## Goal

Build a small native macOS utility that groups windows from different apps into tabbed groups. The selected window is raised into a shared screen position and size; resizing it updates the group bounds. Groups remain recorded when the Mac sleeps and after the utility restarts.

## User experience

- Select accessible app windows in a group builder and click Group.
- Use the first selected window’s existing position and size as the group’s shared bounds.
- Show a visible frame around the shared window area and a compact tab strip above it.
- Click a tab to raise that app window in the same screen position and size.
- Resize the active app window to update the shared bounds used by the group.
- Drag a tab away from the strip to remove that window from the group.
- Keep groups and their member references on disk, so the utility can reconnect to still-open windows after sleep or restart.

## Architecture

Implement a native Swift/AppKit menu bar utility. A lightweight panel draws the tab strip. Accessibility APIs inspect and control other apps’ windows by reading and setting their position and size and raising the selected window. The utility does not embed other apps’ content in its own window; the group is a shared screen rectangle with overlapping app windows.

Store group names, tab order, member app identities, window matching hints, display association, and shared bounds in the app’s Application Support directory. During normal sleep, the apps and their windows remain open; on wake, rescan and reconnect to their windows and reapply the saved bounds if needed. After a restart, reconnect only when matching windows are already available. Do not launch apps or reopen documents automatically.

## Permissions and limitations

The utility needs macOS Accessibility permission to inspect, move, resize, and raise windows from other processes. Explain how to grant permission if it is missing. Some apps do not expose standard accessibility window controls or enforce their own size constraints. When multiple windows in the same app have similar titles, matching after a restart may be ambiguous. Keep the utility’s stored group and allow the user to reassign an unmatched tab.

## Data flow

1. The user selects two or more windows in the group builder and clicks Group.
2. The utility resolves the selected windows through Accessibility, then creates a group record using the first selected window’s bounds.
3. It moves and resizes the selected windows to the shared bounds, then displays a frame and tab strip over that area.
4. A tab click raises the selected window and applies the group’s shared position and size.
5. A resize of the selected window updates the group bounds and is saved locally.
6. On wake or utility launch, scan available windows, reconnect saved members, and restore the tab strip and bounds.

## Alternatives considered

1. **Selection-based group builder with a visible frame and tabs (chosen):** avoids pointer hit-testing and keeps app windows under Accessibility control.
2. **Drag-to-group:** fewer setup steps, but it depends on identifying both windows under a moving pointer and has proven unreliable in practice.
3. **A host window that embeds app content:** AppKit child windows attach app-managed NSWindow instances; the general utility instead draws a frame around third-party windows and controls them through Accessibility.

## Error handling

- If Accessibility permission is absent, show a short explanation and a button that opens the relevant System Settings pane.
- If a window cannot be moved or resized, keep the group record, show the tab as unavailable or constrained, and let the user retry or remove it.
- If a saved member cannot be matched after restart, preserve the tab record and offer reassignment rather than silently dropping it.
- If the active window closes, select another available member; if no members remain, remove the empty group.

## Verification approach

The implementation should cover persistence encoding/decoding and window matching with focused unit tests. Manual checks should cover grouping two apps, tab switching, shared resizing, sleep/wake, missing permission, and relaunch/restart reconnection. Per workspace instructions, do not run build, test, lint, typecheck, or other verification commands unless the user explicitly requests them.
