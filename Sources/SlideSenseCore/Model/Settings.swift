import Foundation

/// What a trackpad edge controls.
public enum EdgeAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case volume
    case brightness

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        }
    }

    public var symbolName: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        }
    }

    public var toggled: EdgeAction {
        self == .volume ? .brightness : .volume
    }
}

public enum ModifierRequirement: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case fn
    case option
    case control

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "None"
        case .fn: return "FN"
        case .option: return "Option"
        case .control: return "Control"
        }
    }
}

public enum HapticStrength: String, Codable, CaseIterable, Sendable, Identifiable {
    case light
    case medium
    case strong

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Everything the user can change. Persisted as JSON in `UserDefaults`.
public struct Settings: Codable, Equatable, Sendable {
    /// Master switch – stops the touch pipeline when off.
    public var enabled: Bool = true

    // Edges
    public var leftEdge: EdgeAction = .brightness
    public var rightEdge: EdgeAction = .volume
    /// How far in from the edge, as a fraction of the trackpad width/height.
    public var edgeWidth: Double = 0.18
    /// Left/right slides must start in the lower quarter of the edge.
    public var bottomQuarterOnly: Bool = true
    /// Multiplies how far a slide has to travel to cover the full range.
    public var sensitivity: Double = 1.0
    /// Require a modifier key to be held before an edge starts responding.
    public var requireModifier: ModifierRequirement = .none
    /// Some trackpads report the vertical axis the other way round.
    public var flipVerticalEdges: Bool = false
    /// Ignore edge touches that start right after a key press.
    public var ignoreWhileTyping: Bool = true
    /// Ignore contacts too large to be a fingertip.
    public var palmRejection: Bool = true

    // Feel
    public var freezeCursor: Bool = true
    public var preciseSliding: Bool = false
    public var fineControlWithModifiers: Bool = true
    public var hapticsEnabled: Bool = true
    public var hapticStrength: HapticStrength = .medium

    // Extras
    public var quickMuteEnabled: Bool = true
    public var mediaStripEnabled: Bool = true
    public var mediaStripReverse: Bool = false
    public var tapToPlayEnabled: Bool = false

    // Appearance
    public var showHUD: Bool = true
    public var appearance: AppearanceMode = .system
    public var openAtLogin: Bool = false

    /// Set once the onboarding assistant has been shown.
    public var hasCompletedSetup: Bool = false

    /// Poll GitHub releases once a day for a newer build.
    public var automaticallyChecksForUpdates: Bool = true

    public init() {}

    /// Codable with forgiving decoding: missing keys fall back to the default
    /// value so old settings files keep working after an upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        leftEdge = try c.decodeIfPresent(EdgeAction.self, forKey: .leftEdge) ?? d.leftEdge
        rightEdge = try c.decodeIfPresent(EdgeAction.self, forKey: .rightEdge) ?? d.rightEdge
        edgeWidth = try c.decodeIfPresent(Double.self, forKey: .edgeWidth) ?? d.edgeWidth
        bottomQuarterOnly = try c.decodeIfPresent(Bool.self, forKey: .bottomQuarterOnly) ?? d.bottomQuarterOnly
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        requireModifier = try c.decodeIfPresent(ModifierRequirement.self, forKey: .requireModifier) ?? d.requireModifier
        flipVerticalEdges = try c.decodeIfPresent(Bool.self, forKey: .flipVerticalEdges) ?? d.flipVerticalEdges
        ignoreWhileTyping = try c.decodeIfPresent(Bool.self, forKey: .ignoreWhileTyping) ?? d.ignoreWhileTyping
        palmRejection = try c.decodeIfPresent(Bool.self, forKey: .palmRejection) ?? d.palmRejection
        freezeCursor = try c.decodeIfPresent(Bool.self, forKey: .freezeCursor) ?? d.freezeCursor
        preciseSliding = try c.decodeIfPresent(Bool.self, forKey: .preciseSliding) ?? d.preciseSliding
        fineControlWithModifiers = try c.decodeIfPresent(Bool.self, forKey: .fineControlWithModifiers) ?? d.fineControlWithModifiers
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        hapticStrength = try c.decodeIfPresent(HapticStrength.self, forKey: .hapticStrength) ?? d.hapticStrength
        quickMuteEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickMuteEnabled) ?? d.quickMuteEnabled
        mediaStripEnabled = try c.decodeIfPresent(Bool.self, forKey: .mediaStripEnabled) ?? d.mediaStripEnabled
        mediaStripReverse = try c.decodeIfPresent(Bool.self, forKey: .mediaStripReverse) ?? d.mediaStripReverse
        tapToPlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .tapToPlayEnabled) ?? d.tapToPlayEnabled
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? d.appearance
        openAtLogin = try c.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? d.openAtLogin
        hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? d.hasCompletedSetup
        automaticallyChecksForUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates)
            ?? d.automaticallyChecksForUpdates
    }

    /// The action configured for a given edge.
    public func action(for edge: Edge) -> EdgeAction? {
        switch edge {
        case .left: return leftEdge
        case .right: return rightEdge
        case .bottom: return nil
        }
    }

    public var swapped: Bool {
        get { leftEdge == .volume }
        set {
            leftEdge = newValue ? .volume : .brightness
            rightEdge = newValue ? .brightness : .volume
        }
    }
}

/// Observable wrapper around `Settings` that persists on every change.
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private static let key = "io.github.slidesense.settings.v1"

    @Published public var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
            NotificationCenter.default.post(name: .slideSenseSettingsDidChange, object: self)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func resetToDefaults() {
        settings = Settings()
    }
}

public extension Notification.Name {
    static let slideSenseSettingsDidChange = Notification.Name("io.github.slidesense.settingsDidChange")
    /// Posted by the settings window when the user asks for an update check.
    static let slideSenseCheckForUpdates = Notification.Name("io.github.slidesense.checkForUpdates")
}
