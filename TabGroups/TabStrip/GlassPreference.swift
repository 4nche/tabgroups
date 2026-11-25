import Foundation

/// Which Liquid Glass look the bar uses, taken from the system's own glass setting.
enum GlassPreference {
    enum Variant: Equatable { case clear, regular }

    /// The key macOS stores its Liquid Glass tint under. It is not a documented API.
    static let systemTintKey = "NSGlassTintAmount"

    static func variant(systemTintAmount: Double?) -> Variant {
        guard let systemTintAmount else { return .regular }
        return systemTintAmount <= 0 ? .clear : .regular
    }

    static var current: Variant {
        variant(systemTintAmount: UserDefaults.standard.object(forKey: systemTintKey) as? Double)
    }
}
