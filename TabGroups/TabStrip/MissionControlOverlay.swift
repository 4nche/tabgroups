import AppKit
import ApplicationServices
import SwiftUI

/// One group as Mission Control should present it: the window it shows and the tabs behind it.
struct MissionControlGroup {
    let groupID: UUID
    let windowTitle: String?
    let windowBounds: WindowBounds
    let tabs: [TabItem]
    let selectedID: UUID?
}

private let dockCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let overlay = Unmanaged<MissionControlOverlay>.fromOpaque(refcon).takeUnretainedValue()
    overlay.dockPosted(notification as String)
}

/// Mission Control and App Exposé only show real windows, so a group shows up there as its one visible
/// window. While either is open, this lays the group's tabs on top of that window's thumbnail, with a
/// hint of the stacked windows behind it. The Dock publishes each thumbnail's place on screen through
/// Accessibility; that is how the bar finds its window.
final class MissionControlOverlay {
    var groups: () -> [MissionControlGroup] = { [] }
    var onSelect: (_ groupID: UUID, _ memberID: UUID) -> Void = { _, _ in }

    private static let refreshInterval: TimeInterval = 0.15
    private static let idlePollInterval: TimeInterval = 0.5
    private static let missesBeforeClosing = 4

    private var observer: AXObserver?
    private var dockApp: AXUIElement?
    private var panels: [UUID: MissionControlTabPanel] = [:]
    private var refreshTimer: Timer?
    private var idleTimer: Timer?
    private var misses = 0
    private var dockLaunchToken: NSObjectProtocol?

    func start() {
        attachToDock()
        dockLaunchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.dock" { self?.attachToDock() }
        }
        // The Dock's notifications are the quick path; a light poll catches any it does not send.
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idlePollInterval, repeats: true) { [weak self] _ in
            guard let self, self.refreshTimer == nil, self.dockShowsOverview() else { return }
            self.begin()
        }
    }

    deinit {
        if let dockLaunchToken { NSWorkspace.shared.notificationCenter.removeObserver(dockLaunchToken) }
    }

    fileprivate func dockPosted(_ notification: String) {
        switch notification {
        case "AXExposeShowAllWindows", "AXExposeShowFrontWindows": begin()
        default: end()
        }
    }

    private func attachToDock() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, LiveWindowRegistry.messagingTimeout)
        dockApp = app
        var created: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, dockCallback, &created) == .success,
              let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"] {
            _ = AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    // MARK: - While the overview is open

    private func begin() {
        guard refreshTimer == nil else { return }
        misses = 0
        refresh()
        // Thumbnails slide into place and move again when the pointer visits the Spaces bar.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func end() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        panels.values.forEach { $0.orderOut(nil) }
    }

    private func refresh() {
        let thumbnails = currentThumbnails()
        guard !thumbnails.isEmpty else {
            misses += 1
            if misses >= Self.missesBeforeClosing { end() }
            return
        }
        misses = 0
        if UserDefaults.standard.bool(forKey: "MissionControlDebug") { Self.writeDebug(thumbnails, groups()) }
        var used = Set<Int>()
        var shown = Set<UUID>()
        for group in groups() where group.tabs.count > 1 {
            guard let index = Self.bestThumbnail(for: group, among: thumbnails, excluding: used) else { continue }
            used.insert(index)
            shown.insert(group.groupID)
            let panel = panels[group.groupID] ?? MissionControlTabPanel()
            panels[group.groupID] = panel
            panel.show(group: group, over: thumbnails[index].frame) { [weak self] memberID in
                self?.choose(groupID: group.groupID, memberID: memberID)
            }
        }
        panels.filter { !shown.contains($0.key) }.values.forEach { $0.orderOut(nil) }
    }

    private func choose(groupID: UUID, memberID: UUID) {
        end()
        // Escape closes Mission Control and App Exposé alike; the tab is selected once it has gone.
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.onSelect(groupID, memberID)
        }
    }

    private static func writeDebug(_ thumbnails: [Thumbnail], _ groups: [MissionControlGroup]) {
        let lines = thumbnails.map { "thumb '\($0.title)' \($0.frame)" }
            + groups.map { "group title='\($0.windowTitle ?? "")' bounds=\($0.windowBounds) tabs=\($0.tabs.map(\.appName))" }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TabGroups/mission-control-debug.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Reading the Dock

    struct Thumbnail {
        let title: String
        let frame: WindowBounds
    }

    /// True when the Dock shows more than its own bar, which is the case while an overview is open.
    private func dockShowsOverview() -> Bool {
        guard let dockApp else { return false }
        let children = Self.children(of: dockApp)
        return children.contains { Self.role(of: $0) != "AXList" }
    }

    private func currentThumbnails() -> [Thumbnail] {
        guard let dockApp else { return [] }
        var found: [Thumbnail] = []
        for child in Self.children(of: dockApp) where Self.role(of: child) != "AXList" {
            Self.collect(in: child, depth: 0, into: &found)
        }
        return found
    }

    private static func collect(in element: AXUIElement, depth: Int, into found: inout [Thumbnail]) {
        guard depth < 8 else { return }
        if role(of: element) == "AXButton", let frame = frame(of: element),
           frame.width > 60, frame.height > 40 {
            found.append(Thumbnail(title: string(element, kAXTitleAttribute) ?? "", frame: frame))
            return
        }
        children(of: element).forEach { collect(in: $0, depth: depth + 1, into: &found) }
    }

    /// The thumbnail with the group's window title; among several, the one whose shape matches best.
    static func bestThumbnail(for group: MissionControlGroup, among thumbnails: [Thumbnail],
                              excluding used: Set<Int>) -> Int? {
        let aspect = group.windowBounds.width / max(group.windowBounds.height, 1)
        let candidates = thumbnails.indices.filter { index in
            !used.contains(index) && !(group.windowTitle ?? "").isEmpty && thumbnails[index].title == group.windowTitle
        }
        return candidates.min { a, b in
            let frameA = thumbnails[a].frame, frameB = thumbnails[b].frame
            return abs(frameA.width / max(frameA.height, 1) - aspect) < abs(frameB.width / max(frameB.height, 1) - aspect)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> WindowBounds? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return WindowBounds(x: point.x, y: point.y, width: extent.width, height: extent.height)
    }
}

// MARK: - The bar over a thumbnail

private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floats above Mission Control itself, on every Space, and never takes focus.
final class MissionControlTabPanel: NSPanel {
    static let height: CGFloat = 52
    private let host = OverlayHostingView(rootView: MissionControlTabsView(tabs: [], selectedID: nil, onSelect: { _ in }))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: Self.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = host
    }

    func show(group: MissionControlGroup, over thumbnail: WindowBounds, onSelect: @escaping (UUID) -> Void) {
        host.rootView = MissionControlTabsView(tabs: group.tabs, selectedID: group.selectedID, onSelect: onSelect)
        let width = max(thumbnail.width, 240)
        let area = WindowBounds(x: thumbnail.x + (thumbnail.width - width) / 2,
                                y: thumbnail.y - Double(Self.height) + 2,
                                width: width, height: Double(Self.height))
        let target = ScreenGeometry.appKitRect(for: area)
        if frame != target { setFrame(target, display: true) }
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        if alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                animator().alphaValue = 1
            }
        }
    }
}

/// A glass pill of tabs sitting on two slivers of "cards", so the thumbnail reads as a stack of windows.
struct MissionControlTabsView: View {
    let tabs: [TabItem]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                pill
                    .frame(maxWidth: proxy.size.width - 8)
                    .padding(.bottom, 4)
                stackEdge(width: proxy.size.width * 0.86, opacity: 0.28)
                stackEdge(width: proxy.size.width * 0.93, opacity: 0.45)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var pill: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                MissionControlTabChip(tab: tab, isSelected: tab.id == selectedID) { onSelect(tab.id) }
            }
        }
        .padding(3)
        .background(PillSurface())
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stackEdge(width: CGFloat, opacity: Double) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: 4)
    }
}

private struct PillSurface: View {
    var body: some View {
        let shape = Capsule()
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
    }
}

private struct MissionControlTabChip: View {
    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = tab.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(tab.appName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.9)
                                          : Color.primary.opacity(hovering ? 0.12 : 0))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
