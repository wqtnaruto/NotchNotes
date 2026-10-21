import AppKit
import SwiftUI

@MainActor
final class TitlePanelInteraction {
    let state: TitleEditingState
    private(set) var activationGeneration = 0
    /// 上下文菜单跟踪期间，临时失焦不得提交当前草稿（设计 5.4）。
    private var isMenuTracking = false

    init(state: TitleEditingState, editor: EditorInteractionState, cancelCollapse: @escaping () -> Void) {
        self.state = state
        editor.isFocusSuspended = state.isEditing
        state.onEditingChanged = { [weak self, weak editor] isEditing in
            editor?.isFocusSuspended = isEditing
            if isEditing {
                self?.activationGeneration += 1
                cancelCollapse()
            }
        }
    }

    func performAutomaticCollapse(_ action: () -> Void) {
        guard !state.isEditing else { return }
        action()
    }

    func performEditorActivation(generation: Int? = nil, _ action: () -> Void) {
        guard !state.isEditing, generation == nil || generation == activationGeneration else { return }
        action()
    }

    // MARK: - T3 离开编辑与导航/收起/失焦的统一确认门控

    /// 切页、双击另一页、固定“＋”、菜单新建等「离开编辑再执行原动作」的入口。
    /// 合法草稿先提交成功才放行原动作；非法/写失败时保留会话与原动作前状态，不放行。
    /// 菜单跟踪期间的离开请求既不提交也不放行。
    @discardableResult
    func performNavigationAction(_ action: () -> Void) -> Bool {
        if isMenuTracking { return false }
        return commitThenPerform(action)
    }

    /// 显式隐藏（如 Cmd+W）：提交成功才隐藏，失败保持面板打开、会话不结束。
    @discardableResult
    func performExplicitHide(_ hide: () -> Void) -> Bool {
        commitThenPerform(hide)
    }

    /// 应用失活：先尝试提交；成功才允许调用方按需重新激活，失败保留草稿且不抢焦点。
    @discardableResult
    func performAppDeactivationSave(reactivate: () -> Void) -> Bool {
        guard commitThenPerform({}) else { return false }
        reactivate()
        return true
    }

    /// 上下文菜单动作按自身语义执行，绝不因打开/操作菜单而提交当前草稿。
    func performMenuAction(_ action: () -> Void) {
        action()
    }

    func beginMenuTracking() { isMenuTracking = true }
    func endMenuTracking() { isMenuTracking = false }

    /// 统一提交原语：无会话直接放行；有会话则先 commitIfNeeded，成功才执行动作。
    /// commitIfNeeded 内部已有 isCommitting 防重入，重复调用不会重复写盘或重复放行动作。
    private func commitThenPerform(_ action: () -> Void) -> Bool {
        guard state.isEditing else { action(); return true }
        guard state.commitIfNeeded() else { return false }
        action()
        return true
    }
}

@MainActor
final class NotchPanel: NSPanel {
    weak var titleInteraction: TitlePanelInteraction?
    var onMouseEvent: ((NSEvent) -> Void)?
    var onEscape: (() -> Void)?
    /// 标题外点击提交失败后，消费同一手势的后续拖动/up，避免孤立 mouseUp 触发新动作（设计 5.4）。
    private var isConsumingMouseSequence = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            if let state = titleInteraction?.state, let session = state.session {
                if let titleView = firstResponder as? TitleTextView, titleView.hasMarkedText() {
                    super.sendEvent(event)
                    return
                }
                state.cancel()
                TitleTextView.restoreLabelFocus(tabID: session.tabID, window: self, state: state)
                return
            }
            onEscape?()
            return
        }

        if event.type == .leftMouseDown,
           let interaction = titleInteraction,
           interaction.state.isEditing,
           !isEventInsideTitleEditor(event) {
            // 离开标题：先同步提交；成功则放行同一个事件继续分发，失败则消费整个手势。
            if !interaction.performNavigationAction({}) {
                isConsumingMouseSequence = true
                return
            }
        } else if event.type == .leftMouseDragged || event.type == .leftMouseUp {
            if isConsumingMouseSequence {
                if event.type == .leftMouseUp { isConsumingMouseSequence = false }
                return
            }
        }

        if event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp {
            onMouseEvent?(event)
        }

        super.sendEvent(event)
    }

    /// 命中标题输入框（含其滚动容器）时交给原生文本系统处理，不触发提交（设计 5.4）。
    private func isEventInsideTitleEditor(_ event: NSEvent) -> Bool {
        guard let titleView = firstResponder as? TitleTextView, let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hit = contentView.hitTest(point) else { return false }
        return hit == titleView
            || hit.isDescendant(of: titleView)
            || titleView.isDescendant(of: hit)
    }
}

@MainActor
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
class TransparentHitHostingView<Content: View>: FirstMouseHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        // SwiftUI may return nil when every rendered pixel is transparent.
        // Keep the panel's full compact frame interactive without drawing a background.
        return super.hitTest(point) ?? self
    }
}

@MainActor
final class CompactFileDropHostingView<Content: View>: TransparentHitHostingView<Content> {
    var onFileDragTargeted: ((Bool) -> Void)?
    var onFilesDropped: (([URL]) -> Bool)?

    private var isFileDragTargeted = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard supportsFileURLs(sender.draggingPasteboard) else { return [] }
        setFileDragTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        supportsFileURLs(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setFileDragTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setFileDragTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        supportsFileURLs(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setFileDragTargeted(false) }
        let urls = FileDropPasteboardReader.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        return onFilesDropped?(urls) ?? false
    }

    private func supportsFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL]) != nil
    }

    private func setFileDragTargeted(_ isTargeted: Bool) {
        guard isFileDragTargeted != isTargeted else { return }
        isFileDragTargeted = isTargeted
        onFileDragTargeted?(isTargeted)
    }
}

@MainActor
final class NotchPanelController: NSObject {
    private let store = NoteStore()
    private(set) lazy var titleEditingState = TitleEditingState(store: store)
    private lazy var titleInteraction = TitlePanelInteraction(
        state: titleEditingState, editor: editorInteractionState,
        cancelCollapse: { [weak self] in self?.cancelCollapse() }
    )
    private(set) var settingsStore = AppSettingsStore()
    private let imageStore = LocalImageStore()
    private let fileShelfStore = FileShelfStore()
    private let workspaceState = NotebookWorkspaceState()
    private let drawerState = DrawerState()
    private let editorInteractionState = EditorInteractionState()
    private let hotPanel: NotchPanel
    private let drawerPanel: NotchPanel
    private var hostingView: NSHostingView<NotebookView>?
    private var hotHostingView: CompactFileDropHostingView<CompactNotchView>?
    private var mousePollingTimer: Timer?
    private var globalMouseDownMonitor: Any?
    private var globalMouseDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var isExpanded = false
    private var isRevealedForFileDrag = false
    private var activeMenuTrackingCount = 0
    private var collapseTask: DispatchWorkItem?
    private var completedDragChangeCount = NSPasteboard(name: .drag).changeCount

    override init() {
        hotPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        drawerPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel(hotPanel)
        configurePanel(drawerPanel)
        drawerPanel.titleInteraction = titleInteraction
        hotPanel.titleInteraction = titleInteraction
        rebuildContent()
        startMousePolling()
        observeScreenChanges()
        observePanelMouseEvents()
        observeGlobalMouseEvents()
        observeMenuTracking()
        observeApplicationDeactivation()
    }

    func showDocked() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        isExpanded = false
        isRevealedForFileDrag = false
        drawerState.isExpanded = false
        drawerState.revealProgress = 0
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        hotPanel.orderFrontRegardless()
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        drawerPanel.orderOut(nil)
    }

    func expand(animated: Bool, activate: Bool = true) {
        if isExpanded {
            finishFileDragRevealIfNeeded()
            if activate {
                activateEditor()
            }
            return
        }
        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        isRevealedForFileDrag = false
        rebuildContent(layout: layout)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            drawerPanel.makeKeyAndOrderFront(nil)
        } else {
            drawerPanel.orderFrontRegardless()
        }
        hotPanel.orderOut(nil)
        setDrawerExpanded(true, animated: animated)
        guard activate else { return }
        let generation = titleInteraction.activationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.isExpanded else { return }
            self.titleInteraction.performEditorActivation(generation: generation) {
                self.activateEditor()
            }
        }
    }

    func collapse(animated: Bool) {
        // 显式隐藏（Cmd+W / 菜单隐藏）：存在会话时先确认，失败不隐藏（设计 5.5）。
        titleInteraction.performExplicitHide { [weak self] in
            self?.performCollapse(animated: animated)
        }
    }

    /// 无会话门控的实际收起；自动收起需由调用方先过 performAutomaticCollapse（检查 !isEditing）。
    private func performCollapse(animated: Bool) {
        guard isExpanded else { return }
        if let range = editorInteractionState.currentSelectionRange(for: store.activeTabID) {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        store.flush(waitForDisk: false)
        isExpanded = false
        isRevealedForFileDrag = false
        workspaceState.isShelfDropTargeted = false
        setDrawerExpanded(false, animated: animated)
        let delay: TimeInterval = animated ? 0.18 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isExpanded else { return }
            let layout = self.currentLayout()
            self.drawerPanel.orderOut(nil)
            self.hotPanel.setFrame(self.hotFrame(for: layout), display: true)
            self.hotPanel.orderFrontRegardless()
        }
    }

    func createNote() {
        // Cmd+N / 菜单新建是独立于鼠标事件的离开入口，需与点击共用同一提交门控（设计 5.4）。
        titleInteraction.performNavigationAction { [weak self] in
            self?.performCreateNote()
        }
    }

    private func performCreateNote() {
        if let range = editorInteractionState.currentSelectionRange(for: store.activeTabID) {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        store.addTab()
        expand(animated: true, activate: true)
    }

    private func configurePanel(_ panel: NotchPanel) {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func rebuildContent(layout: NotchLayout? = nil) {
        let layout = layout ?? currentLayout()
        let hotView = CompactNotchView(layout: layout, settingsStore: settingsStore)
        let view = NotebookView(
            store: store,
            settingsStore: settingsStore,
            imageStore: imageStore,
            fileShelfStore: fileShelfStore,
            workspaceState: workspaceState,
            drawerState: drawerState,
            editorInteractionState: editorInteractionState,
            titleEditingState: titleEditingState,
            layout: layout
        )

        if let hotHostingView {
            hotHostingView.rootView = hotView
            configureCompactFileDropCallbacks(hotHostingView)
        } else {
            let host = CompactFileDropHostingView(rootView: hotView)
            configureCompactFileDropCallbacks(host)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            hotPanel.contentView = host
            hotHostingView = host
        }

        if let hostingView {
            hostingView.rootView = view
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        drawerPanel.contentView = host
        hostingView = host
    }

    private func configureCompactFileDropCallbacks(
        _ host: CompactFileDropHostingView<CompactNotchView>
    ) {
        host.onFileDragTargeted = { [weak self] isTargeted in
            self?.handleFileDragTargeted(isTargeted)
        }
        host.onFilesDropped = { [weak self] urls in
            self?.receiveDroppedFiles(urls) ?? false
        }
    }

    private func setDrawerExpanded(_ expanded: Bool, animated: Bool) {
        guard animated else {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
            return
        }

        let animation: Animation = expanded
            ? .spring(response: 0.28, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)

        withAnimation(animation) {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
        }
    }

    private func startMousePolling() {
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(mousePollingTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        mousePollingTimer = timer
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observePanelMouseEvents() {
        hotPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            guard event.type == .leftMouseDown else { return }
            self.handleActivationClick(at: NotchActivationPolicy.screenLocation(for: event))
        }

        drawerPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown {
                NSApp.activate(ignoringOtherApps: true)
                self.drawerPanel.makeKeyAndOrderFront(nil)
            } else if event.type == .leftMouseUp {
                self.completedDragChangeCount = NSPasteboard(name: .drag).changeCount
                self.workspaceState.isDraggingShelfItem = false
                self.resetFileDropState()
            }
            self.editorInteractionState.handleMouseEvent(event, searchingIn: self.hostingView)
        }

        hotPanel.onEscape = { [weak self] in self?.collapse(animated: true) }
        drawerPanel.onEscape = { [weak self] in self?.collapse(animated: true) }
    }

    private func observeGlobalMouseEvents() {
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            // 在派发到主 actor 前保存事件位置，避免快速移动后的鼠标位置影响命中判断。
            let location = event.locationInWindow
            Task { @MainActor in
                self?.handleActivationClick(at: location)
            }
        }

        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseDragged()
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.editorInteractionState.noteGlobalMouseUp()
                self.completedDragChangeCount = NSPasteboard(name: .drag).changeCount
                self.workspaceState.isDraggingShelfItem = false
                self.resetFileDropState()
                self.finishFileDragRevealIfNeeded()
                let location = NSEvent.mouseLocation
                if self.isExpanded,
                   !self.workspaceState.isPreviewingShelfItem,
                   !self.isPointInExpandedStayRegion(location) {
                    self.titleInteraction.performAutomaticCollapse {
                        self.performCollapse(animated: true)
                    }
                } else {
                    self.handleMouseLocation(location)
                }
            }
        }
    }

    private func observeMenuTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    /// 只监听应用真正失活；输入法候选窗口/菜单短暂夺取 key 不在此列（已由菜单跟踪覆盖）。
    private func observeApplicationDeactivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        // 失焦尝试提交；无论成功失败都不重新激活应用，失败时保留会话与草稿（设计 5.5）。
        titleInteraction.performAppDeactivationSave(reactivate: {})
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        cancelCollapse()
        rebuildContent(layout: layout)
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
    }

    @objc private func mousePollingTick(_ timer: Timer) {
        handleMouseLocation(NSEvent.mouseLocation)
    }

    @objc private func menuTrackingDidBegin(_ notification: Notification) {
        if activeMenuTrackingCount == 0 { titleInteraction.beginMenuTracking() }
        activeMenuTrackingCount += 1
        cancelCollapse()
    }

    @objc private func menuTrackingDidEnd(_ notification: Notification) {
        activeMenuTrackingCount = max(0, activeMenuTrackingCount - 1)
        if activeMenuTrackingCount == 0 { titleInteraction.endMenuTracking() }
        guard activeMenuTrackingCount == 0, isExpanded else { return }
        handleMouseLocation(NSEvent.mouseLocation)
    }

    private func handleMouseLocation(_ point: NSPoint) {
        if !isExpanded, isFileDrag(at: point) {
            let layout = currentLayout()
            hotPanel.setFrame(fileDropFrame(for: layout), display: true)
            hotPanel.orderFrontRegardless()
            handleFileDragTargeted(true)
            return
        }

        if isExpanded {
            if titleEditingState.isEditing {
                cancelCollapse()
                return
            }
            if activeMenuTrackingCount > 0 {
                cancelCollapse()
                return
            }

            if editorInteractionState.isDraggingSelection {
                cancelCollapse()
                return
            }

            if workspaceState.isDraggingShelfItem {
                cancelCollapse()
                return
            }

            if workspaceState.isPreviewingShelfItem {
                cancelCollapse()
                return
            }

            if settingsStore.triggerMode == .click || editorInteractionState.hasKeyboardFocus() {
                cancelCollapse()
                return
            }

            if isPointInExpandedStayRegion(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if NotchActivationPolicy.shouldExpand(
            for: .mouseMoved, at: point, in: activationFrame(),
            mode: settingsStore.triggerMode,
            isLeftMousePressed: NSEvent.pressedMouseButtons & 1 != 0
        ) {
            expand(animated: true, activate: false)
        }
    }

    private func handleActivationClick(at location: NSPoint) {
        guard !isExpanded,
              NotchActivationPolicy.shouldExpand(
                for: .leftMouseDown, at: location, in: activationFrame(),
                mode: settingsStore.triggerMode
              ) else { return }
        expand(animated: true, activate: true)
    }

    private func scheduleCollapse() {
        guard !titleEditingState.isEditing, collapseTask == nil else { return }
        guard activeMenuTrackingCount == 0 else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.activeMenuTrackingCount == 0 else { return }
            guard !self.editorInteractionState.isDraggingSelection else { return }
            guard !self.workspaceState.isDraggingShelfItem else { return }
            guard !self.isPointInExpandedStayRegion(NSEvent.mouseLocation) else { return }
            self.titleInteraction.performAutomaticCollapse {
                self.performCollapse(animated: true)
            }
        }

        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func activationFrame() -> NSRect {
        hotFrame(for: currentLayout())
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 10
        return drawerPanel.frame.insetBy(dx: -margin, dy: -margin).contains(point)
            || activationFrame().contains(point)
    }

    private func receiveDroppedFiles(_ urls: [URL]) -> Bool {
        guard fileShelfStore.acceptDrop(urls) else {
            resetFileDropState()
            return false
        }

        resetFileDropState()

        // Do not replace the NSWindow that owns the active dragging destination
        // until AppKit has finished the drop callback and closed its tracking loop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isExpanded {
                self.finishFileDragRevealIfNeeded()
            } else {
                self.expand(animated: true, activate: false)
            }
        }
        return true
    }

    private func handleFileDragTargeted(_ isTargeted: Bool) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
            workspaceState.isShelfDropTargeted = isTargeted
        }

        if isTargeted {
            revealDrawerForFileDrag()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.finishFileDragRevealIfNeeded()
            }
        }
    }

    private func resetFileDropState() {
        workspaceState.isShelfDropTargeted = false
        guard !isExpanded else { return }
        let layout = currentLayout()
        hotPanel.setFrame(hotFrame(for: layout), display: true)
    }

    private func revealDrawerForFileDrag() {
        guard !isExpanded else { return }

        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        isRevealedForFileDrag = true
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        drawerPanel.orderFrontRegardless()
        hotPanel.orderFrontRegardless()
        setDrawerExpanded(true, animated: true)
    }

    private func finishFileDragRevealIfNeeded() {
        guard isRevealedForFileDrag else { return }
        isRevealedForFileDrag = false
        hotPanel.orderOut(nil)
        drawerPanel.orderFrontRegardless()
    }

    func flush() {
        settingsStore.stopKeepingAwake()
        store.flush(waitForDisk: true)
        imageStore.flush()
    }

    private func activateEditor() {
        titleInteraction.performEditorActivation {
            NSApp.activate(ignoringOtherApps: true)
            drawerPanel.makeKeyAndOrderFront(nil)
            editorInteractionState.prepareForDocument(store.activeTabID)
            editorInteractionState.restoreSelection(
                store.selectionRange(for: store.activeTabID),
                searchingIn: hostingView
            )
            editorInteractionState.requestLayoutRefresh(searchingIn: hostingView)
            editorInteractionState.requestFocus(searchingIn: hostingView)
        }
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(for: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func hotFrame(for layout: NotchLayout) -> NSRect {
        NotchGeometry.activationFrame(for: layout, in: targetScreenFrame())
    }

    private func fileDropFrame(for layout: NotchLayout) -> NSRect {
        NotchGeometry.fileDropFrame(for: layout, in: targetScreenFrame())
    }

    private func drawerFrame(for layout: NotchLayout) -> NSRect {
        let screenFrame = targetScreenFrame()
        let topY = screenFrame.maxY + layout.expandedTopOffset
        return NotchGeometry.topCenteredFrame(
            for: layout.expandedSize,
            topY: topY,
            in: screenFrame
        )
    }

    private func targetScreenFrame() -> NSRect {
        targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func isFileDrag(at point: NSPoint) -> Bool {
        let isPressed = NSEvent.pressedMouseButtons & 1 != 0
        guard !isExpanded, isPressed else { return false }

        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        guard NotchActivationPolicy.shouldInspectFileDrag(
            isExpanded: isExpanded,
            isLeftMousePressed: isPressed,
            pasteboardChanged: changeCount != completedDragChangeCount
        ) else {
            return false
        }

        return NotchActivationPolicy.shouldRevealForFileDrag(
            at: point, in: fileDropFrame(for: currentLayout()),
            isLeftMousePressed: isPressed,
            containsFileURLs: FileDropPasteboardReader.containsFileURLs(pasteboard),
            pasteboardChangeCount: changeCount,
            completedDragChangeCount: completedDragChangeCount
        )
    }
}
