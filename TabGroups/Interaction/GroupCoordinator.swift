import ApplicationServices
import AppKit
import Combine

/// Creates, restores and edits groups. Movement lives in `GroupCoordinator+Movement.swift`.
final class GroupCoordinator: ObservableObject {
    static let windowRefreshInterval: TimeInterval = 5
    static let popOutOffset: Double = 36

    let store: GroupStore
    let catalog: WindowCatalog
    @Published var statusMessage: String?
    @Published var availableWindows: [DiscoveredWindow] = []

    let strip = TabStripCoordinator()
    let registry = LiveWindowRegistry()
    let observers = GeometryObserverCenter()
    let missionControl = MissionControlOverlay()
    var movement = GroupMovementState()

    private let windowScanQueue = DispatchQueue(label: "com.4nche.TabGroups.window-scan", qos: .userInitiated)
    private var dragGrouping: ShiftDragMonitor?
    private var restorer: WindowRestorer?
    private var windowRefreshTimer: Timer?
    private var activationToken: NSObjectProtocol?
    private var terminationToken: NSObjectProtocol?
    private var appQuitToken: NSObjectProtocol?
    private var powerOffToken: NSObjectProtocol?
    /// Set while the Mac shuts down or logs out: apps quitting then must not empty the groups.
    var isPoweringOff = false
    private var windowScanInProgress = false
    private var windowScanCompletions: [([DiscoveredWindow]) -> Void] = []
    private var hasRaisedOnRestore = false
    private var started = false

    init(store: GroupStore = GroupStore(), catalog: WindowCatalog = WindowCatalog()) {
        self.store = store
        self.catalog = catalog
    }

    deinit {
        if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        if let terminationToken { NotificationCenter.default.removeObserver(terminationToken) }
        if let appQuitToken { NSWorkspace.shared.notificationCenter.removeObserver(appQuitToken) }
        if let powerOffToken { NSWorkspace.shared.notificationCenter.removeObserver(powerOffToken) }
    }

    var unmatchedMembers: [(group: TabGroup, member: WindowReference)] {
        store.groups.flatMap { group in
            group.members.compactMap { member -> (group: TabGroup, member: WindowReference)? in
                liveWindow(for: member) == nil ? (group, member) : nil
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        statusMessage = store.loadError?.localizedDescription
        observers.onChange = { [weak self] groupID, memberID in
            self?.memberGeometryChanged(groupID: groupID, memberID: memberID)
        }
        observers.onDestroyed = { [weak self] groupID, memberID in
            self?.memberWindowClosed(groupID: groupID, memberID: memberID)
        }
        if AccessibilityPermission.isGranted {
            restoreAvailableGroups()
        } else {
            statusMessage = "Grant Accessibility permission to group and control app windows."
        }
        dragGrouping = ShiftDragMonitor(coordinator: self)
        dragGrouping?.start()
        missionControl.groups = { [weak self] in self?.missionControlGroups() ?? [] }
        missionControl.onSelect = { [weak self] groupID, memberID in self?.select(groupID: groupID, memberID: memberID) }
        missionControl.start()
        restorer = WindowRestorer { [weak self] in self?.restoreAvailableGroups() }
        restorer?.start()
        windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.windowRefreshInterval,
                                                  repeats: true) { [weak self] _ in
            self?.refreshAvailableWindows { _ in self?.refreshBars() }
        }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(processID: app.processIdentifier)
        }
        appQuitToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationTerminated(processID: app.processIdentifier)
        }
        powerOffToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isPoweringOff = true
        }
        terminationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.revealAll()
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
                self.registry.prune(keeping: windows)
                self.availableWindows = windows
                self.windowScanInProgress = false
                let completions = self.windowScanCompletions
                self.windowScanCompletions = []
                completions.forEach { $0(windows) }
            }
        }
    }

    // MARK: - Editing groups

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
        formGroup(from: selected, selecting: selected.first)
    }

    /// Groups the given windows where the first one sits. Used by the picker and by Shift-drag.
    func formGroup(from windows: [DiscoveredWindow], selecting selected: DiscoveredWindow?) {
        guard let first = windows.first,
              let made = WindowGroupFactory.make(from: windows,
                                                 displayIdentifier: ScreenGeometry.displayIdentifier(for: first.bounds))
        else {
            statusMessage = "Select at least two available windows to create a group."
            return
        }
        windows.forEach { detach($0, fromOtherGroupsExcept: made.id) }
        windows.forEach { registry.remember($0, memberID: $0.reference.id) }

        // The first window keeps its place; the bar goes above it unless it touches the top edge.
        let current = first.window.bounds() ?? first.bounds
        var group = made
        group.bounds = GroupGeometry.container(adopting: current,
                                               visibleTop: ScreenGeometry.visibleTop(for: current))
        group.selectedMemberID = (selected ?? first).reference.id
        let placed = placeAll(in: group)
        reveal((selected ?? first).window)
        (selected ?? first).window.raise()
        guard persist(placed.group) else { return }
        show(placed.group)
        concealUnselected(in: placed.group)
        statusMessage = placed.constrainedApps.isEmpty
            ? "Created \(group.name) with \(group.members.count) windows."
            : "Some apps limited their window size: \(placed.constrainedApps.joined(separator: ", "))."
    }

    func select(groupID: UUID, memberID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }),
              let member = group.members.first(where: { $0.id == memberID }) else { return }
        guard let live = liveWindow(for: member) else {
            statusMessage = "That window is unavailable. Refresh the window list and try again."
            return
        }
        reveal(live.window)
        live.window.raise()
        guard let actual = place(member, in: group) else {
            statusMessage = "Could not move or resize that window."
            return
        }
        group.selectedMemberID = member.id
        group.members = group.members.map { $0.id == member.id ? $0.with(lastKnownBounds: actual) : $0 }
        guard persist(group) else { return }
        show(group)
        concealUnselected(in: group)
        statusMessage = nil
    }

    func removeMember(groupID: UUID, memberID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }) else { return }
        // A tab removed with its close button pops out a little, so its window is not lost behind the group.
        var poppedOut: AXWindow?
        if let leaving = group.members.first(where: { $0.id == memberID }), let live = liveWindow(for: leaving) {
            reveal(live.window)
            if movement.tornTabs[memberID] == nil, let bounds = live.window.bounds() {
                _ = live.window.move(to: bounds.translated(dx: Self.popOutOffset, dy: Self.popOutOffset))
                poppedOut = live.window
            }
        }
        defer { poppedOut?.raise() }
        group.members = group.members.filter { $0.id != memberID }
        registry.forget(memberID: memberID)
        // A group of one is just a window with a bar on it: it dissolves.
        guard group.members.count >= 2 else {
            deleteGroup(group)
            return
        }
        if group.selectedMemberID == memberID { group.selectedMemberID = group.members.first?.id }
        guard persist(group) else { return }
        if let selected = group.selectedMemberID {
            select(groupID: groupID, memberID: selected)
        } else {
            show(group)
        }
    }

    func deleteGroup(_ group: TabGroup) {
        do { try store.removeGroup(id: group.id) } catch { statusMessage = error.localizedDescription }
        group.members.compactMap { liveWindow(for: $0)?.window }.forEach(reveal)
        group.members.forEach { registry.forget(memberID: $0.id) }
        strip.hide(groupID: group.id)
        observers.stop(groupID: group.id)
        cancelMovement(groupID: group.id)
    }

    func reassign(memberID: UUID, to windowID: String) {
        guard let candidate = availableWindows.first(where: { $0.id == windowID }),
              var group = store.groups.first(where: { $0.members.contains { $0.id == memberID } }) else { return }
        var replacement = candidate.reference
        replacement.id = memberID
        group.members = group.members.map { $0.id == memberID ? replacement : $0 }
        registry.forget(memberID: memberID)
        registry.remember(candidate, memberID: memberID)
        if group.bounds.width <= 0 || group.bounds.height <= 0 {
            group.bounds = GroupGeometry.container(
                adopting: replacement.lastKnownBounds,
                visibleTop: ScreenGeometry.visibleTop(for: replacement.lastKnownBounds))
        }
        guard persist(group) else { return }
        restore(group)
    }

    private func detach(_ window: DiscoveredWindow, fromOtherGroupsExcept keepID: UUID) {
        for group in store.groups where group.id != keepID {
            let leaving = group.members.filter { member in
                liveWindow(for: member)?.window.isSameWindow(as: window.window.element) ?? false
            }
            leaving.forEach { removeMember(groupID: group.id, memberID: $0.id) }
        }
    }

    // MARK: - Restoring

    private func restoreAvailableGroups() {
        guard AccessibilityPermission.isGranted else { return }
        refreshAvailableWindows { [weak self] _ in
            guard let self, AccessibilityPermission.isGranted else { return }
            let raise = !self.hasRaisedOnRestore
            self.hasRaisedOnRestore = true
            self.store.groups.forEach { self.restore($0, raisingSelected: raise) }
        }
    }

    /// Reconnects a group to its open windows and puts them back in the container. Only the first
    /// restore after launch raises the selected window, so an unrelated app launch never steals focus.
    private func restore(_ original: TabGroup, raisingSelected: Bool = false) {
        guard var group = store.groups.first(where: { $0.id == original.id }),
              !isMoving(groupID: group.id) else { return }
        let available = group.members.filter { liveWindow(for: $0) != nil }
        guard !available.isEmpty else {
            strip.hide(groupID: group.id)
            observers.stop(groupID: group.id)
            return
        }
        group.members = group.members.map { member in
            guard let live = liveWindow(for: member) else { return member }
            var updated = member
            updated.processID = live.reference.processID
            return updated
        }
        if !available.contains(where: { $0.id == group.selectedMemberID }) {
            group.selectedMemberID = available.first?.id
        }
        group.bounds = GroupGeometry.shiftedIntoView(group.bounds, visibleTop: ScreenGeometry.visibleTop(for: group.bounds))
        let placed = placeAll(in: group)
        if raisingSelected, let selected = placed.group.members.first(where: { $0.id == placed.group.selectedMemberID }),
           let live = liveWindow(for: selected) {
            reveal(live.window)
            live.window.raise()
        }
        if placed.group != original { _ = persist(placed.group) }
        show(placed.group)
        concealUnselected(in: placed.group)
    }

    // MARK: - Shared helpers

    func liveWindow(for member: WindowReference) -> DiscoveredWindow? {
        registry.window(for: member, among: availableWindows)
    }

    /// Places a member at the group's content rectangle and records what the window actually took.
    @discardableResult
    func place(_ member: WindowReference, in group: TabGroup) -> WindowBounds? {
        guard let live = liveWindow(for: member),
              let actual = live.window.apply(GroupGeometry.contentBounds(of: group.bounds)) else { return nil }
        registry.recordApplied(actual, memberID: member.id)
        return actual
    }

    /// Places every reachable member; returns the group with refreshed member bounds and the apps
    /// that did not take the requested rectangle.
    func placeAll(in group: TabGroup) -> (group: TabGroup, constrainedApps: [String]) {
        let content = GroupGeometry.contentBounds(of: group.bounds)
        var constrained = Set<String>()
        var updated = group
        updated.members = group.members.map { member in
            guard let actual = place(member, in: group) else { return member }
            if actual.distance(to: content) > GroupGeometry.tolerance, let live = liveWindow(for: member) {
                constrained.insert(live.appName)
            }
            return member.with(lastKnownBounds: actual)
        }
        return (updated, constrained.sorted())
    }

    @discardableResult
    func persist(_ group: TabGroup) -> Bool {
        do {
            try store.upsert(group)
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func show(_ group: TabGroup) {
        observers.observe(group: group, resolve: liveWindow(for:))
        strip.show(group, tabs: tabs(for: group),
                   select: { [weak self] id in self?.select(groupID: group.id, memberID: id) },
                   remove: { [weak self] id in self?.removeMember(groupID: group.id, memberID: id) },
                   dragChanged: { [weak self] offset in self?.barDragChanged(groupID: group.id, offset: offset) },
                   dragEnded: { [weak self] in self?.barDragEnded(groupID: group.id) },
                   tabDragChanged: { [weak self] id, offset in
                       self?.tabDragChanged(groupID: group.id, memberID: id, offset: offset)
                   },
                   tabDragEnded: { [weak self] id in self?.tabDragEnded(memberID: id) },
                   memberWindowNumbers: memberWindowNumbers(for: group))
    }

    /// Refreshes tab titles and stacking for groups that are not being moved right now.
    private func refreshBars() {
        guard AccessibilityPermission.isGranted else { return }
        store.groups.filter { !isMoving(groupID: $0.id) }.forEach { group in
            guard let next = group.members.first(where: { liveWindow(for: $0) != nil }) else { return }
            // The selected tab's window went away unnoticed: bring the next one up instead of an empty group.
            if let selected = group.members.first(where: { $0.id == group.selectedMemberID }),
               liveWindow(for: selected) == nil, let live = liveWindow(for: next) {
                var healed = group
                healed.selectedMemberID = next.id
                persist(healed)
                reveal(live.window)
                show(healed)
                concealUnselected(in: healed)
                return
            }
            show(group)
        }
    }

    /// Each group's visible window and tabs, for the bar laid over Mission Control.
    private func missionControlGroups() -> [MissionControlGroup] {
        store.groups.compactMap { group in
            guard let selected = group.members.first(where: { $0.id == group.selectedMemberID }),
                  let live = liveWindow(for: selected),
                  let bounds = live.window.bounds() else { return nil }
            return MissionControlGroup(groupID: group.id,
                                       windowTitle: live.window.readString(kAXTitleAttribute as CFString),
                                       windowBounds: bounds, tabs: tabs(for: group),
                                       selectedID: group.selectedMemberID)
        }
    }

    private func tabs(for group: TabGroup) -> [TabItem] {
        group.members.map { member in
            let live = liveWindow(for: member)
            let app = member.processID.flatMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            return TabItem(
                id: member.id,
                appName: live?.appName ?? app?.localizedName ?? member.bundleIdentifier,
                title: live?.window.readString(kAXTitleAttribute as CFString) ?? member.title ?? "Window",
                icon: app?.icon
            )
        }
    }

    func memberWindowNumbers(for group: TabGroup) -> [CGWindowID] {
        guard let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let onScreen: [(number: CGWindowID, processID: Int32, bounds: WindowBounds)] = raw.compactMap { info in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let rect = (info[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return nil }
            return (number, processID, WindowBounds(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        }
        return group.members.compactMap { member in
            guard let live = liveWindow(for: member), let bounds = live.window.bounds() else { return nil }
            return onScreen
                .filter { $0.processID == live.window.processID }
                .min { $0.bounds.distance(to: bounds) < $1.bounds.distance(to: bounds) }?
                .number
        }
    }
}

extension WindowReference {
    func with(lastKnownBounds bounds: WindowBounds) -> WindowReference {
        var copy = self
        copy.lastKnownBounds = bounds
        return copy
    }
}

// MARK: - Keeping only the selected tab on screen

/// A group's tabs that are not selected are taken off screen, so Mission Control, App Exposé and
/// Show Desktop see one window per group instead of the whole stack. The app of an unselected tab
/// is hidden when that tab is its only open window, which is instant; otherwise the window is
/// minimised, so the app's other windows stay where they are.
extension GroupCoordinator {
    /// Gives the newly selected window a moment to come forward before the others leave, so hiding
    /// the app that was in front never hands focus to an unrelated app.
    static let concealDelay: TimeInterval = 0.15

    func concealUnselected(in group: TabGroup, after delay: TimeInterval = concealDelay) {
        let groupID = group.id
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let current = self.store.groups.first(where: { $0.id == groupID }),
                  !self.isMoving(groupID: groupID) else { return }
            for member in current.members where member.id != current.selectedMemberID {
                guard let live = self.liveWindow(for: member) else { continue }
                self.conceal(live.window)
            }
        }
    }

    func reveal(_ window: AXWindow) {
        if let app = NSRunningApplication(processIdentifier: window.processID), app.isHidden { app.unhide() }
        if window.isMinimized { window.setMinimized(false) }
    }

    /// Puts every grouped window back on screen; used when Tab Groups quits.
    func revealAll() {
        store.groups.flatMap(\.members).compactMap { liveWindow(for: $0)?.window }.forEach(reveal)
    }

    private func conceal(_ window: AXWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.processID),
              !app.isHidden, !window.isMinimized else { return }
        if canHide(app) {
            app.hide()
        } else {
            window.setMinimized(true)
        }
    }

    /// An app can be hidden only when every window it has on screen is an unselected tab of some group.
    private func canHide(_ app: NSRunningApplication) -> Bool {
        let concealable = store.groups.flatMap { group in
            group.members
                .filter { $0.id != group.selectedMemberID }
                .compactMap { liveWindow(for: $0)?.window }
                .filter { $0.processID == app.processIdentifier }
        }
        guard !concealable.isEmpty else { return false }
        return AXWindow.windows(ofProcess: app.processIdentifier).allSatisfy { window in
            if window.isMinimized || window.isFinderDesktop { return true }
            if let bounds = window.bounds(), bounds.width <= 80 || bounds.height <= 60 { return true }
            return concealable.contains { $0.isSameWindow(as: window.element) }
        }
    }
}

// MARK: - Windows that close and apps that quit

extension GroupCoordinator {
    /// A member window reported itself destroyed. Checked again a moment later: some apps rebuild a
    /// window (for example around full screen) and the handle can still answer.
    func memberWindowClosed(groupID: UUID, memberID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.isPoweringOff,
                  let group = self.store.groups.first(where: { $0.id == groupID }),
                  let member = group.members.first(where: { $0.id == memberID }) else { return }
            if let live = self.liveWindow(for: member), !live.window.isInvalid { return }
            self.dropClosedMembers([memberID], from: groupID)
        }
    }

    /// An app quit: its tabs leave their groups, and a group whose visible tab it was shows the next one.
    func applicationTerminated(processID: pid_t) {
        guard !isPoweringOff else { return }
        availableWindows.removeAll { $0.window.processID == processID }
        for group in store.groups {
            let gone = group.members.filter { member in
                registry.handleProcessID(for: member.id) == processID
                    || (registry.handleProcessID(for: member.id) == nil && member.processID == processID)
            }
            guard !gone.isEmpty else { continue }
            dropClosedMembers(Set(gone.map(\.id)), from: group.id)
        }
    }

    /// Takes closed windows out of a group. A group left with one tab dissolves; otherwise the next
    /// tab comes forward when the visible one was closed.
    private func dropClosedMembers(_ memberIDs: Set<UUID>, from groupID: UUID) {
        guard var group = store.groups.first(where: { $0.id == groupID }) else { return }
        let wasSelected = group.selectedMemberID.map(memberIDs.contains) ?? false
        let processIDs = Set(memberIDs.compactMap { registry.handleProcessID(for: $0) })
        memberIDs.forEach { registry.forget(memberID: $0) }
        // Stale scan entries of the closed windows must not be matched back into the group.
        availableWindows.removeAll { processIDs.contains($0.window.processID) && $0.window.isInvalid }
        group.members.removeAll { memberIDs.contains($0.id) }

        guard group.members.count >= 2 else {
            let last = group.members.first.flatMap { liveWindow(for: $0)?.window }
            deleteGroup(group)
            if wasSelected { last?.raise() }
            statusMessage = "\(group.name) was ungrouped: only one window was left."
            return
        }
        if wasSelected {
            group.selectedMemberID = (group.members.first { liveWindow(for: $0) != nil } ?? group.members.first)?.id
        }
        guard persist(group) else { return }
        if wasSelected, let selected = group.selectedMemberID,
           group.members.contains(where: { $0.id == selected && liveWindow(for: $0) != nil }) {
            select(groupID: groupID, memberID: selected)
        } else {
            show(group)
        }
    }
}
