import CoreGraphics
import Foundation

/// A snapshot of everything the gesture engine needs for one frame.
public struct EngineConfiguration: Equatable, Sendable {
    public var leftEdge: EdgeAction = .brightness
    public var rightEdge: EdgeAction = .volume
    public var edgeWidth: Double = 0.18
    public var bottomQuarterOnly: Bool = false
    public var sensitivity: Double = 1.0
    public var currentBrightness: Double = 0.5
    public var currentVolume: Double = 0.5
    public var mediaStripEnabled: Bool = true
    public var mediaStripReverse: Bool = false
    public var quickMuteEnabled: Bool = true
    public var tapToPlayEnabled: Bool = false
    public var requireModifier: ModifierRequirement = .none
    public var fineControlWithModifiers: Bool = true
    public var preciseSliding: Bool = false
    /// Ignore edge touches that start right after a key press.
    public var ignoreWhileTyping: Bool = true
    /// How long after the last key press an edge touch is still ignored.
    public var typingGuardInterval: TimeInterval = 0.5
    /// Ignore contacts too large to be a fingertip (palms, thumb sides).
    public var palmRejection: Bool = true
    /// Largest `TouchContact.size` still treated as a finger.
    public var maxFingerSize: Double = 1.6

    public init() {}
}

/// Things the engine can ask the app to do.
public enum MediaCommand: Sendable, Equatable {
    case playPause
    case next
    case previous
    case mute
}

public protocol SlideEngineDelegate: AnyObject {
    func slideEngine(_ engine: SlideEngine, didBeginSlide target: EdgeAction)
    func slideEngine(_ engine: SlideEngine, didUpdateSlide target: EdgeAction, level: Double)
    func slideEngine(_ engine: SlideEngine, didEndSlide target: EdgeAction, level: Double)
    /// Fired once every time the level crosses a haptic step.
    func slideEngine(_ engine: SlideEngine, didTick target: EdgeAction, level: Double)
    func slideEngine(_ engine: SlideEngine, didRecognize command: MediaCommand)
}

/// Turns raw contact frames into edge-slide gestures.
///
/// The engine is deliberately free of AppKit: it is fed `TouchFrame`s and
/// emits semantic events, which makes the messy part unit-testable.
public final class SlideEngine {
    public weak var delegate: SlideEngineDelegate?

    /// Live configuration (levels are read when a slide begins).
    public var configuration: () -> EngineConfiguration = { EngineConfiguration() }
    /// Live modifier state, used for the "require modifier" and fine-control options.
    public var modifiers: () -> ModifierState = { .current }
    /// Seconds since the last key press, used for the "ignore while typing" guard.
    public var secondsSinceLastKeyPress: () -> TimeInterval = { KeyboardActivity.secondsSinceLastKeyPress }

    private enum Kind {
        case slider(target: EdgeAction, edge: Edge, startLevel: Double)
        case media
        case corner
        case ignored
    }

    private struct Gesture {
        var kind: Kind
        var startX: Double
        var startY: Double
        var startTime: TimeInterval
        var lastX: Double
        var lastY: Double
        var lastSeen: TimeInterval
        var moved: Bool
        var emittedLevel: Double
        var lastStep: Int
        var consumed: Bool
        var lostFrames: Int
    }

    private var gesture: Gesture?
    private var lastCornerTap: TimeInterval = -10
    private var lastMediaTap: TimeInterval = -10

    public init() {}

    /// True while a finger is being tracked (used to keep the cursor frozen).
    public var isTrackingSlide: Bool {
        guard let gesture else { return false }
        if case .slider = gesture.kind { return gesture.moved }
        return false
    }

    // MARK: - Frame processing

    public func process(_ frame: TouchFrame) {
        let config = configuration()
        let active = frame.activeContacts

        if var current = gesture {
            if active.isEmpty {
                current.lostFrames += 1
                // A tap ends the moment the finger lifts; a slide survives a
                // few dropped frames so it does not stop halfway (1.8 fix).
                if !current.moved || current.lostFrames > 5 || frame.timestamp - current.lastSeen > 0.12 {
                    finish(current, at: frame.timestamp, config: config)
                    gesture = nil
                }
                return
            }

            guard active.count == 1, let point = active.first else {
                // Extra fingers mean the user wants a system gesture.
                cancel(current)
                gesture = nil
                return
            }

            // Palms tend to land edge-first and then spread, so keep checking
            // the contact size until the slide has actually started.
            if !current.moved, isPalm(point, config: config) {
                current.kind = .ignored
            }

            current.lostFrames = 0
            current.lastX = point.x
            current.lastY = point.y
            current.lastSeen = frame.timestamp
            update(&current, point: CGPoint(x: point.x, y: point.y), now: frame.timestamp, config: config)
            gesture = current
            return
        }

        guard active.count == 1, let point = active.first else { return }
        begin(contact: point, now: frame.timestamp, config: config)
    }

    /// Drops any in-flight gesture (e.g. the app was disabled).
    public func reset() {
        if let current = gesture { cancel(current) }
        gesture = nil
    }

    // MARK: - Gesture lifecycle

    private func begin(contact: TouchContact, now: TimeInterval, config: EngineConfiguration) {
        let point = CGPoint(x: contact.x, y: contact.y)
        guard ModifierState.modifierRequirementSatisfied(config.requireModifier, by: modifiers()) else {
            gesture = makeGesture(kind: .ignored, point: point, now: now, level: 0, fine: false, config: config)
            return
        }

        // Mistouch guards: a touch that starts mid-typing or is palm-sized is
        // ignored until it lifts. Neither check runs again once a slide moves.
        if config.ignoreWhileTyping, secondsSinceLastKeyPress() < config.typingGuardInterval {
            gesture = makeGesture(kind: .ignored, point: point, now: now, level: 0, fine: false, config: config)
            return
        }
        if isPalm(contact, config: config) {
            gesture = makeGesture(kind: .ignored, point: point, now: now, level: 0, fine: false, config: config)
            return
        }

        let geometry = EdgeGeometry(edgeWidth: config.edgeWidth, bottomQuarterOnly: config.bottomQuarterOnly)
        let fine = isFine(config: config)

        if config.quickMuteEnabled, geometry.isQuickMuteCorner(point) {
            gesture = makeGesture(kind: .corner, point: point, now: now, level: 0, fine: fine, config: config)
            return
        }

        guard let edge = geometry.edge(at: point) else {
            gesture = makeGesture(kind: .ignored, point: point, now: now, level: 0, fine: fine, config: config)
            return
        }

        switch edge {
        case .bottom:
            guard config.mediaStripEnabled else {
                gesture = makeGesture(kind: .ignored, point: point, now: now, level: 0, fine: fine, config: config)
                return
            }
            gesture = makeGesture(kind: .media, point: point, now: now, level: 0, fine: fine, config: config)
        case .left, .right:
            let target = edge == .left ? config.leftEdge : config.rightEdge
            let level = target == .volume ? config.currentVolume : config.currentBrightness
            gesture = makeGesture(
                kind: .slider(target: target, edge: edge, startLevel: level),
                point: point,
                now: now,
                level: level,
                fine: fine,
                config: config
            )
        }
    }

    private func update(_ gesture: inout Gesture, point: CGPoint, now: TimeInterval, config: EngineConfiguration) {
        let dx = point.x - gesture.startX
        let dy = point.y - gesture.startY

        // Touching down inside the Quick Mute corner and then sliding is a
        // volume/brightness slide, not a failed tap. Not in bottom-quarter
        // mode, where the corner is at the top and slides must start low.
        if case .corner = gesture.kind, !config.bottomQuarterOnly, abs(dy) > 0.012 {
            let target = config.rightEdge
            let level = target == .volume ? config.currentVolume : config.currentBrightness
            let steps = isFine(config: config) ? 64.0 : 16.0
            gesture.kind = .slider(target: target, edge: .right, startLevel: level)
            gesture.emittedLevel = (level * steps).rounded() / steps
            gesture.lastStep = Int((level * steps).rounded())
            update(&gesture, point: point, now: now, config: config)
            return
        }

        switch gesture.kind {
        case let .slider(target, edge, startLevel):
            guard abs(dy) > 0.006 else { return }
            if !gesture.moved {
                gesture.moved = true
                delegate?.slideEngine(self, didBeginSlide: target)
            }

            let geometry = EdgeGeometry(edgeWidth: config.edgeWidth, bottomQuarterOnly: config.bottomQuarterOnly)
            let span = geometry.travelSpan(for: edge)
            let raw = startLevel + (dy / span) * config.sensitivity
            let clamped = min(max(raw, 0), 1)

            let steps = isFine(config: config) ? 64.0 : 16.0
            let snapped = (clamped * steps).rounded() / steps

            if snapped != gesture.emittedLevel {
                gesture.emittedLevel = snapped
                delegate?.slideEngine(self, didUpdateSlide: target, level: snapped)
            }

            let step = Int((snapped * steps).rounded())
            if step != gesture.lastStep {
                gesture.lastStep = step
                delegate?.slideEngine(self, didTick: target, level: snapped)
            }

        case .media:
            guard config.mediaStripEnabled else { return }
            if abs(dx) > 0.02 { gesture.moved = true }
            guard abs(dx) > 0.12, !gesture.consumed else { return }
            gesture.consumed = true
            // Swiping left means "forward" on the media strip.
            var forward = dx < 0
            if config.mediaStripReverse { forward.toggle() }
            delegate?.slideEngine(self, didRecognize: forward ? .next : .previous)

        case .corner, .ignored:
            break
        }
    }

    private func finish(_ gesture: Gesture, at now: TimeInterval, config: EngineConfiguration) {
        let duration = now - gesture.startTime
        let travel = hypot(gesture.lastX - gesture.startX, gesture.lastY - gesture.startY)
        let isTap = !gesture.moved && duration < 0.4 && travel < 0.03

        switch gesture.kind {
        case let .slider(target, _, _):
            if gesture.moved {
                delegate?.slideEngine(self, didEndSlide: target, level: gesture.emittedLevel)
            }

        case .media:
            if isTap, config.tapToPlayEnabled {
                if now - lastMediaTap < 0.45 {
                    lastMediaTap = -10
                    delegate?.slideEngine(self, didRecognize: .playPause)
                } else {
                    lastMediaTap = now
                }
            }

        case .corner:
            if isTap {
                if now - lastCornerTap < 0.45 {
                    lastCornerTap = -10
                    delegate?.slideEngine(self, didRecognize: .mute)
                } else {
                    lastCornerTap = now
                }
            }

        case .ignored:
            break
        }
    }

    private func cancel(_ gesture: Gesture) {
        if case let .slider(target, _, _) = gesture.kind, gesture.moved {
            delegate?.slideEngine(self, didEndSlide: target, level: gesture.emittedLevel)
        }
    }

    // MARK: - Helpers

    private func makeGesture(
        kind: Kind,
        point: CGPoint,
        now: TimeInterval,
        level: Double,
        fine: Bool,
        config: EngineConfiguration
    ) -> Gesture {
        let steps = fine ? 64.0 : 16.0
        return Gesture(
            kind: kind,
            startX: point.x,
            startY: point.y,
            startTime: now,
            lastX: point.x,
            lastY: point.y,
            lastSeen: now,
            moved: false,
            emittedLevel: (level * steps).rounded() / steps,
            lastStep: Int((level * steps).rounded()),
            consumed: false,
            lostFrames: 0
        )
    }

    private func isPalm(_ contact: TouchContact, config: EngineConfiguration) -> Bool {
        config.palmRejection && contact.size > config.maxFingerSize
    }

    private func isFine(config: EngineConfiguration) -> Bool {
        if config.preciseSliding { return true }
        guard config.fineControlWithModifiers else { return false }
        let state = modifiers()
        return state.contains(.shift) && state.contains(.option)
    }
}

private extension ModifierState {
    /// Whether the user is holding whatever the setting asks for.
    static func modifierRequirementSatisfied(_ requirement: ModifierRequirement, by available: ModifierState) -> Bool {
        switch requirement {
        case .none: return true
        case .fn: return available.contains(.fn)
        case .option: return available.contains(.option)
        case .control: return available.contains(.control)
        }
    }
}
