import CoreGraphics
import XCTest
@testable import SlideSenseCore

final class EdgeGeometryTests: XCTestCase {
    func testDetectsEachEdge() {
        let geometry = EdgeGeometry(edgeWidth: 0.2)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.05, y: 0.5)), .left)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.95, y: 0.5)), .right)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.5, y: 0.05)), .bottom)
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.5, y: 0.5)))
    }

    func testCornerPicksNearestEdge() {
        let geometry = EdgeGeometry(edgeWidth: 0.2)
        // Bottom-left corner: closer to the bottom (y = 0.02) than the left (x = 0.15).
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.15, y: 0.02)), .bottom)
        // Bottom-right corner: closer to the right.
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.99, y: 0.02)), .right)
    }

    func testBottomQuarterOnlyLimitsSideEdges() {
        let geometry = EdgeGeometry(edgeWidth: 0.2, bottomQuarterOnly: true)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.05, y: 0.1)), .left)
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.05, y: 0.7)))
    }

    func testBottomQuarterSideBandBeatsMediaStrip() {
        let geometry = EdgeGeometry(edgeWidth: 0.2, bottomQuarterOnly: true)
        // Closer to the bottom than the left, but inside the start zone.
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.15, y: 0.02)), .left)
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.9, y: 0.05)), .right)
        // The middle of the bottom band is still the media strip.
        XCTAssertEqual(geometry.edge(at: CGPoint(x: 0.5, y: 0.05)), .bottom)
    }

    func testBottomQuarterKeepsFullTravelSpan() {
        let on = EdgeGeometry(bottomQuarterOnly: true)
        let off = EdgeGeometry(bottomQuarterOnly: false)
        XCTAssertEqual(on.travelSpan(for: .left), 0.75, accuracy: 1e-9)
        XCTAssertEqual(off.travelSpan(for: .right), 0.75, accuracy: 1e-9)
    }

    func testQuickMuteCorner() {
        let geometry = EdgeGeometry()
        XCTAssertTrue(geometry.isQuickMuteCorner(CGPoint(x: 0.95, y: 0.95)))
        XCTAssertFalse(geometry.isQuickMuteCorner(CGPoint(x: 0.95, y: 0.5)))
        XCTAssertFalse(geometry.isQuickMuteCorner(CGPoint(x: 0.5, y: 0.95)))
    }

    func testOutOfRangePointsAreIgnored() {
        let geometry = EdgeGeometry()
        XCTAssertNil(geometry.edge(at: CGPoint(x: -0.2, y: 0.5)))
        XCTAssertNil(geometry.edge(at: CGPoint(x: 0.5, y: 1.4)))
    }
}
