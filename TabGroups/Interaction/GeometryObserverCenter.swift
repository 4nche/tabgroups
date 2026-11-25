import ApplicationServices
import Foundation

private final class ObserverContext {
    weak var center: GeometryObserverCenter?
    let groupID: UUID
    let memberID: UUID

    init(center: GeometryObserverCenter, groupID: UUID, memberID: UUID) {
        self.center = center
        self.groupID = groupID
        self.memberID = memberID
    }
}

private let observerCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    context.center?.onChange?(context.groupID, context.memberID)
}

/// Watches member windows for moves and resizes made by anything: the mouse, a window manager, the app.
final class GeometryObserverCenter {
    private struct Registration {
        let observer: AXObserver
        let source: CFRunLoopSource
        let context: ObserverContext   // kept alive here; the callback holds it unretained
        let groupID: UUID
        let window: AXWindow
    }

    var onChange: ((_ groupID: UUID, _ memberID: UUID) -> Void)?
    private var registrations: [UUID: Registration] = [:]

    func observe(group: TabGroup, resolve: (WindowReference) -> DiscoveredWindow?) {
        let memberIDs = Set(group.members.map(\.id))
        registrations
            .filter { $0.value.groupID == group.id && !memberIDs.contains($0.key) }
            .keys.forEach(stop(memberID:))

        for member in group.members {
            guard let live = resolve(member) else {
                stop(memberID: member.id)
                continue
            }
            if let existing = registrations[member.id], existing.groupID == group.id,
               existing.window.isSameWindow(as: live.window.element) { continue }
            stop(memberID: member.id)
            if let registration = register(live.window, groupID: group.id, memberID: member.id) {
                registrations[member.id] = registration
            }
        }
    }

    func stop(groupID: UUID) {
        registrations.filter { $0.value.groupID == groupID }.keys.forEach(stop(memberID:))
    }

    private func stop(memberID: UUID) {
        guard let registration = registrations.removeValue(forKey: memberID) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), registration.source, .commonModes)
    }

    private func register(_ window: AXWindow, groupID: UUID, memberID: UUID) -> Registration? {
        var created: AXObserver?
        guard AXObserverCreate(window.processID, observerCallback, &created) == .success,
              let observer = created else { return nil }
        let context = ObserverContext(center: self, groupID: groupID, memberID: memberID)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        let moved = AXObserverAddNotification(observer, window.element, kAXMovedNotification as CFString, pointer)
        let resized = AXObserverAddNotification(observer, window.element, kAXResizedNotification as CFString, pointer)
        guard moved == .success || resized == .success else { return nil }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return Registration(observer: observer, source: source, context: context, groupID: groupID, window: window)
    }
}
