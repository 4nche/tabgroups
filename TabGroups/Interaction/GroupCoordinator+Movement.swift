import AppKit

/// What is in flight while a group is being moved.
struct GroupMovementState {
    /// Container at the moment a bar drag started, per group.
    var dragOrigins: [UUID: WindowBounds] = [:]
    /// Working copy of a group during a bar drag; saved when the drag ends.
    var draggedGroups: [UUID: TabGroup] = [:]
    /// Container a group will take once an outside move of a member settles.
    var pendingContainers: [UUID: WindowBounds] = [:]
    var settleWork: [UUID: DispatchWorkItem] = [:]
}

extension GroupCoordinator {
    static let settleDelay: TimeInterval = 0.12

    func isMoving(groupID: UUID) -> Bool {
        movement.dragOrigins[groupID] != nil || movement.pendingContainers[groupID] != nil
    }

    func cancelMovement(groupID: UUID) {
        movement.settleWork.removeValue(forKey: groupID)?.cancel()
        movement.pendingContainers[groupID] = nil
        movement.dragOrigins[groupID] = nil
        movement.draggedGroups[groupID] = nil
    }

    // MARK: - Dragging the bar

    /// `offset` is the pointer's total travel since mouse-down, in Accessibility axes.
    func barDragChanged(groupID: UUID, offset: CGSize) {
        guard let stored = movement.draggedGroups[groupID] ?? store.groups.first(where: { $0.id == groupID })
        else { return }
        if movement.dragOrigins[groupID] == nil {
            movement.settleWork.removeValue(forKey: groupID)?.cancel()
            movement.dragOrigins[groupID] = movement.pendingContainers.removeValue(forKey: groupID) ?? stored.bounds
        }
        guard let origin = movement.dragOrigins[groupID] else { return }

        var group = stored
        group.bounds = origin.translated(dx: Double(offset.width), dy: Double(offset.height))
        movement.draggedGroups[groupID] = group
        strip.place(groupID: groupID, at: group.bounds)

        // Only the visible window follows live; the ones underneath catch up when the drag ends.
        if let selected = group.members.first(where: { $0.id == group.selectedMemberID }),
           let live = liveWindow(for: selected) {
            _ = live.window.move(to: GroupGeometry.contentBounds(of: group.bounds))
        }
    }

    func barDragEnded(groupID: UUID) {
        let dragged = movement.draggedGroups.removeValue(forKey: groupID)
        movement.dragOrigins[groupID] = nil
        // Re-read the group: a tab may have been removed while the drag was in flight.
        guard let dragged, let current = store.groups.first(where: { $0.id == groupID }) else { return }
        commit(current, container: dragged.bounds)
    }

    // MARK: - A member moved by something else

    /// A member window was moved or resized: by the mouse, by a window manager such as Rectangle Pro,
    /// or by its app. The group follows it instead of putting it back.
    func memberGeometryChanged(groupID: UUID, memberID: UUID) {
        guard movement.dragOrigins[groupID] == nil,
              let group = store.groups.first(where: { $0.id == groupID }),
              let member = group.members.first(where: { $0.id == memberID }),
              let window = liveWindow(for: member)?.window,
              !window.isMinimizedOrFullScreen,
              let reported = window.bounds() else { return }
        let lastApplied = registry.lastApplied[memberID]
        guard !GroupGeometry.isEcho(reported, of: lastApplied) else { return }

        let container = GroupGeometry.container(group.bounds, afterMember: reported, lastApplied: lastApplied,
                                                visibleTop: ScreenGeometry.visibleTop(for: reported))
        movement.pendingContainers[groupID] = container
        strip.place(groupID: groupID, at: container)
        scheduleSettle(groupID: groupID)
    }

    private func scheduleSettle(groupID: UUID) {
        movement.settleWork[groupID]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settle(groupID: groupID) }
        movement.settleWork[groupID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func settle(groupID: UUID) {
        // Never reposition a window the user is still holding.
        guard NSEvent.pressedMouseButtons == 0 else {
            scheduleSettle(groupID: groupID)
            return
        }
        movement.settleWork[groupID] = nil
        guard let container = movement.pendingContainers.removeValue(forKey: groupID),
              let group = store.groups.first(where: { $0.id == groupID }) else { return }
        commit(group, container: container)
    }

    /// Makes `container` the group's rectangle: places every member, saves, and restacks the bar.
    private func commit(_ group: TabGroup, container: WindowBounds) {
        var moved = group
        moved.bounds = GroupGeometry.shiftedIntoView(container, visibleTop: ScreenGeometry.visibleTop(for: container))
        moved.displayIdentifier = ScreenGeometry.displayIdentifier(for: moved.bounds)
        let placed = placeAll(in: moved)
        persist(placed.group)
        strip.place(groupID: group.id, at: placed.group.bounds)
        strip.reorder(groupID: group.id, memberWindowNumbers: memberWindowNumbers(for: placed.group))
        if !placed.constrainedApps.isEmpty {
            statusMessage = "Some apps limited their window size: \(placed.constrainedApps.joined(separator: ", "))."
        }
    }

    // MARK: - Following app switches

    /// When an app comes forward (Dock, Cmd-Tab, a click), the tab of its focused window becomes
    /// the selected one and the bar is restacked with the group.
    func applicationActivated(processID: pid_t) {
        for group in store.groups where !isMoving(groupID: group.id) {
            let owned = group.members.filter { liveWindow(for: $0)?.window.processID == processID }
            guard let first = owned.first, let anyWindow = liveWindow(for: first)?.window else { continue }
            let focused = anyWindow.focusedWindowOfOwningApp()
            let front = owned.first { member in
                guard let focused, let live = liveWindow(for: member) else { return false }
                return live.window.isSameWindow(as: focused)
            }
            guard let front else { continue }
            var updated = group
            updated.selectedMemberID = front.id
            if updated != group { persist(updated) }
            show(updated)
        }
    }
}
