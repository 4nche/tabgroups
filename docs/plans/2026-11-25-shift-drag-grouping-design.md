# Shift-Drag Grouping Design

Approved in conversation on 2026-11-25.

## Intent

Group two windows by hand: hold Shift, drag one window onto another, let go.

## Behaviour

- Shift held at the click: the window under the pointer at that moment is the one to group. It is read live then, not looked up from an earlier list.
- Nothing happens unless that window actually moves, so Shift-dragging inside an app (selecting text, constraining a shape) never groups.
- While dragging with Shift held, the window under the pointer (other than the dragged one) is the target and gets a blue outline. Releasing Shift removes the outline and cancels.
- On release with Shift held:
  - neither window grouped: a new group forms where the target sits; the dragged window is the selected tab.
  - target is in a group: the dragged window joins that group as the selected tab.
  - dragged window is in a group: the target joins that group.
  - both in different groups: the dragged window's group is merged into the target's.
  - both in the same group: nothing.

## Approaches

1. Match windows by position against a list taken at mouse-down (the retired first attempt). The list goes stale as the window moves. Rejected.
2. Ask Accessibility for the window under the pointer at the click, keep that handle, and resolve the target fresh from the window server's front-to-back order. Chosen.

## Builder's calls

- Movement threshold 8pt; target lookups at most every 80ms and cached per window for the length of one drag.
- Shift-dragging a group's own tab bar does not group; drag a member window by its title bar instead.
- The outline is 3pt accent blue with a faint blue fill. The user asked for this outline explicitly.

## Validation

Unit tests for the two pure rules (which window is under a point; what a drop does). Hand check for the drag itself.
