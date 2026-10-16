import AppKit
import XCTest
@testable import NotchNotes

@MainActor
final class NotchGeometryTests: XCTestCase {
    func testActivationFrameMatchesNotchInsteadOfExtendedDropTarget() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let layout = NotchLayout(
            notchSize: NSSize(width: 210, height: 32),
            compactSize: NSSize(width: 204, height: 34),
            expandedSize: NSSize(width: 480, height: 408),
            compactTopOffset: 0,
            expandedTopOffset: 0
        )

        let activationFrame = NotchGeometry.activationFrame(for: layout, in: screenFrame)
        let dropFrame = NotchGeometry.fileDropFrame(for: layout, in: screenFrame)

        XCTAssertEqual(activationFrame.width, 210)
        XCTAssertEqual(activationFrame.height, 32)
        XCTAssertEqual(activationFrame.midX, screenFrame.midX)
        XCTAssertEqual(activationFrame.maxY, screenFrame.maxY)
        XCTAssertEqual(dropFrame.maxY, activationFrame.maxY)
        XCTAssertEqual(
            dropFrame.height - layout.compactSize.height,
            NotchGeometry.fileDropTargetExtension
        )
        XCTAssertEqual(dropFrame.height, 62)
        let belowNotch = NSPoint(x: screenFrame.midX, y: activationFrame.minY - 1)
        XCTAssertFalse(activationFrame.contains(belowNotch))
        XCTAssertTrue(dropFrame.contains(belowNotch))
    }

    func testActivationFrameUsesScreenOriginAndExactNotchSize() {
        let screen = NSRect(x: -1800, y: 600, width: 1512, height: 982)
        let layout = NotchLayout(
            notchSize: NSSize(width: 220, height: 30),
            compactSize: NSSize(width: 214, height: 32),
            expandedSize: NSSize(width: 480, height: 408),
            compactTopOffset: 0, expandedTopOffset: 0
        )
        let frame = NotchGeometry.activationFrame(for: layout, in: screen)
        XCTAssertEqual(frame, NSRect(x: screen.midX - 110, y: screen.maxY - 30, width: 220, height: 30))
        for point in [NSPoint(x: frame.minX - 1, y: frame.midY),
                      NSPoint(x: frame.maxX + 1, y: frame.midY),
                      NSPoint(x: frame.midX, y: frame.minY - 1)] {
            XCTAssertFalse(frame.contains(point))
        }
        XCTAssertTrue(frame.contains(NSPoint(x: frame.minX + 0.5, y: frame.minY + 0.5)))
        XCTAssertTrue(frame.contains(NSPoint(x: frame.maxX - 0.5, y: frame.maxY - 0.5)))
    }

    func testMissingScreenKeepsSimulatedNotchEntry() {
        let layout = NotchGeometry.layout(for: nil)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(NotchGeometry.activationFrame(for: layout, in: screen),
                       NSRect(x: 615, y: 868, width: 210, height: 32))
    }
}
