# 分页标题重命名：选型理由

> 范围：NotchNotes 单仓库；状态：用户已确认方案，T1 导航、T2 基本改名与 T3 离开编辑统一确认已实现并通过自动化验证；T4–T5 待执行。
> 产品依据：`NotchNotes/docs/prd/PRD.md` 与 `NotchNotes/SPEC.md`。本文件只保存取舍，具体契约集中在技术设计中。

## D1：自定义标题随分页保存

- 候选：`NoteTab` 增加可选名称 / 以 UUID 为键另存标题表 / 改写正文首行。
- 选择：新增 `customTitle: String?`；有效标题由既有标题入口统一解析。
- 理由：删除、恢复和归档天然携带同一分页属性；可选字段能读取缺少该键的旧 JSON。空值回退自动标题，身份仍是 UUID。
- 否决独立标题表：增加归档和删除恢复时的双份一致性工作。
- 否决改正文：违反独立命名及正文保持要求。
- 边界：不改归档键名、不迁移数据库；不承诺旧应用重写后保留新字段。

## D2：SwiftUI 导航搭配局部 AppKit 输入

- 候选：全部使用 SwiftUI `TextField` / SwiftUI 滚动条搭配 AppKit 标签按钮和单行文本视图 / 全部重写为 AppKit 标签栏。
- 选择：保留 SwiftUI `ScrollViewReader`、横向 `ScrollView` 和普通 `HStack`；以局部 `NSViewRepresentable` 承载原生标签按钮及 `TitleTextView` 输入。
- 理由：原生按钮可用 `clickCount` 明确区分单击和双击；独立文本视图可查询 marked text、保留输入选区并控制粘贴与命令分发。其余布局沿用现有 SwiftUI。
- 否决纯 SwiftUI：本次涉及窗口先截获 Esc、输入法和点击前保存，单靠焦点绑定及 `onSubmit` 不足以定义事件顺序。
- 否决整栏 AppKit 重写：扩大维护范围，丢失已有 SwiftUI 布局优势。
- 选择普通而非惰性 HStack：避免编辑标签在离屏复用时销毁输入视图；本需求不新增分页数量上限。
- 局部拆分：将 `TabPagerControl` 移到独立文件；只删除不再使用的圆点布局/样式，不重构正文或文件暂存视图。

## D3：窗口持有单一标题编辑会话，并严格识别正文

- 候选：每个标签独立 `@State` / 在 `NoteStore` 保存输入草稿 / 控制器持有一个 `TitleEditingState`。
- 选择：`NotchPanelController` 持有单一主线程会话并传给分页栏；会话保存目标 UUID、初始有效标题、草稿、输入选区与错误。
- 理由：面板重建、系统失焦和退出都需要访问同一草稿；窗口级所有权避免多个输入框和跨页串写，草稿不进入持久快照。
- 否决标签局部状态：标签生命周期不等于编辑会话生命周期。
- 否决存储层持有草稿：模糊已保存数据与临时输入的边界。
- 关联改动：正文查找限定为 `delegate is NativeTextViewCoordinator` 的文本视图，不再取任意第一个 `NSTextView`；此协调器是现有 MarkdownEngine 的 public 类型，无须修改 Vendor。
- 焦点选择：进入标题编辑时暂停并失效化正文聚焦重试；退出时按退出原因决定焦点目标。正文选区通知携带原文档 UUID 和捕获时的范围，避免异步通知写入新活动页。

## D4：标题确认采用可失败的磁盘优先提交

- 候选：沿用先更新内存/UserDefaults 再异步落盘 / 异步确认并排队重放所有点击 / 标题确认时在既有串行队列同步原子落盘。
- 选择：仅标题确认走同步的候选快照提交；先完成已有队列写入，再原子写 `notes.json`，成功后同步 UserDefaults 并发布新标题。
- 理由：当前 `persistNow()` 隐藏磁盘错误，无法支撑 PRD 的“保存失败不覆盖旧标题”。同步确认使点击放行、失败拦截和正常退出获得确定结果，不引入保存中的额外产品状态。
- 否决直接沿用：UserDefaults 先写入新名后再报磁盘失败，取消与重启可能仍读到用户以为未保存的标题。
- 否决本轮全面异步化：需要版本冲突处理、动作队列、鼠标事件重放与退出等待协议，超出本次低频操作的必要复杂度。
- 代价：确认会阻塞主线程直到一次本地快照写入结束；不声称零卡顿。实现验证必须包含大正文样本；若出现明显停顿，应重新讨论此决策，不能通过降级为虚假成功绕过。
- 边界：普通正文自动保存仍沿用现有策略；归档路径缺失或文件写入失败时，改名返回失败，UserDefaults 不作为改名成功的替代凭据。失败后仍安排原有正文/选区的保存，不把候选新名混入其中。
- 测试接缝：复用可注入的 `@Sendable (Data, URL) throws -> Void` 文件写入闭包，默认创建目录并原子写文件；不引入通用存储框架。

## D5：先保存再执行动作，收起统一受会话约束

- 候选：输入框失焦后补存 / 对每个按钮分别加判断 / 会话提供统一 `commitIfNeeded()`，调用方在执行动作前检查。
- 选择：第三项，同时保留窗口事件分发前的鼠标命中判断；保存成功才让原鼠标事件继续传递，不伪造或异步重放鼠标事件。
- 理由：`onBlur` 时新建/切换可能已经执行；统一入口能同时约束标签、“＋”、菜单 Cmd+N、显式隐藏与正常退出。
- 否决仅失焦补存：无法阻止失败后的导航，还可能把标题保存到新的活动页。
- 否决散落的规则副本：Esc、全局 mouseUp、定时收起和菜单隐藏容易漏掉不同入口。
- 顺序例外：右键打开分页菜单时不先确认草稿，允许选择删除当前目标；删除动作先检查至少一页约束，再丢弃该目标草稿。菜单取消后再按实际焦点判断是否需要保存。
- 收起策略：自动收起遇到编辑会话一律拒绝；显式隐藏先尝试保存；Esc 仅取消会话。三个入口不混用。

## D6：输入法、原生编辑与可访问性使用同一条改名路径

- 候选：按 keyCode 无条件保存/取消 / 由原生输入系统优先处理 marked text，再转业务动作。
- 选择：先交给输入法；组字时不归一化中间串、不截断、不提交、不退出。
- 理由：确认候选和提交名称是两次不同操作，Esc 取消组字不应成为窗口收起。
- 否决无条件 keyCode：会丢候选文字或提前退出编辑。
- 键盘与辅助技术：原生标签可聚焦；Space 选择，Return 进入同一改名流程，提供本地化的 accessibility 自定义“重命名”动作。不新增独立页面。
- 编辑隔离：标题使用独立 UndoManager、纯文本复制粘贴和选区；正文格式命令在会话存在期间不执行。错误用统一枚举映射现有本地化系统，不把文案散落到视图中。

## D7：按用户路径拆分，测试沿用 XCTest

- 候选：先完成所有数据层再做所有视图 / 按文字导航、基本改名、离开编辑、输入访问、删除退出五条路径递增交付。
- 选择：五个可单独验证和提交的纵向切片，每片同时包含相应逻辑、调用入口与测试。
- 理由：每一步能检验真实收益或完整边界，不把风险全部压到最后联调。
- 否决横向切层：只有模型或只有输入框时无法验证闭环行为。
- 测试选择：沿用 SwiftPM/XCTest；原生控件及事件用进程内测试，真实中文输入法、VoiceOver、滚动观感和退出重启另列人工验收。
- 否决新建 Python/Web 测试框架：当前为原生 macOS 应用，用户已选择不安装通用测试引擎，新增工具链没有必要。
- 授权边界：本轮不提交；后续每个任务可形成一个 commit，但只有用户明确授权提交时才执行 Git 提交。测试通过不等于已获计划批准或发布许可。

## T1 实施记录

- 原分页数量同时参与视图换行和 NotebookView 的正文高度计算；只替换分页栏仍会留出多行空白，因此两处高度计算一起改为固定栏高。删除无引用的 WrappingHStack、TabDotButtonStyle 和旧“＋”样式，不改存储、正文与 Vendor。
- 测试使用不可见 NSPanel 承载真实 NSHostingView，验证按钮 action、visibleRect、单行位置和固定入口边界；覆盖 21 页溢出后往返选择首尾页、继续新建及完整 tooltip/辅助名称，不用单个布局常量替代导航验收。
- AppSettingsStore 构造会检查防休眠恢复状态；测试 fixture 在构造期间临时保护相关 UserDefaults 键并立即恢复，避免导航测试触发系统恢复流程。不为本任务扩展设置模块接口。
- 验证：原圆点实现上 3 个新增测试出现 4 次预期断言失败；替换后过滤集 3 项、全量 44 项 XCTest 均通过，`swift build` 成功。编译仍提示原正文选区闭包的隐式强捕获警告，该调用链由 T2 的选区归属改造处理。
- 尚未执行真实窗口视觉、输入法或 VoiceOver 人工验收；T1 当时只交付文字导航，不宣称双击改名已可用。

## T2 实施记录

- 磁盘写入成功前不能更新任何含新标题的恢复副本。标题提交先复制完整快照，在原串行队列同步写入，成功才发布；失败恢复先前待执行的正文保存。writer 只能处理 Data/URL，不得同步回主线程，否则会与 `persistenceQueue.sync` 死锁。普通正文保存的降级策略不变，大正文阻塞代价留在 T5 实测。
- 原正文查找接受任意 NSTextView，新标题输入会被误认并被格式命令改写。现在筛选非 field editor 且 delegate 为公开 NativeTextViewCoordinator 的视图；回调改为 `onDocumentSelectionChange(UUID, NSRange)`，通知当下捕获选区，binding generation 失效后不回写。Binder 携带文档 UUID，导航保存选区也检查 UUID，避免两次点击之间把旧页选区写到新页。
- 暂停正文焦点不只是阻止新的请求：已经排队的重试也必须失效。标题开始时取消正文重试及收起任务；展开的延迟激活另带 generation，结束标题会话不重放旧请求。原选区闭包的 weak/隐式强捕获警告已随 UUID 回调调整消除。
- 窗口保护抽成同文件内的 `TitlePanelInteraction`，供真实控制器的定时与全局 mouseUp 收起、正文激活共用。否决在测试中默认构造控制器：其初始化会读取真实笔记、图像 manifest 并启动全局监听。测试使用隔离会话与不可见 NotchPanel，验证 Esc 分发、门控动作次数和延迟执行；没有更改图像、暂存或防休眠模块来绕过副作用，也不把门控单测称为真实系统事件验收。
- 分页原生按钮第二次 mouseDown 开始改名；当前与非当前目标均用 UUID，输入框沿用初始标题槽位宽度。更新只同步错误说明，不重设草稿或选区。错误以栏下 overlay 显示，不撑高导航栏；三种中英文文案与 PRD 逐字一致。
- RED/GREEN：规则 3 项、存储新增 9 项、会话 4 项、输入 5 项、正文隔离 4 项、窗口保护 3 项、分页新增 3 项及本地化新增 1 项均经过预期断言失败再实现。C2 验证：指定过滤集 43 项、分页过滤集 6 项通过；完整 `swift test` 为 76 项、0 失败，`swift build` 成功。
- 阶段边界：T2 以双击、Enter/Esc 验证闭环；点击外部、菜单新建/隐藏和应用失活的统一保存仍由 T3 接入，当前编辑时显式隐藏暂时拒绝。完整 IME、纯文本粘贴、独立撤销及可访问改名由 T4 完成，删除/退出由 T5 完成。真实窗口视觉、输入法、VoiceOver 和正常退出重启均未人工验收，不发布；本轮不提交或推送。

## T3 实施记录

- 门控仍集中在 `TitlePanelInteraction`（进程内单测），不在测试里构造真实控制器。新增 `performNavigationAction`/`performExplicitHide`/`performAppDeactivationSave`/`performMenuAction` 与 `begin/endMenuTracking`，共用私有 `commitThenPerform`：无会话直接放行，有会话先 `commitIfNeeded`，成功才执行动作。`commitIfNeeded` 自带 `isCommitting` 防重入，重复通知/delegate 重入不会重复写盘或重放动作（`testSaveFailure` 连开三次离开均被拒且动作计数为 0）。
- **踩坑（测试前提）**：`TitleArchiveWriter.write` 每次调用先 `count += 1` 再判失败抛错，`writeCount` 统计的是「写入尝试次数」而非成功次数；失败写仍会让计数增长。早期用 `writeCount == before` 断言「失败不落盘」是错的（实际 5≠2、3≠2），改为真正的不变量：`customTitle` 仍为 nil、分页数量不变、动作计数为 0、会话保留。
- **踩坑（基线）**：`TitleFixture.init` 会先 `store.flush()` 一次，`writeCount` 起点非 0；断言必须相对进入前捕获的 `before`，不能假设从 0 起。
- **踩坑（编译）**：`NSWindow` 没有 `convert(_:from:)`/`hitTest(_:)`，这些是 `NSView` 方法；`isEventInsideTitleEditor` 需经 `contentView.convert(...)` + `contentView.hitTest(...)`，否则 `swift build` 直接失败。
- 事件接线按设计 5.4 放在窗口分发层：`NotchPanel.sendEvent` 对命中区在标题外的 `leftMouseDown` 先过 `performNavigationAction`，失败则置 `isConsumingMouseSequence` 吞掉本次 down 及随后的 drag/up，避免孤立 mouseUp 触发新动作。因此标签单击、固定“＋”、双击另一页的鼠标路径会在 SwiftUI/AppKit 控件收到事件前被门控消费，无须把门控注入视图。键盘与辅助技术入口归 T4。
- `createNote()`（菜单 Cmd+N）不经过窗口鼠标事件，作为独立离开入口单独包 `performNavigationAction`。`collapse(animated:)` 重定义为显式隐藏（`performExplicitHide`），拆出无门控的 `performCollapse`；全局 mouseUp 与 `scheduleCollapse` 两条自动收起路径改调 `performCollapse`，仍由外层 `performAutomaticCollapse` 保证会话内一律拒绝。
- 应用失活只监听 `NSApplication.didResignActiveNotification`，走 `performAppDeactivationSave(reactivate: {})`——无论成败都不重新激活应用；菜单跟踪用 `activeMenuTrackingCount` 的 0↔1 边沿驱动 `begin/endMenuTracking`，跟踪期间的离开请求既不提交也不放行。
- **已知债（不阻塞 T3，留待后续核实）**：① 设计 5.4「取消菜单后确已离开且应用活跃则再尝试提交」未在 T3 落地，当前依赖 sendEvent/全局路径处理真正离开，菜单自身不主动补存；② `sendEvent` 门控依赖输入框 `updateDraft` 实时同步草稿，带 marked text 时鼠标点击离开的「先 `unmarkText()` 再读完整串」路径属组字闭环，与键盘入口一并在 T4 覆盖；③ `isEventInsideTitleEditor` 用 `firstResponder`+hitTest 判定「标题内」，其真实性能（首响、输入法候选窗、滚动容器命中）需真实窗口人工验收，本层单测不冒充端到端。
- 验证：`testValidDraftCommitsBeforeSwitchOrAdd`、`testInvalidDraftBlocksClickAndCommandN`、`testSaveFailureDoesNotReplayDeferredAction`、`testExplicitHideCommitsOrStaysOpen`、`testAppDeactivationPreservesFailedDraftWithoutReactivation`、`testMenuTrackingDoesNotCommitCurrentDraft` 六项先看到方法不存在的编译失败，再经 GREEN 与断言前提修正后全部通过；C3 指定过滤集 17 项、完整 `swift test` 为 92 项、0 失败，`swift build` 成功。控制器真实事件接线（首响、菜单跟踪、失活、点击离开）未做人工验收，不发布；本轮不提交推送。
