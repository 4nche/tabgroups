import AppKit
import Combine

final class GroupCoordinator: ObservableObject {
    let store: GroupStore
    let catalog: WindowCatalog
    @Published var statusMessage: String?
    @Published var availableWindows: [DiscoveredWindow] = []

    private let windowController: WindowController
    private let strip = TabStripCoordinator()
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
        statusMessage = nil
        restoreAvailableGroups()
    }

    func refreshAvailableWindows() {
        availableWindows = catalog.scan()
    }

    func createGroup(windowIDs: [String]) {
        guard AccessibilityPermission.isGranted else {
            statusMessage = "Enable Accessibility permission before grouping windows."
            return
        }
        refreshAvailableWindows()
        var seen = Set<String>()
        let selected = windowIDs.compactMap { id -> DiscoveredWindow? in
            guard seen.insert(id).inserted else { return nil }
            return availableWindows.first { $0.id == id }
        }
        guard let first = selected.first, selected.count > 1,
              var group = WindowGroupFactory.make(from: selected, displayIdentifier: displayIdentifier(for: first.bounds)) else {
            statusMessage = "Select at least two available windows to create a group."
            return
        }

        for window in selected { detach(window, fromOtherGroupsExcept: group.id) }
        var constrainedApps: [String] = []
        for window in selected {
            guard let actual = window.window.apply(group.bounds) else {
                constrainedApps.append(window.appName)
                continue
            }
            let delta = abs(actual.x - group.bounds.x) + abs(actual.y - group.bounds.y)
                + abs(actual.width - group.bounds.width) + abs(actual.height - group.bounds.height)
            if delta > 4 { constrainedApps.append(window.appName) }
        }
        if let actual = first.window.bounds() { group.bounds = actual }
        first.window.raise()

        do {
            try store.upsert(group)
            show(group)
            statusMessage = constrainedApps.isEmpty
                ? "Created \(group.name) with \(group.members.count) windows."
                : "Some apps limited their window size: \(Array(Set(constrainedApps)).joined(separator: ", "))."
        } catch {
            statusMessage = error.localizedDescription
        }
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
            strip.hide(groupID: groupID)
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
        strip.hide(groupID: group.id)
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
                strip.hide(groupID: group.id)
            } else {
                if !group.members.contains(where: { $0.id == group.selectedMemberID }) { group.selectedMemberID = group.members.first?.id }
                do {
                    try store.upsert(group)
                    restore(group)
                } catch {
                    statusMessage = error.localizedDescription
                }
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
            strip.hide(groupID: group.id)
            if changed { try? store.upsert(group) }
            return
        }
        if changed { try? store.upsert(group) }
        for member in group.members where member.id != group.selectedMemberID {
            guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) else { continue }
            if let actual = live.window.apply(group.bounds) {
                updateReference(member.id, in: &group) { $0.lastKnownBounds = actual }
            }
        }
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
            restoreAvailableGroups()
        }
        refreshAvailableWindows()
        for var group in store.groups {
            guard let selectedID = group.selectedMemberID,
                  let selected = group.members.first(where: { $0.id == selectedID }),
                  let current = windowController.currentBounds(selected),
                  abs(current.x - group.bounds.x) + abs(current.y - group.bounds.y)
                    + abs(current.width - group.bounds.width) + abs(current.height - group.bounds.height) > 3 else { continue }
            var constrained = abs(current.width - group.bounds.width) + abs(current.height - group.bounds.height) > 4
            group.bounds = current
            updateReference(selectedID, in: &group) { $0.lastKnownBounds = current }
            for member in group.members where member.id != selectedID {
                guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) else { continue }
                guard let actual = live.window.apply(current) else { continue }
                let delta = abs(actual.x - current.x) + abs(actual.y - current.y)
                    + abs(actual.width - current.width) + abs(actual.height - current.height)
                if delta > 4 { constrained = true }
                updateReference(member.id, in: &group) { $0.lastKnownBounds = actual }
            }
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
