import AppKit
import Combine

final class GroupCoordinator: ObservableObject {
    let store: GroupStore
    let catalog: WindowCatalog
    @Published var statusMessage: String?
    @Published var availableWindows: [DiscoveredWindow] = []

    private let windowController: WindowController
    private let strip = TabStripCoordinator()
    private var dragMonitor: WindowDragMonitor?
    private var restorer: WindowRestorer?
    private var boundsTimer: Timer?
    private var started = false
    private var hadPermission = false

    init(store: GroupStore = GroupStore(), catalog: WindowCatalog = WindowCatalog()) {
        self.store = store
        self.catalog = catalog
        self.windowController = WindowController(catalog: catalog)
    }

    var unmatchedMembers: [(group: TabGroup, member: WindowReference)] {
        store.groups.flatMap { group in
            group.members.compactMap { member -> (group: TabGroup, member: WindowReference)? in
                switch WindowReferenceMatcher.match(member, among: availableWindows) {
                case .matched: return nil
                case .ambiguous, .missing: return (group, member)
                }
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        statusMessage = store.loadError?.localizedDescription
        refreshAvailableWindows()
        let monitor = WindowDragMonitor(catalog: catalog) { [weak self] source, target in
            guard let self else { return DragDropResult(message: "Tab Groups is unavailable", succeeded: false) }
            return self.createOrExtendGroup(source: source, target: target)
        }
        dragMonitor = monitor
        monitor.start()
        if AccessibilityPermission.isGranted {
            hadPermission = true
            restoreAvailableGroups()
        } else {
            statusMessage = "Grant Accessibility permission to group and control app windows."
        }
        restorer = WindowRestorer { [weak self] in self?.restoreAvailableGroups() }
        restorer?.start()
        boundsTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.observeActiveWindowBounds()
        }
    }

    func permissionWasGranted() {
        guard AccessibilityPermission.explainAndRequest() else {
            statusMessage = "Accessibility permission is still off. Enable Tab Groups in System Settings, then return here."
            return
        }
        dragMonitor?.start()
        statusMessage = nil
        restoreAvailableGroups()
    }

    func refreshAvailableWindows() {
        availableWindows = catalog.scan()
    }

    func select(groupID: UUID, memberID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }),
              let member = group.members.first(where: { $0.id == memberID }) else { return }
        do {
            let actual = try windowController.activate(member, bounds: group.bounds)
            group.selectedMemberID = member.id
            group.bounds = actual
            updateReference(member.id, in: &group) { $0.lastKnownBounds = actual }
            try store.upsert(group)
            show(group)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeMember(groupID: UUID, memberID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }) else { return }
        group.members.removeAll { $0.id == memberID }
        if group.members.isEmpty {
            do { try store.removeGroup(id: groupID) } catch { statusMessage = error.localizedDescription }
            strip.hide()
            return
        }
        if group.selectedMemberID == memberID { group.selectedMemberID = group.members.first?.id }
        do {
            try store.upsert(group)
            if let selected = group.selectedMemberID { select(groupID: groupID, memberID: selected) }
            else { show(group) }
        } catch { statusMessage = error.localizedDescription }
    }

    func deleteGroup(_ group: TabGroup) {
        do { try store.removeGroup(id: group.id) } catch { statusMessage = error.localizedDescription }
        strip.hide()
    }

    func reassign(memberID: UUID, to windowID: String) {
        guard let candidate = availableWindows.first(where: { $0.id == windowID }) else { return }
        guard var group = store.groups.first(where: { $0.members.contains(where: { $0.id == memberID }) }),
              let index = group.members.firstIndex(where: { $0.id == memberID }) else { return }
        var replacement = candidate.reference
        replacement.id = memberID
        group.members[index] = replacement
        if group.bounds.width <= 0 || group.bounds.height <= 0 { group.bounds = replacement.lastKnownBounds }
        do {
            try store.upsert(group)
            refreshAvailableWindows()
            restore(group)
        } catch { statusMessage = error.localizedDescription }
    }

    private func createOrExtendGroup(source: DiscoveredWindow, target: DiscoveredWindow) -> DragDropResult {
        guard AccessibilityPermission.isGranted else {
            statusMessage = "Enable Accessibility permission before grouping windows."
            return DragDropResult(message: statusMessage ?? "Accessibility permission is required", succeeded: false)
        }
        refreshAvailableWindows()
        var targetGroup = store.groups.first { group in
            group.members.contains { member in
                if case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) {
                    return live.id == target.id
                }
                return false
            }
        }
        if let group = targetGroup,
           group.members.contains(where: { member in
               if case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) { return live.id == source.id }
               return false
           }) {
            statusMessage = "Those windows are already in the same group."
            return DragDropResult(message: statusMessage ?? "Those windows are already grouped", succeeded: false)
        }

        if targetGroup == nil {
            targetGroup = TabGroup(
                name: "\(target.appName) Group",
                displayIdentifier: displayIdentifier(for: target.bounds),
                bounds: target.bounds,
                members: [target.reference, source.reference],
                selectedMemberID: target.reference.id
            )
        } else if var group = targetGroup {
            detach(source, fromOtherGroupsExcept: group.id)
            if let existingTarget = group.members.first(where: { member in
                if case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) {
                    return live.id == target.id
                }
                return false
            }) {
                group.selectedMemberID = existingTarget.id
            } else {
                group.members.append(target.reference)
                group.selectedMemberID = target.reference.id
            }
            group.members.append(source.reference)
            group.bounds = target.bounds
            targetGroup = group
        }
        guard let group = targetGroup else {
            return DragDropResult(message: "Couldn’t identify the target group", succeeded: false)
        }
        detach(source, fromOtherGroupsExcept: group.id)

        // Move the background member first and the drop target last so it stays visible.
        for member in group.members where member.id != group.selectedMemberID {
            guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) else { continue }
            if live.id != source.id && live.id != target.id { _ = live.window.apply(group.bounds) }
        }
        _ = source.window.apply(group.bounds)
        _ = target.window.apply(group.bounds)
        if let selected = group.members.first(where: { $0.id == group.selectedMemberID }),
           let live = (try? windowController.resolve(selected)) { live.window.raise() }
        do {
            try store.upsert(group)
            show(group)
            statusMessage = "Window group created."
            return DragDropResult(message: "Grouped \(source.appName) with \(target.appName)", succeeded: true)
        } catch {
            statusMessage = error.localizedDescription
            return DragDropResult(message: error.localizedDescription, succeeded: false)
        }
    }

    private func detach(_ window: DiscoveredWindow, fromOtherGroupsExcept keepID: UUID) {
        for var group in store.groups where group.id != keepID {
            let before = group.members.count
            group.members.removeAll { member in
                if case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) { return live.id == window.id }
                return false
            }
            guard before != group.members.count else { continue }
            if group.members.isEmpty {
                try? store.removeGroup(id: group.id)
                strip.hide()
            } else {
                if !group.members.contains(where: { $0.id == group.selectedMemberID }) { group.selectedMemberID = group.members.first?.id }
                try? store.upsert(group)
            }
        }
    }

    private func restoreAvailableGroups() {
        guard AccessibilityPermission.isGranted else { return }
        refreshAvailableWindows()
        store.groups.forEach(restore)
    }

    private func restore(_ original: TabGroup) {
        guard var group = store.groups.first(where: { $0.id == original.id }) else { return }
        var changed = false
        var availableMemberIDs = Set<UUID>()
        for index in group.members.indices {
            if case .matched(let live) = WindowReferenceMatcher.match(group.members[index], among: availableWindows) {
                group.members[index].processID = live.reference.processID
                group.members[index].lastKnownBounds = live.bounds
                availableMemberIDs.insert(group.members[index].id)
                changed = true
            }
        }
        if !availableMemberIDs.contains(group.selectedMemberID ?? UUID()),
           let fallback = group.members.first(where: { availableMemberIDs.contains($0.id) }) {
            group.selectedMemberID = fallback.id
            changed = true
        }
        guard !availableMemberIDs.isEmpty else {
            strip.hide()
            if changed { try? store.upsert(group) }
            return
        }
        if changed { try? store.upsert(group) }
        guard let selectedID = group.selectedMemberID,
              let selected = group.members.first(where: { $0.id == selectedID }),
              case .matched(let live) = WindowReferenceMatcher.match(selected, among: availableWindows) else { return }
        _ = live.window.apply(group.bounds)
        live.window.raise()
        show(group)
    }

    private func observeActiveWindowBounds() {
        guard AccessibilityPermission.isGranted else {
            hadPermission = false
            return
        }
        if !hadPermission {
            hadPermission = true
            if statusMessage?.localizedCaseInsensitiveContains("accessibility") == true {
                statusMessage = nil
            }
            dragMonitor?.start()
            restoreAvailableGroups()
        }
        refreshAvailableWindows()
        for var group in store.groups {
            guard let selectedID = group.selectedMemberID,
                  let selected = group.members.first(where: { $0.id == selectedID }),
                  let current = windowController.currentBounds(selected),
                  abs(current.x - group.bounds.x) + abs(current.y - group.bounds.y)
                    + abs(current.width - group.bounds.width) + abs(current.height - group.bounds.height) > 3 else { continue }
            let constrained = abs(current.width - group.bounds.width) + abs(current.height - group.bounds.height) > 4
            group.bounds = current
            updateReference(selectedID, in: &group) { $0.lastKnownBounds = current }
            try? store.upsert(group)
            if constrained { statusMessage = "An app constrained its window size. The group now uses the accepted size." }
            show(group)
        }
    }

    private func show(_ group: TabGroup) {
        let labels = Dictionary(uniqueKeysWithValues: group.members.map { member in
            let app = NSRunningApplication(processIdentifier: pid_t(member.processID ?? -1))?.localizedName ?? member.bundleIdentifier
            return (member.id, (app: app, title: member.title ?? "Window"))
        })
        strip.show(group, titles: labels,
                   select: { [weak self] id in self?.select(groupID: group.id, memberID: id) },
                   remove: { [weak self] id in self?.removeMember(groupID: group.id, memberID: id) })
    }

    private func updateReference(_ id: UUID, in group: inout TabGroup, update: (inout WindowReference) -> Void) {
        guard let index = group.members.firstIndex(where: { $0.id == id }) else { return }
        update(&group.members[index])
    }

    private func displayIdentifier(for bounds: WindowBounds) -> String? {
        guard let screen = NSScreen.screens.first(where: {
            let point = CGPoint(x: CGFloat(bounds.x + bounds.width / 2),
                                y: $0.frame.maxY - CGFloat(bounds.y + bounds.height / 2))
            return $0.frame.contains(point)
        }), let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return number.stringValue
    }
}
