import AppKit
import XCTest
@testable import NotchNotes

@MainActor
final class NotchActivationPolicyTests: XCTestCase {
    private let frame = NSRect(x: 600, y: 950, width: 210, height: 32)

    func testClickModeOnlyOpensOnLeftMouseDownInsideNotch() {
        let inside = NSPoint(x: 700, y: 960)
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .leftMouseUp] {
            XCTAssertEqual(NotchActivationPolicy.shouldExpand(for: type, at: inside, in: frame, mode: .click),
                           type == .leftMouseDown)
        }
        for mode in TriggerMode.allCases {
            for point in [NSPoint(x: 599, y: 960), NSPoint(x: 811, y: 960), NSPoint(x: 700, y: 949)] {
                XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .leftMouseDown, at: point, in: frame, mode: mode))
                XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .mouseMoved, at: point, in: frame, mode: mode))
            }
        }
    }

    func testHoverRemainsOptionalAndDoesNotOpenDuringMousePress() {
        let point = NSPoint(x: 700, y: 960)
        XCTAssertTrue(NotchActivationPolicy.shouldExpand(for: .mouseMoved, at: point, in: frame, mode: .hover))
        XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .mouseMoved, at: point, in: frame,
                                                          mode: .hover, isLeftMousePressed: true))
        XCTAssertTrue(NotchActivationPolicy.shouldExpand(for: .leftMouseDown, at: point, in: frame, mode: .hover))
    }

    func testClickUsesEventLocationRatherThanLaterPointerPosition() throws {
        let inside = try mouseEvent(at: NSPoint(x: 700, y: 960))
        let outside = try mouseEvent(at: NSPoint(x: 700, y: 949))
        let capturedInside = NotchActivationPolicy.screenLocation(for: inside)
        let capturedOutside = NotchActivationPolicy.screenLocation(for: outside)
        // 后续鼠标位于另一侧时，先前点击仍按事件快照判定，无需移动真实鼠标。
        XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .mouseMoved, at: capturedOutside, in: frame, mode: .click))
        XCTAssertTrue(NotchActivationPolicy.shouldExpand(for: .leftMouseDown, at: capturedInside, in: frame, mode: .click))
        XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .mouseMoved, at: capturedInside, in: frame, mode: .click))
        XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .leftMouseDown, at: capturedOutside, in: frame, mode: .click))
    }

    func testLocalEventConvertsWindowLocationToScreen() throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let event = try mouseEvent(at: NSPoint(x: 100, y: 10), windowNumber: window.windowNumber)
        XCTAssertEqual(NotchActivationPolicy.screenLocation(for: event), NSPoint(x: 700, y: 960))
    }

    func testFileDragKeepsExtendedAreaWithoutAcceptingStalePasteboard() {
        let dropFrame = NSRect(x: 600, y: 920, width: 210, height: 62)
        let point = NSPoint(x: 700, y: 930)
        XCTAssertFalse(NotchActivationPolicy.shouldExpand(for: .leftMouseDown, at: point, in: frame, mode: .click))
        func shouldReveal(_ location: NSPoint = NSPoint(x: 700, y: 930), pressed: Bool = true,
                          hasFiles: Bool = true, changeCount: Int = 11) -> Bool {
            NotchActivationPolicy.shouldRevealForFileDrag(
                at: location, in: dropFrame, isLeftMousePressed: pressed,
                containsFileURLs: hasFiles, pasteboardChangeCount: changeCount, completedDragChangeCount: 10
            )
        }
        XCTAssertTrue(shouldReveal())
        XCTAssertFalse(shouldReveal(changeCount: 10))
        XCTAssertFalse(shouldReveal(pressed: false))
        XCTAssertFalse(shouldReveal(hasFiles: false))
        XCTAssertFalse(shouldReveal(NSPoint(x: 599, y: 930)))
    }

    private func mouseEvent(at point: NSPoint, windowNumber: Int = 0) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                        timestamp: 0, windowNumber: windowNumber, context: nil,
                                        eventNumber: 1, clickCount: 1, pressure: 1))
    }
}
