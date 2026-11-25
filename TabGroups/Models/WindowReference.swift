import Foundation

/// A durable description of an app window. `processID` is only a hint for the
/// current login session; the app must be able to reconnect without it.
struct WindowReference: Codable, Identifiable, Equatable {
    var id: UUID
    var bundleIdentifier: String
    var processID: Int32?
    var accessibilityIdentifier: String?
    var title: String?
    var lastKnownBounds: WindowBounds

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        processID: Int32? = nil,
        accessibilityIdentifier: String? = nil,
        title: String? = nil,
        lastKnownBounds: WindowBounds
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.accessibilityIdentifier = accessibilityIdentifier
        self.title = title
        self.lastKnownBounds = lastKnownBounds
    }
}

struct WindowBounds: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
