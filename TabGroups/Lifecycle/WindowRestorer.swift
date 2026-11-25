import AppKit

final class WindowRestorer {
    private let restore: () -> Void
    private var tokens: [NSObjectProtocol] = []

    init(restore: @escaping () -> Void) { self.restore = restore }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        tokens = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard name != NSWorkspace.didTerminateApplicationNotification else {
                    self?.restore()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.restore() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: restore)
    }

    deinit {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
