import Foundation

/// Replays a slide as the 1/16 steps the volume and brightness keys use.
///
/// macOS only shows its own volume and brightness HUD for real key presses;
/// setting the level through CoreAudio or DisplayServices changes it silently.
/// With "Use macOS HUD" on, the coordinator turns each slide update into the
/// key presses returned here, so the system HUD appears exactly as it does for
/// the keyboard keys. Pure value type: no AppKit, no I/O.
public struct SystemHUDStepper: Equatable, Sendable {
    /// Key presses that cover the full 0…1 range, like the keyboard keys.
    public static let stepsPerRange = 16

    /// Level when the slide began.
    public let start: Double
    /// Net key presses handed out so far (positive = up).
    public private(set) var sent = 0

    public init(start: Double) {
        self.start = min(max(start, 0), 1)
    }

    /// Key presses still needed to follow the slide to `level`:
    /// positive = up, negative = down, zero = stay.
    public mutating func presses(toFollow level: Double) -> Int {
        let target = min(max(level, 0), 1)
        let wanted = Int(((target - start) * Double(Self.stepsPerRange)).rounded())
        let delta = wanted - sent
        sent = wanted
        return delta
    }
}
