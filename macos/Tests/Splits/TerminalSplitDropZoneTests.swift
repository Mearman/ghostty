import Testing
import Foundation
@testable import Ghostty

struct TerminalSplitDropZoneTests {
    private let standardSize = CGSize(width: 100, height: 100)

    // MARK: - Basic Edge Detection

    @Test func topEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 5), in: standardSize)
        #expect(zone == .top)
    }

    @Test func bottomEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 95), in: standardSize)
        #expect(zone == .bottom)
    }

    @Test func leftEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 5, y: 50), in: standardSize)
        #expect(zone == .left)
    }

    @Test func rightEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 95, y: 50), in: standardSize)
        #expect(zone == .right)
    }

    // MARK: - Corner Tie-Breaking
    // When distances are equal, the check order determines the result:
    // left -> right -> top -> bottom

    @Test func topLeftCornerSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 0, y: 0), in: standardSize)
        #expect(zone == .left)
    }

    @Test func topRightCornerSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 0), in: standardSize)
        #expect(zone == .right)
    }

    @Test func bottomLeftCornerSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 0, y: 100), in: standardSize)
        #expect(zone == .left)
    }

    @Test func bottomRightCornerSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 100), in: standardSize)
        #expect(zone == .right)
    }

    // MARK: - Center Zone

    @Test func centerPointIsTheCenterZone() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 50), in: standardSize)
        #expect(zone == .center)
    }

    @Test func justInsideTheInsetOnEveryEdgeIsStillCenter() {
        let inset = TerminalSplitDropZone.centerInset * 100
        let points = [
            CGPoint(x: inset, y: 50),
            CGPoint(x: 100 - inset, y: 50),
            CGPoint(x: 50, y: inset),
            CGPoint(x: 50, y: 100 - inset),
        ]
        for point in points {
            #expect(TerminalSplitDropZone.calculate(at: point, in: standardSize) == .center)
        }
    }

    @Test func justOutsideTheInsetSplits() {
        let outside = TerminalSplitDropZone.centerInset * 100 - 1
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: outside, y: 50), in: standardSize) == .left)
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: 100 - outside, y: 50), in: standardSize) == .right)
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: outside), in: standardSize) == .top)
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 100 - outside), in: standardSize) == .bottom)
    }

    @Test func centerZoneScalesWithANonSquarePane() {
        let size = CGSize(width: 400, height: 100)
        // A quarter of the width in is the edge of the center zone, even though that is 100pt
        // while a quarter of the height is only 25pt.
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: 200, y: 50), in: size) == .center)
        #expect(TerminalSplitDropZone.calculate(at: CGPoint(x: 90, y: 50), in: size) == .left)
    }

    // MARK: - Non-Square Aspect Ratio

    @Test func rectangularViewTopEdge() {
        let size = CGSize(width: 200, height: 100)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 10), in: size)
        #expect(zone == .top)
    }

    @Test func rectangularViewLeftEdge() {
        let size = CGSize(width: 200, height: 100)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 10, y: 50), in: size)
        #expect(zone == .left)
    }

    @Test func tallRectangleTopEdge() {
        let size = CGSize(width: 100, height: 200)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 10), in: size)
        #expect(zone == .top)
    }

    // MARK: - Out-of-Bounds Points

    @Test func pointLeftOfViewSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: -10, y: 50), in: standardSize)
        #expect(zone == .left)
    }

    @Test func pointAboveViewSelectsTop() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: -10), in: standardSize)
        #expect(zone == .top)
    }

    @Test func pointRightOfViewSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 110, y: 50), in: standardSize)
        #expect(zone == .right)
    }

    @Test func pointBelowViewSelectsBottom() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 110), in: standardSize)
        #expect(zone == .bottom)
    }

    // MARK: - Diagonal Regions (Triangular Zones)

    @Test func upperLeftTriangleSelectsLeft() {
        // Point in the upper-left triangle, closer to left than top
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 20, y: 30), in: standardSize)
        #expect(zone == .left)
    }

    @Test func upperRightTriangleSelectsRight() {
        // Point in the upper-right triangle, closer to right than top
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 80, y: 30), in: standardSize)
        #expect(zone == .right)
    }

    @Test func lowerLeftTriangleSelectsLeft() {
        // Point in the lower-left triangle, closer to left than bottom
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 20, y: 70), in: standardSize)
        #expect(zone == .left)
    }

    @Test func lowerRightTriangleSelectsRight() {
        // Point in the lower-right triangle, closer to right than bottom
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 80, y: 70), in: standardSize)
        #expect(zone == .right)
    }
}
