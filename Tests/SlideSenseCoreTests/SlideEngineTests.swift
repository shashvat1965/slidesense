import CoreGraphics
import XCTest
@testable import SlideSenseCore

private final class Recorder: SlideEngineDelegate {
    var begins: [EdgeAction] = []
    var updates: [(EdgeAction, Double)] = []
    var ends: [(EdgeAction, Double)] = []
    var ticks: [(EdgeAction, Double)] = []
    var commands: [MediaCommand] = []

    func slideEngine(_ engine: SlideEngine, didBeginSlide target: EdgeAction) {
        begins.append(target)
    }

    func slideEngine(_ engine: SlideEngine, didUpdateSlide target: EdgeAction, level: Double) {
        updates.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didEndSlide target: EdgeAction, level: Double) {
        ends.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didTick target: EdgeAction, level: Double) {
        ticks.append((target, level))
    }

    func slideEngine(_ engine: SlideEngine, didRecognize command: MediaCommand) {
        commands.append(command)
    }
}

final class SlideEngineTests: XCTestCase {
    private func makeEngine(_ configure: (inout EngineConfiguration) -> Void = { _ in }) -> (SlideEngine, Recorder) {
        let engine = SlideEngine()
        var config = EngineConfiguration()
        config.mediaStripEnabled = true
        configure(&config)
        engine.configuration = { config }
        engine.modifiers = { [] }
        engine.secondsSinceLastKeyPress = { .infinity }
        let recorder = Recorder()
        engine.delegate = recorder
        return (engine, recorder)
    }

    private func frame(at time: TimeInterval, x: Double, y: Double, touching: Bool = true) -> TouchFrame {
        TouchFrame(timestamp: time, contacts: [TouchContact(id: 1, x: x, y: y, isTouching: touching)])
    }

    func testRightSlideSenseChangesVolume() {
        var config = EngineConfiguration()
        config.currentVolume = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        engine.process(frame(at: 0.04, x: 0.95, y: 0.6))

        XCTAssertEqual(recorder.begins, [.volume])
        XCTAssertGreaterThan(recorder.updates.last?.1 ?? 0, 0.5)
        XCTAssertEqual(recorder.ends.count, 0) // still touching
    }

    func testLeftSlideSenseChangesBrightness() {
        var config = EngineConfiguration()
        config.currentBrightness = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.05, y: 0.8))
        engine.process(frame(at: 0.02, x: 0.05, y: 0.6))

        XCTAssertEqual(recorder.begins, [.brightness])
        XCTAssertEqual(recorder.updates.last?.1 ?? 1, 0.25, accuracy: 0.001)
    }

    func testMiddleTouchIsIgnored() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.5, y: 0.5))
        engine.process(frame(at: 0.02, x: 0.55, y: 0.55))
        XCTAssertTrue(recorder.begins.isEmpty)
        XCTAssertTrue(recorder.updates.isEmpty)
    }

    func testSecondFingerCancelsSlide() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        let twoFingers = TouchFrame(timestamp: 0.04, contacts: [
            TouchContact(id: 1, x: 0.95, y: 0.5, isTouching: true),
            TouchContact(id: 2, x: 0.5, y: 0.5, isTouching: true)
        ])
        engine.process(twoFingers)
        XCTAssertEqual(recorder.ends.count, 1)
    }

    func testLevelStopsAtBounds() {
        var config = EngineConfiguration()
        config.currentVolume = 0.9
        let (engine, recorder) = makeEngine { $0 = config }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 1.0))
        XCTAssertEqual(recorder.updates.last?.1 ?? 0, 1.0, accuracy: 0.001)
    }

    func testDoubleTapCornerMutes() {
        let (engine, recorder) = makeEngine()
        for index in 0..<2 {
            let base = Double(index) * 0.2
            engine.process(frame(at: base + 0.00, x: 0.95, y: 0.95))
            engine.process(frame(at: base + 0.05, x: 0.95, y: 0.95))
            engine.process(frame(at: base + 0.08, x: 0.95, y: 0.95, touching: false))
        }
        XCTAssertEqual(recorder.commands, [.mute])
    }

    func testSingleCornerTapDoesNotMute() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.05, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.08, x: 0.95, y: 0.95, touching: false))
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testBottomStripSwipeSendsNext() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.8, y: 0.05))
        engine.process(frame(at: 0.02, x: 0.6, y: 0.05))
        engine.process(frame(at: 0.04, x: 0.4, y: 0.05))
        XCTAssertEqual(recorder.commands, [.next])
    }

    func testBottomStripReverseFlipsDirection() {
        let (engine, recorder) = makeEngine { $0.mediaStripReverse = true }
        engine.process(frame(at: 0.0, x: 0.2, y: 0.05))
        engine.process(frame(at: 0.04, x: 0.6, y: 0.05))
        XCTAssertEqual(recorder.commands, [.next])
    }

    func testDroppedContactKeepsSlideAlive() {
        let (engine, recorder) = makeEngine()
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        // One stray frame with no contacts should not end the gesture.
        engine.process(TouchFrame(timestamp: 0.04, contacts: []))
        engine.process(frame(at: 0.05, x: 0.95, y: 0.55))
        XCTAssertEqual(recorder.begins.count, 1)
        XCTAssertEqual(recorder.ends.count, 0)
        XCTAssertGreaterThan(recorder.updates.last?.1 ?? 0, 0.5)
    }

    func testFineControlUsesQuarterSteps() {
        var config = EngineConfiguration()
        config.preciseSliding = true
        config.currentVolume = 0.5
        let (engine, recorder) = makeEngine { $0 = config }

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.25))
        guard let level = recorder.updates.last?.1 else {
            return XCTFail("expected an update")
        }
        // Quarter steps land on multiples of 1/64.
        let scaled = level * 64
        XCTAssertEqual(scaled.rounded(), scaled, accuracy: 0.0001)
    }

    func testRequiredModifierBlocksSlide() {
        let engine = SlideEngine()
        var config = EngineConfiguration()
        config.requireModifier = .option
        engine.configuration = { config }
        engine.modifiers = { [] }
        engine.secondsSinceLastKeyPress = { .infinity }
        let recorder = Recorder()
        engine.delegate = recorder

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertTrue(recorder.updates.isEmpty)
    }

    // MARK: - Mistouch guards

    private func contact(at time: TimeInterval, x: Double, y: Double, size: Double) -> TouchFrame {
        TouchFrame(timestamp: time, contacts: [TouchContact(id: 1, x: x, y: y, isTouching: true, size: size)])
    }

    func testBottomQuarterIgnoresSlidesStartingHigh() {
        let (engine, recorder) = makeEngine { $0.bottomQuarterOnly = true }
        engine.process(frame(at: 0.0, x: 0.05, y: 0.6))
        engine.process(frame(at: 0.02, x: 0.05, y: 0.3))
        engine.process(frame(at: 0.04, x: 0.05, y: 0.1))
        XCTAssertTrue(recorder.begins.isEmpty)
        XCTAssertTrue(recorder.updates.isEmpty)
    }

    func testBottomQuarterSlideCanTravelFullHeight() {
        let (engine, recorder) = makeEngine {
            $0.bottomQuarterOnly = true
            $0.currentVolume = 0.0
        }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.1))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.5))
        let midway = recorder.updates.last?.1 ?? 0
        engine.process(frame(at: 0.04, x: 0.95, y: 0.9))
        XCTAssertEqual(recorder.begins, [.volume])
        // Normal speed: half the pad is roughly half the range, not all of it.
        XCTAssertLessThan(midway, 0.7)
        XCTAssertEqual(recorder.updates.last?.1 ?? 0, 1.0, accuracy: 0.0001)
    }

    func testBottomQuarterBlocksCornerSlide() {
        let (engine, recorder) = makeEngine {
            $0.bottomQuarterOnly = true
            $0.quickMuteEnabled = true
        }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.95))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.7))
        XCTAssertTrue(recorder.begins.isEmpty)
    }

    func testRecentKeyPressIgnoresTouch() {
        let (engine, recorder) = makeEngine()
        var sinceKey: TimeInterval = 0.2
        engine.secondsSinceLastKeyPress = { sinceKey }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        sinceKey = 5 // typing stopped mid-touch: still ignored until lift
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertTrue(recorder.begins.isEmpty)
    }

    func testOldKeyPressAllowsSlide() {
        let (engine, recorder) = makeEngine()
        engine.secondsSinceLastKeyPress = { 2 }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertEqual(recorder.begins, [.volume])
    }

    func testKeyPressDoesNotCancelMovingSlide() {
        let (engine, recorder) = makeEngine()
        var sinceKey: TimeInterval = 5
        engine.secondsSinceLastKeyPress = { sinceKey }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.4))
        sinceKey = 0
        engine.process(frame(at: 0.04, x: 0.95, y: 0.6))
        XCTAssertEqual(recorder.updates.count, 2)
    }

    func testTypingGuardCanBeDisabled() {
        let (engine, recorder) = makeEngine { $0.ignoreWhileTyping = false }
        engine.secondsSinceLastKeyPress = { 0 }
        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertEqual(recorder.begins, [.volume])
    }

    func testPalmSizedContactIsIgnored() {
        let (engine, recorder) = makeEngine()
        engine.process(contact(at: 0.0, x: 0.95, y: 0.2, size: 4))
        engine.process(contact(at: 0.02, x: 0.95, y: 0.6, size: 4))
        XCTAssertTrue(recorder.begins.isEmpty)
    }

    func testContactThatGrowsBeforeMovingIsIgnored() {
        let (engine, recorder) = makeEngine()
        engine.process(contact(at: 0.0, x: 0.95, y: 0.2, size: 0.8))
        engine.process(contact(at: 0.01, x: 0.95, y: 0.202, size: 3))
        engine.process(contact(at: 0.03, x: 0.95, y: 0.6, size: 3))
        XCTAssertTrue(recorder.begins.isEmpty)
    }

    func testFingerSizedContactSlides() {
        let (engine, recorder) = makeEngine()
        engine.process(contact(at: 0.0, x: 0.95, y: 0.2, size: 0.8))
        engine.process(contact(at: 0.02, x: 0.95, y: 0.6, size: 0.9))
        XCTAssertEqual(recorder.begins, [.volume])
    }
}
