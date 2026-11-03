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

    private func tap(_ engine: SlideEngine, at time: TimeInterval, x: Double, y: Double) {
        engine.process(frame(at: time, x: x, y: y))
        engine.process(frame(at: time + 0.08, x: x, y: y, touching: false))
    }

    func testDoubleTapMutesAcrossTopEdge() {
        for x in [0.05, 0.5, 0.95] {
            let (engine, recorder) = makeEngine()
            tap(engine, at: 0, x: x, y: 0.95)
            tap(engine, at: 0.2, x: x, y: 0.95)
            XCTAssertEqual(recorder.commands, [.mute], "x = \(x)")
            XCTAssertTrue(recorder.begins.isEmpty)
        }
    }

    func testSingleTapOrTapsBelowTopBandDoNotMute() {
        let (engine, recorder) = makeEngine()
        tap(engine, at: 0, x: 0.5, y: 0.95)
        tap(engine, at: 0.15, x: 0.5, y: 0.839)
        tap(engine, at: 0.3, x: 0.5, y: 0.839)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testTopCornerDragAdjustsItsSideWithoutMuting() {
        for (x, target) in [(0.05, EdgeAction.brightness), (0.95, .volume)] {
            let (engine, recorder) = makeEngine()
            tap(engine, at: 0, x: x, y: 0.95)
            engine.process(frame(at: 0.15, x: x, y: 0.95))
            engine.process(frame(at: 0.17, x: x, y: 0.7))
            engine.process(frame(at: 0.32, x: x, y: 0.7, touching: false))
            tap(engine, at: 0.35, x: x, y: 0.95)

            XCTAssertEqual(recorder.begins, [target])
            XCTAssertEqual(recorder.updates.last?.0, target)
            XCTAssertLessThan(recorder.updates.last?.1 ?? 0.5, 0.5)
            XCTAssertTrue(recorder.commands.isEmpty)
        }
    }

    func testResetAndMultitouchClearPendingMuteTap() {
        let (engine, recorder) = makeEngine()
        tap(engine, at: 0, x: 0.5, y: 0.95)
        engine.reset()
        tap(engine, at: 0.15, x: 0.5, y: 0.95)
        engine.process(frame(at: 0.25, x: 0.5, y: 0.95))
        engine.process(TouchFrame(timestamp: 0.27, contacts: [
            TouchContact(id: 1, x: 0.5, y: 0.95, isTouching: true),
            TouchContact(id: 2, x: 0.6, y: 0.95, isTouching: true)
        ]))
        tap(engine, at: 0.35, x: 0.5, y: 0.95)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testBottomDoubleTapSendsPlayPauseOnlyWhenEnabled() {
        for (stripEnabled, tapEnabled) in [(true, true), (true, false), (false, true)] {
            let (engine, recorder) = makeEngine {
                $0.mediaStripEnabled = stripEnabled
                $0.tapToPlayEnabled = tapEnabled
            }
            tap(engine, at: 0, x: 0.5, y: 0.05)
            XCTAssertTrue(recorder.commands.isEmpty)
            tap(engine, at: 0.2, x: 0.5, y: 0.05)
            XCTAssertEqual(recorder.commands, stripEnabled && tapEnabled ? [.playPause] : [])
        }
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
        let recorder = Recorder()
        engine.delegate = recorder

        engine.process(frame(at: 0.0, x: 0.95, y: 0.2))
        engine.process(frame(at: 0.02, x: 0.95, y: 0.6))
        XCTAssertTrue(recorder.updates.isEmpty)
    }
}
