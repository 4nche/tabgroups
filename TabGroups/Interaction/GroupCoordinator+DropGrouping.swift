import AppKit

/// What a Shift-drag can be dropped on.
enum DropTarget {
    case window(AXWindow)
    case group(UUID)
}

extension GroupCoordinator {
    func groupID(containing window: AXWindow) -> UUID? {
        store.groups.first { group in
            group.members.contains { liveWindow(for: $0)?.window.isSameWindow(as: window.element) ?? false }
        }?.id
    }

    func groupID(forBarWindowNumber number: Int) -> UUID? {
        strip.groupID(forWindowNumber: number)
    }

    func containerBounds(ofGroup id: UUID) -> WindowBounds? {
        movement.pendingContainers[id] ?? store.groups.first { $0.id == id }?.bounds
    }

    /// Finishes a Shift-drag: `source` was dropped on `target`.
    func completeDrop(of source: AXWindow, onto target: DropTarget) {
        if case .window(let window) = target, window.isSameWindow(as: source.element) { return }
        let sourceGroup = groupID(containing: source)
        let targetGroup: UUID?
        switch target {
        case .group(let id): targetGroup = id
        case .window(let window): targetGroup = groupID(containing: window)
        }

        switch DropPlan.action(sourceGroup: sourceGroup, targetGroup: targetGroup) {
        case .nothing:
            return
        case .createGroup:
            guard case .window(let targetWindow) = target,
                  let anchor = catalog.describe(targetWindow), let dragged = catalog.describe(source) else {
                statusMessage = "Could not read one of those windows."
                return
            }
            formGroup(from: [anchor, dragged], selecting: dragged)
        case .addSource(let groupID):
            guard let dragged = catalog.describe(source) else {
                statusMessage = "Could not read the dragged window."
                return
            }
            add(dragged, toGroup: groupID, selecting: true)
        case .addTarget(let groupID):
            guard case .window(let targetWindow) = target, let added = catalog.describe(targetWindow) else {
                statusMessage = "Could not read the window you dropped on."
                return
            }
            // The group was just dragged here by its member. Read where that member is now (its move
            // notification may not have arrived yet) and land the group there before the new window joins.
            if let member = member(for: source, inGroup: groupID) {
                memberGeometryChanged(groupID: groupID, memberID: member.id)
            }
            flushPendingMove(groupID: groupID)
            add(added, toGroup: groupID, selecting: false)
            source.raise()
        case .merge(let groupID, let destination):
            merge(groupID: groupID, into: destination, selecting: source)
        }
    }

    private func member(for window: AXWindow, inGroup groupID: UUID) -> WindowReference? {
        store.groups.first { $0.id == groupID }?.members.first { member in
            liveWindow(for: member)?.window.isSameWindow(as: window.element) ?? false
        }
    }

    private func add(_ window: DiscoveredWindow, toGroup groupID: UUID, selecting: Bool) {
        guard var group = store.groups.first(where: { $0.id == groupID }) else { return }
        registry.remember(window, memberID: window.reference.id)
        group.members = group.members + [window.reference]
        if selecting { group.selectedMemberID = window.reference.id }
        let placed = placeAll(in: group)
        if selecting { window.window.raise() }
        guard persist(placed.group) else { return }
        show(placed.group)
        statusMessage = "Added \(window.appName) to \(group.name)."
    }

    /// Moves every member of one group into another. Live handles are kept, since member ids carry over.
    private func merge(groupID: UUID, into destinationID: UUID, selecting source: AXWindow) {
        guard let moving = store.groups.first(where: { $0.id == groupID }),
              var destination = store.groups.first(where: { $0.id == destinationID }) else { return }
        let dragged = member(for: source, inGroup: groupID)
        // Store first: if the write fails, the group keeps its bar and observers.
        do { try store.removeGroup(id: groupID) } catch {
            statusMessage = error.localizedDescription
            return
        }
        cancelMovement(groupID: groupID)
        strip.hide(groupID: groupID)
        observers.stop(groupID: groupID)
        destination.members = destination.members + moving.members
        if let dragged { destination.selectedMemberID = dragged.id }
        let placed = placeAll(in: destination)
        source.raise()
        guard persist(placed.group) else { return }
        show(placed.group)
        statusMessage = "Merged \(moving.name) into \(destination.name)."
    }
}
