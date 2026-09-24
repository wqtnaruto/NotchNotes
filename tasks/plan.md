# 分页标题常显与双击重命名实施计划

> 执行约定：用户确认整套方案后，通过 `/b` 逐任务执行；本计划不构成自动实现、提交或发布授权。
> 状态：待用户确认。任务顺序 T1 → T2 → T3 → T4 → T5，单人串行；每项同时交付该路径的代码和测试。

**Goal:** 常显分页标题，支持双击原位命名并可靠保存，正文、焦点及原有分页行为不回归。

**Architecture:** SwiftUI 管导航布局，局部 AppKit 管点击和文本输入，窗口持有单一标题编辑会话。自定义标题随原分页归档；保存、退出和导航共用可失败的确认入口。

**Tech Stack:** Swift 6、SwiftPM、SwiftUI、AppKit、Foundation、Combine、现有 MarkdownEngine 与 XCTest，最低 macOS 14。

## 输入与事实边界

- 规格：[NotchNotes/SPEC.md](../SPEC.md)，从本地 [PRD](../docs/prd/PRD.md) 提取，不创建 Meegle 工作项。
- 技术契约：[NotchNotes/docs/design/tab-title-renaming/technical-design.md](../docs/design/tab-title-renaming/technical-design.md)。内部接口、保存顺序、布局参数与事件优先级只在该文档定义，本计划引用而不再维护副本。
- 选型理由：[NotchNotes/docs/intent/tab-title-renaming.md](../docs/intent/tab-title-renaming.md)（D1–D7）。
- 当前代码基线：`9321a25`；当前分支 `chore/init-ai-native-workflow`，已有初始化和 PRD 等未跟踪文件。执行前重新检查状态，不把既有产物当成本任务新文件批量提交。
- 2026-09-24 规划时运行 `swift test --package-path /Users/wuqitian/macbook-island/NotchNotes`：41 个 XCTest、0 失败；这是旧功能基线，新测试尚未创建，原生新交互尚未验收。
- 本轮未执行打包、GUI 启动、commit、push 或发布。所有下面的命令均是实现阶段的待执行步骤，除上面明确记录的基线测试。

## 文件与责任地图

以下源码相对 `NotchNotes/`，没有列出的模块不主动重构。

| 文件 | 动作 | 责任/首个任务 |
|---|---|---|
| `Sources/NotchNotes/TabPagerControl.swift` | 新建 | 抽出导航栏、原生标签按钮、滚动定位；T1 |
| `Sources/NotchNotes/NotebookView.swift` | 修改 | 接入独立分页栏、固定高度、会话注入及正文选区回调；T1 |
| `Sources/NotchNotes/NoteTitlePolicy.swift` | 新建 | 规范化、变更分类和标题错误；T2 |
| `Sources/NotchNotes/TitleEditingState.swift` | 新建 | 单一编辑会话和动作门控；T2 |
| `Sources/NotchNotes/InlineTitleEditor.swift` | 新建 | 原生标题文本视图和 SwiftUI 桥接；T2 |
| `Sources/NotchNotes/NoteStore.swift` | 修改 | 可选名称、有效标题、严格磁盘确认；T2 |
| `Sources/NotchNotes/EditorInteractionState.swift` | 修改 | 正文身份筛选、暂停聚焦、携带 UUID 的选区回调；T2 |
| `Sources/NotchNotes/NotchPanelController.swift` | 修改 | 会话持有、Esc、点击/收起门控及退出检查；T2 |
| `Sources/NotchNotes/Localization.swift` | 修改 | 三种错误及重命名文案；T2、T4 |
| `Sources/NotchNotes/AppDelegate.swift` | 修改 | 正常退出的可取消检查；T5 |
| `Tests/NotchNotesTests/TabPagerControlTests.swift` | 新建 | 原生按钮动作、导航和布局；T1 |
| `Tests/NotchNotesTests/NoteTitlePolicyTests.swift` | 新建 | 标题规范化和边界；T2 |
| `Tests/NotchNotesTests/TitleEditingStateTests.swift` | 新建 | 会话、失败、重入和目标删除；T2 |
| `Tests/NotchNotesTests/InlineTitleEditorTests.swift` | 新建 | 原生输入、粘贴、选区、marked text 和撤销；T2 |
| `Tests/NotchNotesTests/EditorInteractionStateTests.swift` | 新建 | 正文识别、焦点及异步选区隔离；T2 |
| `Tests/NotchNotesTests/NotchPanelInteractionTests.swift` | 新建 | Esc、动作门控、收起与系统失焦；T2 |
| `Tests/NotchNotesTests/AppTerminationTests.swift` | 新建 | 退出检查成功/失败返回值；T5 |
| `Tests/NotchNotesTests/NoteStoreTests.swift` | 增补 | 归档兼容、严格保存、删除恢复；T2 |
| `Tests/NotchNotesTests/LocalizationTests.swift` | 增补 | 错误及重命名提示双语；T2、T4 |
| `README.md` | 修改 | 实现验收后说明标题使用方式；T5 |

`Package.swift`、`Vendor/`、文件暂存、防休眠和 GitHub Actions 不改。AppKit 测试位于现有 SwiftPM test target，不新装 UI 测试框架。测试 fixture 跟所属测试文件存放，只有确实重复时才提取辅助对象。

## 执行规则与检查点

- 下列命令均在 `NotchNotes/` 仓库根执行。每个测试簇先运行确认因缺少目标行为而失败，再写最小实现；语法错误或环境问题不算有效红灯。
- 先跑任务过滤集，再跑 `swift test`；有原生 UI 改动同时执行 `swift build`。不能只靠测试名称出现或构建成功勾选验收。
- 每个任务能单独形成一个 commit；明确得到提交授权才提交，且逐文件暂存，不使用 `git add .` 收入此前初始化产物。实现授权与提交授权分开。
- 当前是工作分支，不在规划阶段改分支或拉取业务代码；执行时若改用保护分支，按项目规则先确认基线并建工作分支。
- 实现与设计发生实质偏离时更新技术设计和对应 D 决策；不扩展产品范围，不降低失败语义，也不改 PRD 来掩盖未实现项。

## 阶段一：可读导航与基本命名

### Task 1 / T1：文字标签导航与固定新建入口

目标路径：展开 → 看见标题 → 选择/新建 → 目标可见。覆盖 AC01 的浏览/单击、AC10；双击编辑由 T2 接入。

- [ ] 在 `TabPagerControlTests.swift` 建立隔离 store、settings 与 NSHostingView fixture；测试 `testSelectingTextTabPreservesIdentityAndBody`、`testPlusCreatesOneVisibleActiveTab`、`testOverflowKeepsSingleRowAndPlusVisible`。
- [ ] 运行过滤集，确认当前圆点/换行实现无法满足文字标签及固定高度断言。
- [ ] 从 NotebookView 移出 TabPagerControl 到同名新文件，保留 select/add/remove 调用；按技术设计 10.1 接入横向滚动和标签按钮。只删除已经无引用的 WrappingHStack 与圆点专用样式。
- [ ] 同步替换 NotebookView 的 tabControlHeight/toolbarHeight 与 tabRowCount；分页数量不再参与栏高计算。
- [ ] 测试标签使用 store 的完整有效标题作 tooltip/辅助名称；已有选区在切换前保存，activeTabID 使用原 UUID。
- [ ] 用 1、20 页和长正文自动标题验证：栏高一致，“＋”在面板内，选择末页/新建页后目标可见。原生视图测试断控件 frame 和 action 结果，不只断布局常量。
- [ ] 运行以下过滤集及完整回归，记录检查点结果。

```bash
swift test --filter TabPagerControlTests
swift test
swift build
```

检查点 C1：可以按文字辨认和切换页面，不新增数据字段，旧自动标题与正文行为保持。

### Task 2 / T2：双击 → 草稿 → Enter 保存 / Esc 取消

目标路径：双击目标 → 独立命名 → 确认 → 本地归档 → 重建恢复；失败时保留草稿。覆盖 AC01–AC04、AC06–AC09、AC13 的数据兼容、AC14 的保存失败；建立 AC11 的基本焦点保护。

- [ ] 在 `NoteTitlePolicyTests.swift` 写表驱动用例：空白→清空；原自动名未修改→unchanged；`" A\n\tB  C "`→`"A B  C"`；50/51 个汉字；组合表情；`# 标题` 保持符号。先运行得到缺实现的失败。
- [ ] 在 `NoteStoreTests.swift` 加 `testCustomTitlePersistsWithoutChangingBodyOrSelection`、`testUnchangedAutoTitleStaysAutomatic`、`testClearingTitleRestoresAutomaticTitle`、`testDuplicateTitlesKeepDistinctTabs`，再按设计 3/5.1 实现可选属性、规则和解析入口。
- [ ] 加 `testTitleWriteFailureDoesNotPublishOrPersistCandidate`、`testQueuedOldSaveCannotOverwriteCommittedTitle`、`testFailedRenamePreservesPendingBodySave`。使用注入 writer 的确定性失败和临时目录，不能通过修改真实笔记目录权限制造失败。
- [ ] 按设计 5.2 实现候选快照的严格提交，验证内存、文件、UserDefaults 三个结果；分别从文件及恢复副本重新构造 store，不只断当前内存值。
- [ ] 加旧数据四种来源兼容用例，旧 JSON 中必须真的没有 customTitle 键，不能用新的编码器生成“旧数据”；检查 ID、正文、选区、顺序及默认语言名称。
- [ ] 在 `TitleEditingStateTests.swift` 写 begin/更新/确认/取消路径，含重复 begin 不重置、进入时完整有效标题及第二会话不会串写；实现窗口持有的单一 TitleEditingState。
- [ ] 在 `InlineTitleEditorTests.swift` 写 `testNewSessionSelectsCompleteTitleOnce`、`testViewUpdateKeepsDraftAndSelection`；新增原生输入桥接并让标签双击进入它，接通 Enter/Esc 与三种本地化错误。
- [ ] 在 `EditorInteractionStateTests.swift` 写正文/标题共存 fixture，以及 `testTitleViewCannotBecomeBodyBinding`、`testSuspendedFocusIgnoresQueuedRetry`、`testSelectionNotificationKeepsOriginDocumentID`；修改正文筛选和选区回调，禁止跨页/跨编辑器写入。
- [ ] 在 `NotchPanelInteractionTests.swift` 写 `testFirstEscapeCancelsSecondEscapeCollapses`、`testTitleSessionPreventsTimerAndGlobalMouseUpCollapse`、`testDelayedActivationCannotStealTitleFocus`；接入窗口持有状态与所有自动收起/延迟焦点保护。
- [ ] 用当前和非当前页各完成一次改名；关闭并重建隔离 store 后仍见已保存标题。此时以 Enter/Esc 为阶段验收入口，完整点击离开由 T3 收口。
- [ ] 跑过滤集、完整回归与构建，记录 C2。

```bash
swift test --filter 'NoteTitlePolicyTests|NoteStoreTests|TitleEditingStateTests|InlineTitleEditorTests|EditorInteractionStateTests|NotchPanelInteractionTests|LocalizationTests'
swift test
swift build
```

检查点 C2：基本改名数据闭环成立；严格保存失败能重试/取消，原标题和正文保留。仅有模型或输入框不能算完成 T2。

## 阶段二：离开编辑与原生输入可靠性

### Task 3 / T3：点击、菜单与系统失焦统一确认

目标路径：编辑 → 请求离开 → 先确认 → 成功执行原动作，失败留在原会话。覆盖 AC05、AC11 的全部收起入口、AC14 的动作阻断。

- [ ] 在会话和窗口测试中增加 `testValidDraftCommitsBeforeSwitchOrAdd`、`testInvalidDraftBlocksClickAndCommandN`、`testSaveFailureDoesNotReplayDeferredAction`；同时断 activeTabID、分页数量、文件内容和动作调用计数。
- [ ] 按设计 5.4 接入事件预处理：标题外点击先提交，成功放行原事件；失败同时消费该次对应的 drag/up。标题内部的选区操作不能触发保存。
- [ ] 为标签、固定“＋”、菜单新建及双击另一页接同一 commitIfNeeded；无会话重复检查没有副作用，删除例外留给 T5 的专用入口。
- [ ] 添加 `testExplicitHideCommitsOrStaysOpen`；将显式隐藏和自动收起分开，Cmd+W 失败不隐藏，自动收起在会话内始终拒绝。
- [ ] 添加 `testAppDeactivationPreservesFailedDraftWithoutReactivation`、`testMenuTrackingDoesNotCommitCurrentDraft`；观察应用 didResignActive，区分菜单跟踪/候选窗口与真正应用失活，不无条件请求焦点。
- [ ] 验证失败→修正→再次点击只执行一次新建/切换；重复通知和 delegate 重入不能导致重复提交或动作重放。
- [ ] 执行过滤集及回归；人工覆盖点击正文、点击另一页、菜单 Cmd+N、Cmd+W、切到其他应用后返回。

```bash
swift test --filter 'TitleEditingStateTests|NotchPanelInteractionTests|TabPagerControlTests'
swift test
swift build
```

检查点 C3：所有离开入口使用同一保存结果，保存失败不串页、不丢草稿、不抢系统焦点。

### Task 4 / T4：中文输入、键盘与辅助技术闭环

目标路径：键盘或辅助技术开始改名 → 中文/粘贴/撤销 → 确认或取消。覆盖 AC02、AC09、AC11、AC13 的提示本地化、AC15。

- [ ] 增补 `testMarkedTextEnterAndEscapeStayInEditingSession`：用原生 setMarkedText 建立组字，断第一次命令仅由输入系统处理；再无 marked text 时才保存/取消。窗口级 Esc 也要覆盖，不能只测试文本视图。
- [ ] 增补 `testPlainTextPasteNormalizesLineSeparators`、`testUndoAndSelectAllOnlyAffectTitle`、`testMarkdownCommandIsIgnoredDuringTitleEditing`；输入视图使用独立 UndoManager，组字中不得回写规范化草稿。
- [ ] 给标签原生按钮接键盘遍历、Space 选择、Return 改名及 accessibility 自定义动作，验证与双击进入同一目标会话；新增 `testKeyboardAndAccessibilityRenameShareTarget`。
- [ ] 完善焦点边框、当前页名称、错误说明和中英文 renameNote/renameNoteHelp；增补 LocalizationTests 的逐字断言，错误沿用 PRD 文案。
- [ ] 确认单击标题进入后不重置选区，SwiftUI 刷新/语言切换不全选当前草稿，失活期间 view 更新不激活应用。
- [ ] 执行过滤集及回归；人工验证中文输入法候选 Enter/Esc、组合表情、外部富文本粘贴、Cmd+A/C/X/V/Z、VoiceOver 重命名和错误提示。

```bash
swift test --filter 'InlineTitleEditorTests|EditorInteractionStateTests|NotchPanelInteractionTests|TabPagerControlTests|LocalizationTests'
swift test
swift build
```

检查点 C4：原生输入与可访问入口能完成完整改名，标题编辑不影响正文。自动化 marked text 测试不能替代真实输入法/VoiceOver 结果。

## 阶段三：生命周期与最终验收

### Task 5 / T5：删除恢复和正常退出不丢命名

目标路径 A：改名 → 删除 → 恢复；目标路径 B：有草稿 → 请求退出 → 保存成功退出或失败留下修正。覆盖 AC03 的退出、AC12、AC14 的目标消失；收口全量验收。

- [ ] 增补 `testDeletingEditingTargetDiscardsDraftAndRestoresSavedTitle`、`testDeletingOtherTabRequiresCommit`、`testLastTabCannotBeDeletedDuringRename`；删除动作先验证可删除条件，再按设计例外处理草稿。
- [ ] 增补 `testMissingTargetEndsSessionWithoutCreatingNote`；验证非主动删除导致的缺失使用独立提示，不把草稿保存到当前页。
- [ ] 在 `AppTerminationTests.swift` 增加 `testValidDraftAllowsTermination`、`testInvalidOrFailedDraftCancelsTermination`、`testCancelThenRetryAllowsTermination`。以注入闭包/隔离会话检查返回值，绝不终止 XCTest 进程。
- [ ] 接入 AppDelegate.applicationShouldTerminate 和控制器 prepareForTermination；拒绝退出不能提前停止防休眠或执行 willTerminate 清理。
- [ ] 测试依旧通过原 restoreLastDeletedTab 恢复，不新增恢复页面；文件暂存、防休眠及正文功能只回归、不改实现。
- [ ] 使用 20 页各约 100 KB 的隔离正文样本记录改名确认耗时；出现明显 UI 停顿时回到 D4 讨论，不将假保存作为优化。
- [ ] 执行完整 XCTest、构建和下方人工清单；实际完成后才在 README 的“使用”中说明双击、Enter/Esc、清空与横向滚动。
- [ ] 同步技术设计与实际接口、intent 的新取舍；逐条核对 AC01–AC15，留存未通过项，不宣称纯单测等同产品验收。

```bash
swift test --filter 'NoteStoreTests|TitleEditingStateTests|AppTerminationTests|NotchPanelInteractionTests'
swift test
swift build
```

检查点 C5：删除恢复、失败重试与正常退出闭环成立，全部测试和人工验收有对应证据。未通过不能直接进入发布。

## 原生人工验收清单

以下使用专用测试 macOS 用户的应用数据；不要拿真实日常笔记当故障注入对象。测试环境准备好后运行 `swift run NotchNotes`；本轮规划不启动应用。

- [ ] 建三页，分别留正文选区；单击/双击当前和非当前页，确认输入不会进入正文。
- [ ] 命名、清空、无变更确认、两页重名、50/51 字符、中文与组合表情；错误保留草稿。
- [ ] 20 页和长标题横向滚动，末页/新建页/编辑页均可见，“＋”固定，正文高度不随页数减少。
- [ ] 鼠标移出、立即双击后等待延迟聚焦、两次 Esc；编辑与失败状态均不误收起。
- [ ] 点击其他标签、正文、“＋”，以及 Cmd+N/Cmd+W；失败先修正再操作，不重复执行旧动作。
- [ ] 真正切换应用与菜单跟踪分别验证，不抢焦点；右键菜单删除当前编辑页使用最后保存名称恢复。
- [ ] 中文组字的 Enter/Esc、富文本粘贴、纯标题撤销；正文格式快捷操作不误写正文。
- [ ] 键盘遍历、Return 改名、Space 选中、VoiceOver 动作和错误朗读；中英文分别验证。
- [ ] 合法草稿退出重开保留；超长或注入保存失败取消退出；Esc 放弃后再次退出可成功。
- [ ] 文件拖入/拖出、防休眠、正文编辑、分页删除及至少一页保持原行为。

## 完成定义与交接

五个任务全部有实现和同层测试，AC 覆盖见技术设计第十一章；所有人工未测项必须明确列出。计划生成者只做一致性自检，不批准计划。用户确认后才进入 `/b`，每次执行下一项，不自动创建工作项或推进远端状态。
