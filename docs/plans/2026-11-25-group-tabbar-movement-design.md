# Group Tab Bar Movement Design

## Goal

Make a grouped window container move only when its browser-like tab bar is dragged. The app windows and visible outline must move together; dragging an individual app window must not reposition the group.

## Current behavior

`TabStripPanel` and `GroupFramePanel` are separate panels. `GroupCoordinator` currently watches Accessibility move and resize events and treats whichever member moved as the group's new bounds, then moves the other members to match. This is the source of the current window-driven group movement.

## Design

Use the tab bar as the only move handle. Make its background draggable at the AppKit panel level while keeping tab selection and remove buttons interactive. When the tab panel moves, calculate its position delta, update the persisted `TabGroup.bounds`, apply the translated bounds to every live member, and move the outline and tab panel to the matching positions.

Treat `TabGroup.bounds` as authoritative outside a tab-bar drag. When Accessibility reports that an app window has moved or resized independently, restore that member to the group's stored bounds instead of allowing the member to redefine the group. Programmatic updates caused by a tab-bar drag must not be interpreted as independent user movement.

Keep tab selection behavior intact: selecting a tab raises that app window and places it at the group bounds. Keep the current topbar above the container and preserve the current tab labels and remove controls.

## Failure behavior

If an app rejects a requested position or size, keep the stored group bounds and report the app limitation using the existing status message pattern. Other group members continue moving when possible. A missing member is skipped until the existing restore flow reconnects it.

## Validation

Build the macOS app and manually check: tab-bar dragging translates all grouped windows and the outline; dragging an app window does not move the group; tab selection still switches the visible app; remove-tab still works; drag interaction does not prevent clicking tab controls.
