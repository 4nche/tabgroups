# Group Tab Bar Movement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the tab bar the only handle that moves grouped app windows and their container.

**Architecture:** Add a move callback to the tab strip panel that reports its AppKit frame delta. The coordinator translates the group's persisted bounds and applies the new bounds to every matched member, then refreshes the tab and outline panels. Accessibility move/resize events from individual member windows restore that member to the authoritative group bounds, while coordinator-driven moves are guarded from feedback.

**Tech Stack:** Swift, AppKit, SwiftUI, macOS Accessibility API.

---

### Task 1: Add tab bar drag movement reporting

**Files:**
- Modify: `TabGroups/TabStrip/TabStripPanel.swift`
- Modify: `TabGroups/TabStrip/TabStripCoordinator.swift`

**Steps:**
1. Give `TabStripPanel` a move callback carrying the panel's old and new AppKit origins.
2. Implement the panel's user drag handling so background/titlebar space can move it while its SwiftUI tab buttons remain clickable.
3. Forward movement deltas through `TabStripCoordinator.show` to the group coordinator.
4. Keep the group outline and tab panel placement derived from `TabGroup.bounds`.

### Task 2: Make group bounds authoritative

**Files:**
- Modify: `TabGroups/Interaction/GroupCoordinator.swift`

**Steps:**
1. Add a group-move handler that converts the tab bar's AppKit delta into the coordinate convention used by `WindowBounds`.
2. Translate `group.bounds`, apply it to each matched member window, update member references, persist the group, and show the updated panels.
3. Guard coordinator-driven Accessibility changes so they cannot be mistaken for a user moving an app window.
4. Change independent member move/resize notifications to restore that member to `group.bounds` rather than changing group bounds or moving other members.
5. Preserve existing tab selection and constrained-window status behavior.

### Task 3: Verify the interaction

**Files:**
- No additional files.

**Steps:**
1. Build the `TabGroups` Debug scheme.
2. Manually drag the tab bar and confirm all member windows and the outline follow together.
3. Drag a member app window and confirm the group stays in place and the member returns to the group bounds.
4. Confirm tab selection, remove controls, and panel visibility still work.
