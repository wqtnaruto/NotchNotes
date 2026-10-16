import Combine
import Foundation

enum TriggerMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .hover:
            return language.localized(.hover)
        case .click:
            return language.localized(.click)
        }
    }

    var systemImage: String {
        switch self {
        case .hover:
            return "cursorarrow.motionlines"
        case .click:
            return "cursorarrow.click.2"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var triggerMode: TriggerMode {
        didSet {
            defaults.set(triggerMode.rawValue, forKey: Self.triggerModeKey)
        }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    @Published private(set) var isKeepingAwake = false
    @Published private(set) var isChangingKeepAwake = false
    @Published private(set) var keepAwakeErrorMessage: String?

    private static let triggerModeKey = "notchNotes.triggerMode"
    private static let completedClickTriggerMigrationKey = "notchNotes.completedClickTriggerMigrationV1"
    private static let languageKey = "notchNotes.language"
    private static let ownsSleepDisabledKey = "notchNotes.ownsSleepDisabled"
    private static let completedSleepGuardMigrationKey = "notchNotes.completedSleepGuardRecoveryV1"
    private var caffeinateProcess: Process?
    private let systemSleepGuard = SystemSleepGuard()
    private var keepAwakeTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        triggerMode = Self.loadTriggerMode(from: defaults)

        let rawLanguage = defaults.string(forKey: Self.languageKey)
        language = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .chinese

        let needsOwnedStateRecovery = defaults.bool(forKey: Self.ownsSleepDisabledKey)
        let needsLegacyRecovery = !defaults.bool(forKey: Self.completedSleepGuardMigrationKey)
            && SystemSleepGuard.isSleepDisabled()

        if needsOwnedStateRecovery || needsLegacyRecovery {
            isKeepingAwake = SystemSleepGuard.isSleepDisabled()
            isChangingKeepAwake = true
            keepAwakeTask = Task { [weak self] in
                await self?.recoverSleepAfterUnexpectedExit()
            }
        } else {
            defaults.set(true, forKey: Self.completedSleepGuardMigrationKey)
            defaults.set(false, forKey: Self.ownsSleepDisabledKey)
        }
    }

    private static func loadTriggerMode(from defaults: UserDefaults) -> TriggerMode {
        // 仅首次升级切换为点按；之后保留用户主动选择的悬停模式。
        if !defaults.bool(forKey: completedClickTriggerMigrationKey) {
            defaults.set(TriggerMode.click.rawValue, forKey: triggerModeKey)
            defaults.set(true, forKey: completedClickTriggerMigrationKey)
            return .click
        }
        return defaults.string(forKey: triggerModeKey).flatMap(TriggerMode.init(rawValue:)) ?? .click
    }

    func toggleKeepAwake() {
        guard !isChangingKeepAwake else { return }

        if isKeepingAwake {
            stopKeepingAwake()
        } else {
            requestKeepAwake()
        }
    }

    func stopKeepingAwake() {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        systemSleepGuard.requestStop()
        isChangingKeepAwake = true

        let process = caffeinateProcess
        caffeinateProcess = nil

        if let process, process.isRunning {
            process.terminate()
        }

        keepAwakeTask = Task { [weak self] in
            guard let self else { return }
            let didStop = await self.systemSleepGuard.resetSleepIfNeeded()
            guard !Task.isCancelled else { return }

            self.setOwnsSleepDisabled(!didStop)
            self.isKeepingAwake = !didStop && SystemSleepGuard.isSleepDisabled()
            self.isChangingKeepAwake = false
            if !didStop {
                self.keepAwakeErrorMessage = self.language.localized(.keepAwakeErrorRestore)
            }
            self.keepAwakeTask = nil
        }
    }

    func dismissKeepAwakeError() {
        keepAwakeErrorMessage = nil
    }

    private func requestKeepAwake() {
        guard caffeinateProcess == nil, !systemSleepGuard.isRunning else { return }

        isChangingKeepAwake = true
        keepAwakeErrorMessage = nil
        setOwnsSleepDisabled(true)

        do {
            try systemSleepGuard.start()
        } catch {
            setOwnsSleepDisabled(false)
            isChangingKeepAwake = false
            keepAwakeErrorMessage = language.localized(.keepAwakeErrorPrevent)
            return
        }

        keepAwakeTask = Task { [weak self] in
            guard let self else { return }
            let isReady = await self.systemSleepGuard.waitUntilReady()
            guard !Task.isCancelled else { return }

            guard isReady, self.startCaffeinate() else {
                let didReset = await self.systemSleepGuard.resetSleepIfNeeded()
                self.setOwnsSleepDisabled(!didReset)
                self.isKeepingAwake = !didReset && SystemSleepGuard.isSleepDisabled()
                self.isChangingKeepAwake = false
                self.keepAwakeErrorMessage = self.language.localized(.keepAwakeErrorPrevent)
                self.keepAwakeTask = nil
                return
            }

            self.isKeepingAwake = true
            self.isChangingKeepAwake = false
            self.keepAwakeTask = nil
        }
    }

    private func startCaffeinate() -> Bool {
        guard caffeinateProcess == nil else { return true }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = [
            "-dims",
            "-w",
            String(ProcessInfo.processInfo.processIdentifier)
        ]

        do {
            try process.run()
            caffeinateProcess = process
            return true
        } catch {
            caffeinateProcess = nil
            return false
        }
    }

    private func recoverSleepAfterUnexpectedExit() async {
        let didReset = await systemSleepGuard.resetSleepIfNeeded()
        guard !Task.isCancelled else { return }

        setOwnsSleepDisabled(!didReset)
        if didReset {
            defaults.set(true, forKey: Self.completedSleepGuardMigrationKey)
        }
        isKeepingAwake = !didReset && SystemSleepGuard.isSleepDisabled()
        isChangingKeepAwake = false
        if !didReset {
            keepAwakeErrorMessage = language.localized(.keepAwakeErrorRestore)
        }
        keepAwakeTask = nil
    }

    private func setOwnsSleepDisabled(_ ownsSleepDisabled: Bool) {
        defaults.set(ownsSleepDisabled, forKey: Self.ownsSleepDisabledKey)
    }
}
