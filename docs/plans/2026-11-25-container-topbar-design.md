# Container Top Bar Design

Approved in conversation on 2026-11-25.

## Intent

A group should feel like one window. A full-width bar sits on top of each group with one tab per app. The bar is the handle, and any move of the group, however it is caused, takes the whole container along. Rectangle Pro shortcuts and plain window drags must work with the group instead of being undone.

## Goals

- A bar spanning the full width of the group, one tab per member, close control per tab.
- Dragging the bar moves the container and every member.
- A member moved or resized by anything (mouse drag, Rectangle Pro, the app itself) makes the group adopt that rectangle. The bar follows live; the other members follow when the move settles.
- The bar stays on screen when the group is snapped to a screen edge.

## Non-goals

- Dragging tabs to reorder or to pull a window out of a group.
- Launching apps or reopening documents on restore.
- Changing the saved file format in a way old files cannot load.

## Anti-goals

- Snapping a moved window back to its old place.
- A bar that jitters, lags behind a drag, or blocks when one app hangs.

## Approaches

1. Bar floating above the group (today). The bar leaves the screen when a window is snapped to the top edge. Rejected.
2. Bar inside the container, windows beneath it. The container rectangle is bar plus content; members are placed in the content part. Chosen: it survives edge snaps and the bar never overlaps a member window.
3. Bar overlaid on the top of each window. Covers the apps' own title bars and toolbars. Rejected.

## Design

- Container rectangle = the group's stored bounds. The bar takes the top `barHeight` (36pt); members get the rest.
- When a member reports a new rectangle from outside, the container becomes that rectangle grown upward by the bar height, so a plain drag or a manual resize never shrinks the window. If that would push the bar above the screen's visible top (a Rectangle snap to the top edge), the container is clamped to the visible top and the member is nudged down by the bar height instead. This nudge is accepted.
- Our own moves are told apart from outside moves by comparing a member's reported rectangle with the rectangle it actually took the last time we placed it, within a small tolerance. Using the rectangle it took, not the one we asked for, keeps apps that limit their own size from looping.
- A member is not repositioned while a mouse button is held, so a window being dragged is never fought.
- Bar drag is handled in AppKit using screen mouse coordinates, so the moving panel cannot distort the drag. Tabs and close buttons stay clickable. During the drag the bar and the visible member move live; hidden members move when the drag ends.
- Each member keeps a live Accessibility handle for the session, so a changing window title cannot lose it. Title and position matching is only used to reconnect after launch or wake.
- Accessibility calls get a short messaging timeout so a hung app cannot freeze the bar.
- Geometry rules (content rectangle, adopting a member rectangle, telling echoes from outside moves, coordinate conversion) live in pure code with unit tests.
- Styling follows the user's rules: weight at most medium, no outlines around controls, colour for emphasis, no press scaling.

## Builder's calls

- Bar height 36pt, tolerance 3pt, settle delay about 120ms.
- Saved bounds from older files are read as the content rectangle and grown upward by the bar height on first restore, clamped to the screen.
- The thin outline panel around the group is dropped; the bar plus the windows read as one container without it.

## Validation

Unit tests for the geometry rules. Build, then check by hand: bar drag moves everything; Rectangle Pro shortcuts on a member move the group; dragging a member moves the group; tabs switch; close removes a tab.
