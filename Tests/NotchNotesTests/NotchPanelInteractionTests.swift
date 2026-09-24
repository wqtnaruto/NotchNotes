import AppKit
import XCTest
@testable import NotchNotes

@MainActor
final class NotchPanelInteractionTests: XCTestCase {
    func testFirstEscapeCancelsSecondEscapeCollapses() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let body = EditorInteractionState()
        let interaction = TitlePanelInteraction(state: f.state, editor: body, cancelCollapse: {})
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.titleInteraction = interaction
        var collapseCount = 0
        panel.onEscape = { collapseCount += 1 }
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("放弃", selection: .init(location: 2, length: 0), isComposing: false)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        panel.sendEvent(escape)
        XCTAssertNil(f.state.session)
        XCTAssertEqual(collapseCount, 0)
        XCTAssertFalse(body.isFocusSuspended)
        panel.sendEvent(escape)
        XCTAssertEqual(collapseCount, 1)
        XCTAssertNil(f.store.tabs[0].customTitle)
    }

    func testTitleSessionPreventsTimerAndGlobalMouseUpCollapse() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        var cancellations = 0
        var collapses = 0
        let body = EditorInteractionState()
        let interaction = TitlePanelInteraction(state: f.state, editor: body) { cancellations += 1 }
        // 与控制器相同：安排时允许，执行时必须再次检查会话。
        let pendingTimer = DispatchWorkItem {
            interaction.performAutomaticCollapse { collapses += 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: pendingTimer)
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(body.isFocusSuspended)
        interaction.performAutomaticCollapse { collapses += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(collapses, 0)
        f.state.updateDraft(String(repeating: "长", count: 51), selection: .init(location: 0, length: 0), isComposing: false)
        XCTAssertFalse(f.state.commitIfNeeded())
        interaction.performAutomaticCollapse { collapses += 1 }
        XCTAssertEqual(collapses, 0)
        f.state.cancel()
        interaction.performAutomaticCollapse { collapses += 1 }
        XCTAssertEqual(collapses, 1)
    }

    func testExpiredActivationRemainsBlockedAfterEditingEnds() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let body = EditorInteractionState()
        let interaction = TitlePanelInteraction(state: f.state, editor: body, cancelCollapse: {})
        let oldGeneration = interaction.activationGeneration
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.cancel()
        var activations = 0
        interaction.performEditorActivation(generation: oldGeneration) { activations += 1 }
        XCTAssertEqual(activations, 0)
        interaction.performEditorActivation(generation: interaction.activationGeneration) { activations += 1 }
        XCTAssertEqual(activations, 1)
        XCTAssertFalse(body.isFocusSuspended)
    }

    func testDelayedActivationCannotStealTitleFocus() throws {
        let f = try TitleFixture()
        defer { f.cleanUp() }
        let body = EditorInteractionState()
        let interaction = TitlePanelInteraction(state: f.state, editor: body, cancelCollapse: {})
        var activations = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            interaction.performEditorActivation { activations += 1 }
        }
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        interaction.performEditorActivation { activations += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(activations, 0)
        f.state.cancel()
        XCTAssertEqual(activations, 0)
        interaction.performEditorActivation { activations += 1 }
        XCTAssertEqual(activations, 1)
    }
}
