import AppKit
import XCTest
@testable import NotchNotes

/// T3：离开编辑与导航/收起/失焦的统一确认门控（进程内，围绕 TitlePanelInteraction）。
/// 覆盖 AC05、AC14 的动作阻断与 AC11 的显式隐藏/失活，控制器真实事件接线另由人工验收。
@MainActor
final class NotchPanelNavigationTests: XCTestCase {

    private func makeInteraction(_ f: TitleFixture, body: EditorInteractionState) -> TitlePanelInteraction {
        TitlePanelInteraction(state: f.state, editor: body, cancelCollapse: {})
    }

    /// 合法草稿：先提交成功，再放行原动作（切页/新建），标题落盘且会话结束。
    func testValidDraftCommitsBeforeSwitchOrAdd() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("新名字", selection: .init(location: 3, length: 0), isComposing: false)
        let before = f.writer.writeCount
        var actions = 0
        XCTAssertTrue(interaction.performNavigationAction { actions += 1 })
        XCTAssertEqual(actions, 1)
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.writer.writeCount, before + 1)
        XCTAssertEqual(f.store.tabs.first?.customTitle, "新名字")
    }

    /// 非法草稿（超长）：阻断切页/Cmd+N，保留会话与草稿，不写盘。
    func testInvalidDraftBlocksClickAndCommandN() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        let before = f.writer.writeCount
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft(String(repeating: "长", count: 51), selection: .init(location: 0, length: 0), isComposing: false)
        var actions = 0
        XCTAssertFalse(interaction.performNavigationAction { actions += 1 })
        XCTAssertEqual(actions, 0)
        XCTAssertNotNil(f.state.session)
        XCTAssertEqual(f.writer.writeCount, before)
        XCTAssertEqual(f.state.session?.draft.count, 51)
    }

    /// 保存失败：不重复执行延迟动作，不重复新建，会话与旧标题保留。
    func testSaveFailureDoesNotReplayDeferredAction() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("会失败的改名", selection: .init(location: 5, length: 0), isComposing: false)
        let tabs = f.store.tabs.count
        f.writer.shouldFail = true
        var actions = 0
        // 模拟重复通知 / delegate 重入：失败期间多次请求离开都不得放行动作，也不得发布新标题。
        XCTAssertFalse(interaction.performNavigationAction { actions += 1 })
        XCTAssertFalse(interaction.performNavigationAction { actions += 1 })
        XCTAssertFalse(interaction.performNavigationAction { actions += 1 })
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(f.store.tabs.count, tabs)
        XCTAssertNil(f.store.tabs.first?.customTitle)
        XCTAssertNotNil(f.state.session)
        // 即便写入恢复，未经用户再次合法提交也不得隐式发布旧会话的失败草稿。
        XCTAssertFalse(f.state.commitIfNeeded())
        XCTAssertNil(f.store.tabs.first?.customTitle)
    }

    /// 显式隐藏（Cmd+W）：提交成功才隐藏；失败保持打开；自动收起在会话内始终拒绝。
    func testExplicitHideCommitsOrStaysOpen() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("可保存", selection: .init(location: 3, length: 0), isComposing: false)
        var hid = 0
        XCTAssertTrue(interaction.performExplicitHide { hid += 1 })
        XCTAssertEqual(hid, 1)
        XCTAssertNil(f.state.session)
        XCTAssertEqual(f.store.tabs.first?.customTitle, "可保存")

        // 失败草稿：显式隐藏被拒，面板保持打开，会话不结束。
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("超长".repeated(60), selection: .init(location: 0, length: 0), isComposing: false)
        f.writer.shouldFail = true
        XCTAssertFalse(interaction.performExplicitHide { hid += 1 })
        XCTAssertEqual(hid, 1)
        XCTAssertNotNil(f.state.session)
        f.writer.shouldFail = false
        f.state.cancel()
        // 无会话时自动收起照常放行。
        interaction.performAutomaticCollapse { hid += 1 }
        XCTAssertEqual(hid, 2)
    }

    /// 应用失活：失败草稿保留且不强抢焦点（不触发重新激活）。
    func testAppDeactivationPreservesFailedDraftWithoutReactivation() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("失败即保留", selection: .init(location: 5, length: 0), isComposing: false)
        f.writer.shouldFail = true
        var reactivations = 0
        XCTAssertFalse(interaction.performAppDeactivationSave { reactivations += 1 })
        XCTAssertEqual(reactivations, 0)
        XCTAssertNotNil(f.state.session)
        XCTAssertNil(f.store.tabs.first?.customTitle)
        f.writer.shouldFail = false
    }

    /// 菜单跟踪期间不提交当前草稿；菜单动作按语义执行而不触发保存。
    func testMenuTrackingDoesNotCommitCurrentDraft() throws {
        let f = try TitleFixture(); defer { f.cleanUp() }
        let interaction = makeInteraction(f, body: EditorInteractionState())
        let before = f.writer.writeCount
        f.state.begin(tabID: f.store.activeTabID, language: .chinese)
        f.state.updateDraft("菜单里不该存", selection: .init(location: 6, length: 0), isComposing: false)
        interaction.beginMenuTracking()
        var menuActions = 0
        interaction.performMenuAction { menuActions += 1 }
        XCTAssertEqual(menuActions, 1)
        XCTAssertEqual(f.writer.writeCount, before)
        XCTAssertNotNil(f.state.session)
        // 跟踪期间的离开请求既不提交也不放行。
        var navigations = 0
        XCTAssertFalse(interaction.performNavigationAction { navigations += 1 })
        XCTAssertEqual(navigations, 0)
        interaction.endMenuTracking()
        // 结束跟踪后，合法草稿可正常提交并放行。
        f.state.updateDraft("退出后保存", selection: .init(location: 5, length: 0), isComposing: false)
        XCTAssertTrue(interaction.performNavigationAction { navigations += 1 })
        XCTAssertEqual(navigations, 1)
    }
}

private extension String {
    func repeated(_ times: Int) -> String { String(repeating: self, count: times) }
}
