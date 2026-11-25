import ApplicationServices
import AppKit
import Combine

private final class WindowGeometryObserverContext {
    weak var coordinator: GroupCoordinator?
    let groupID: UUID
    let memberID: UUID

    init(coordinator: GroupCoordinator, groupID: UUID, memberID: UUID) {
        self.coordinator = coordinator
        self.groupID = groupID
        self.memberID = memberID
    }
}

private struct WindowGeometryObserverRegistration {
    let observer: AXObserver
    let source: CFRunLoopSource
    let context: WindowGeometryObserverContext
    let groupID: UUID
    let processID: pid_t
}

private let windowGeometryObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let context = Unmanaged<WindowGeometryObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    context.coordinator?.scheduleWindowBoundsSync(groupID: context.groupID, memberID: context.memberID)
}

final class GroupCoordinator: ObservableObject {
    let store: GroupStore
    let catalog: WindowCatalog
    @Published var statusMessage: String?
    @Published var availableWindows: [DiscoveredWindow] = []

    private let strip = TabStripCoordinator()
    private let windowScanQueue = DispatchQueue(label: "com.4nche.TabGroups.window-scan", qos: .userInitiated)
    private var restorer: WindowRestorer?
    private var windowRefreshTimer: Timer?
    private var windowScanInProgress = false
    private var windowScanCompletions: [([DiscoveredWindow]) -> Void] = []
    private var geometryObservers: [UUID: WindowGeometryObserverRegistration] = [:]
    private var pendingBoundsSyncs: [UUID: DispatchWorkItem] = [:]
    private var activeGroupMoves: [UUID: TabGroup] = [:]
    private var started = false

    init(store: GroupStore = GroupStore(), catalog: WindowCatalog = WindowCatalog()) {
        self.store = store
        self.catalog = catalog
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
        if AccessibilityPermission.isGranted {
            restoreAvailableGroups()
        } else {
            statusMessage = "Grant Accessibility permission to group and control app windows."
        }
        restorer = WindowRestorer { [weak self] in self?.restoreAvailableGroups() }
        restorer?.start()
        windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshAvailableWindows()
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
        refreshAvailableWindows(completion: nil)
    }

    private func refreshAvailableWindows(completion: (([DiscoveredWindow]) -> Void)?) {
        if let completion { windowScanCompletions.append(completion) }
        guard !windowScanInProgress else { return }
        windowScanInProgress = true
        windowScanQueue.async { [weak self] in
            guard let self else { return }
            let windows = self.catalog.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.availableWindows = windows
                self.windowScanInProgress = false
                if AccessibilityPermission.isGranted {
                    self.store.groups.forEach(self.configureGeometryObservers)
                }
                let completions = self.windowScanCompletions
                self.windowScanCompletions.removeAll()
                completions.forEach { $0(windows) }
            }
        }
    }

    func createGroup(windowIDs: [String]) {
        guard AccessibilityPermission.isGranted else {
            statusMessage = "Enable Accessibility permission before grouping windows."
            return
        }
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
        guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows) else {
            statusMessage = "That window is unavailable. Refresh the window list and try again."
            return
        }
        live.window.raise()
        guard let actual = live.window.apply(group.bounds) else {
            statusMessage = "Could not move or resize that window."
            return
        }
        group.selectedMemberID = member.id
        group.bounds = actual
        updateReference(member.id, in: &group) { $0.lastKnownBounds = actual }
        do {
            try store.upsert(group)
            show(group)
            statusMessage = nil
        } catch { statusMessage = error.localizedDescription }
    }

    func removeMember(groupID: UUID, memberID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }) else { return }
        group.members.removeAll { $0.id == memberID }
        if group.members.isEmpty {
            do { try store.removeGroup(id: groupID) } catch { statusMessage = error.localizedDescription }
            strip.hide(groupID: groupID)
            removeGeometryObservers(groupID: groupID)
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
        removeGeometryObservers(groupID: group.id)
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
                removeGeometryObservers(groupID: group.id)
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

    private func configureGeometryObservers(for group: TabGroup) {
        let memberIDs = Set(group.members.map(\.id))
        let staleIDs = geometryObservers.compactMap { memberID, registration in
            registration.groupID == group.id && !memberIDs.contains(memberID) ? memberID : nil
        }
        staleIDs.forEach(removeGeometryObserver)

        for member in group.members {
            guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows),
                  let processID = live.reference.processID.map({ pid_t($0) }) else {
                if geometryObservers[member.id]?.groupID == group.id { removeGeometryObserver(member.id) }
                continue
            }
            if let existing = geometryObservers[member.id],
               existing.groupID == group.id, existing.processID == processID { continue }
            removeGeometryObserver(member.id)

            var observer: AXObserver?
            guard AXObserverCreate(processID, windowGeometryObserverCallback, &observer) == .success,
                  let observer else { continue }
            let context = WindowGeometryObserverContext(coordinator: self, groupID: group.id, memberID: member.id)
            let contextPointer = Unmanaged.passUnretained(context).toOpaque()
            let moved = AXObserverAddNotification(observer, live.window.element, kAXMovedNotification as CFString, contextPointer)
            let resized = AXObserverAddNotification(observer, live.window.element, kAXResizedNotification as CFString, contextPointer)
            guard moved == .success || resized == .success else { continue }
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            geometryObservers[member.id] = WindowGeometryObserverRegistration(
                observer: observer,
                source: source,
                context: context,
                groupID: group.id,
                processID: processID
            )
        }
    }

    private func removeGeometryObserver(_ memberID: UUID) {
        guard let registration = geometryObservers.removeValue(forKey: memberID) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), registration.source, .commonModes)
    }

    private func removeGeometryObservers(groupID: UUID) {
        let memberIDs = geometryObservers.compactMap { memberID, registration in
            registration.groupID == groupID ? memberID : nil
        }
        memberIDs.forEach(removeGeometryObserver)
        pendingBoundsSyncs.removeValue(forKey: groupID)?.cancel()
    }

    fileprivate func scheduleWindowBoundsSync(groupID: UUID, memberID: UUID) {
        pendingBoundsSyncs[groupID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBoundsSyncs[groupID] = nil
            self.synchronizeGroupBounds(groupID: groupID, sourceMemberID: memberID)
        }
        pendingBoundsSyncs[groupID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func moveGroup(groupID: UUID, by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0,
              var group = activeGroupMoves[groupID] ?? store.groups.first(where: { $0.id == groupID }) else { return }
        group.bounds.x += Double(delta.width)
        group.bounds.y += Double(delta.height)

        var constrainedApps: [String] = []
        for member in group.members {
            guard case .matched(let live) = WindowReferenceMatcher.match(member, among: availableWindows),
                  let actual = live.window.apply(group.bounds) else { continue }
            let difference = abs(actual.x - group.bounds.x) + abs(actual.y - group.bounds.y)
                + abs(actual.width - group.bounds.width) + abs(actual.height - group.bounds.height)
            if difference > 4 { constrainedApps.append(live.appName) }
            updateReference(member.id, in: &group) { $0.lastKnownBounds = actual }
        }

        activeGroupMoves[groupID] = group
        strip.translate(groupID: groupID, by: delta)
        if !constrainedApps.isEmpty {
            statusMessage = "Some apps limited their window movement: \(Array(Set(constrainedApps)).joined(separator: ", "))."
        }
    }

    private func finishGroupMove(groupID: UUID) {
        guard let group = activeGroupMoves.removeValue(forKey: groupID) else { return }
        do { try store.upsert(group) }
        catch { statusMessage = error.localizedDescription }
    }

    private func synchronizeGroupBounds(groupID: UUID, sourceMemberID: UUID) {
        guard var group = activeGroupMoves[groupID] ?? store.groups.first(where: { $0.id == groupID }),
              let source = group.members.first(where: { $0.id == sourceMemberID }),
              case .matched(let liveSource) = WindowReferenceMatcher.match(source, among: availableWindows),
              let bounds = liveSource.window.bounds() else { return }
        let change = abs(bounds.x - group.bounds.x) + abs(bounds.y - group.bounds.y)
            + abs(bounds.width - group.bounds.width) + abs(bounds.height - group.bounds.height)
        guard change > 2 else { return }

        guard let actual = liveSource.window.apply(group.bounds) else { return }
        updateReference(sourceMemberID, in: &group) { $0.lastKnownBounds = actual }
        if activeGroupMoves[groupID] != nil {
            activeGroupMoves[groupID] = group
            return
        }
        do {
            try store.upsert(group)
        } catch { statusMessage = error.localizedDescription }
    }

    private func restoreAvailableGroups() {
        guard AccessibilityPermission.isGranted else { return }
        refreshAvailableWindows { [weak self] _ in
            guard let self, AccessibilityPermission.isGranted else { return }
            self.store.groups.forEach(self.restore)
        }
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

    private func show(_ group: TabGroup) {
        configureGeometryObservers(for: group)
        let labels = Dictionary(uniqueKeysWithValues: group.members.map { member in
            let app = NSRunningApplication(processIdentifier: pid_t(member.processID ?? -1))?.localizedName ?? member.bundleIdentifier
            return (member.id, (app: app, title: member.title ?? "Window"))
        })
        strip.show(group, titles: labels,
                   select: { [weak self] id in self?.select(groupID: group.id, memberID: id) },
                   remove: { [weak self] id in self?.removeMember(groupID: group.id, memberID: id) },
                   move: { [weak self] delta in self?.moveGroup(groupID: group.id, by: delta) },
                   moveEnded: { [weak self] in self?.finishGroupMove(groupID: group.id) })
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
