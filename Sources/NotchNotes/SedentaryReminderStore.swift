import Combine
import Foundation

enum SedentaryReminderInterval: Int, CaseIterable, Identifiable {
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }
    var seconds: Int { rawValue * 60 }
}

enum SedentaryActivityDuration: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5

    var id: Int { rawValue }
    var seconds: Int { rawValue * 60 }
}

enum SedentaryReminderPhase: Equatable {
    case disabled
    case countingDown
    case due
    case snoozed
    case activity
    case completed
    case paused
    case waitingForUnlock
}

@MainActor
final class SedentaryReminderStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isPaused: Bool
    @Published var showsPendant: Bool {
        didSet { defaults.set(showsPendant, forKey: Self.showsPendantKey) }
    }
    @Published var interval: SedentaryReminderInterval {
        didSet { defaults.set(interval.rawValue, forKey: Self.intervalKey) }
    }
    @Published var activityDuration: SedentaryActivityDuration {
        didSet { defaults.set(activityDuration.rawValue, forKey: Self.activityDurationKey) }
    }
    @Published private(set) var phase: SedentaryReminderPhase
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var hasSnoozed = false
    @Published private(set) var isScreenAvailable = true
    @Published private(set) var isCardPresented = false

    static let snoozeSeconds = 5 * 60
    static let completionFeedbackSeconds = 3

    private static let enabledKey = "notchNotes.sedentaryReminder.enabled"
    private static let pausedKey = "notchNotes.sedentaryReminder.paused"
    private static let showsPendantKey = "notchNotes.sedentaryReminder.showsPendant"
    private static let intervalKey = "notchNotes.sedentaryReminder.intervalMinutes"
    private static let activityDurationKey = "notchNotes.sedentaryReminder.activityMinutes"

    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let automaticallyTicks: Bool
    private var deadline: TimeInterval?
    private var timer: Timer?
    private var presentationSuppressed = false
    private var didAutomaticallyPresentCurrentDue = false

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        automaticallyTicks: Bool = true
    ) {
        self.defaults = defaults
        self.now = now
        self.automaticallyTicks = automaticallyTicks

        let loadedInterval = SedentaryReminderInterval(
            rawValue: defaults.integer(forKey: Self.intervalKey)
        ) ?? .fortyFive
        let loadedActivityDuration = SedentaryActivityDuration(
            rawValue: defaults.integer(forKey: Self.activityDurationKey)
        ) ?? .two
        interval = loadedInterval
        activityDuration = loadedActivityDuration

        let loadedEnabled = defaults.bool(forKey: Self.enabledKey)
        let loadedPaused = loadedEnabled && defaults.bool(forKey: Self.pausedKey)
        isEnabled = loadedEnabled
        isPaused = loadedPaused
        showsPendant = defaults.bool(forKey: Self.showsPendantKey)

        if !loadedEnabled {
            phase = .disabled
            remainingSeconds = 0
        } else if loadedPaused {
            phase = .paused
            remainingSeconds = 0
        } else {
            phase = .countingDown
            remainingSeconds = loadedInterval.seconds
            deadline = now() + TimeInterval(loadedInterval.seconds)
        }

        startTimerIfNeeded()
    }

    var shouldDisplayPendant: Bool {
        guard isEnabled, isScreenAvailable else { return false }
        return showsPendant || phase == .due || phase == .completed
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)

        if enabled {
            isPaused = false
            defaults.set(false, forKey: Self.pausedKey)
            if isScreenAvailable {
                startNewRound()
            } else {
                phase = .waitingForUnlock
            }
            startTimerIfNeeded()
        } else {
            isPaused = false
            defaults.set(false, forKey: Self.pausedKey)
            phase = .disabled
            remainingSeconds = 0
            deadline = nil
            hasSnoozed = false
            isCardPresented = false
            stopTimer()
        }
    }

    func pause() {
        guard isEnabled, !isPaused else { return }
        isPaused = true
        defaults.set(true, forKey: Self.pausedKey)
        phase = .paused
        remainingSeconds = 0
        deadline = nil
        isCardPresented = false
    }

    func resume() {
        guard isEnabled, isPaused else { return }
        isPaused = false
        defaults.set(false, forKey: Self.pausedKey)
        if isScreenAvailable {
            startNewRound()
        } else {
            phase = .waitingForUnlock
        }
        startTimerIfNeeded()
    }

    func startActivity() {
        guard isEnabled, isScreenAvailable, !isPaused, phase != .activity else { return }
        phase = .activity
        remainingSeconds = activityDuration.seconds
        deadline = now() + TimeInterval(activityDuration.seconds)
        isCardPresented = false
        startTimerIfNeeded()
    }

    func snooze() {
        guard isEnabled, phase == .due, !hasSnoozed else { return }
        hasSnoozed = true
        phase = .snoozed
        remainingSeconds = Self.snoozeSeconds
        deadline = now() + TimeInterval(Self.snoozeSeconds)
        isCardPresented = false
        startTimerIfNeeded()
    }

    func skipCurrentRound() {
        guard isEnabled, isScreenAvailable, !isPaused else { return }
        startNewRound()
    }

    func endActivityEarly() {
        guard phase == .activity else { return }
        startNewRound()
    }

    func presentCard() {
        guard isEnabled, isScreenAvailable else { return }
        isCardPresented = true
    }

    func dismissCard() {
        isCardPresented = false
    }

    func setPresentationSuppressed(_ suppressed: Bool) {
        presentationSuppressed = suppressed
        if suppressed {
            isCardPresented = false
        } else if phase == .due, !didAutomaticallyPresentCurrentDue {
            automaticallyPresentCardIfAllowed()
        }
    }

    func handleScreenUnavailable() {
        guard isScreenAvailable else { return }
        isScreenAvailable = false
        deadline = nil
        remainingSeconds = 0
        isCardPresented = false
        if isEnabled {
            phase = .waitingForUnlock
        }
    }

    func handleScreenAvailable() {
        guard !isScreenAvailable else { return }
        isScreenAvailable = true
        guard isEnabled else {
            phase = .disabled
            return
        }
        if isPaused {
            phase = .paused
        } else {
            startNewRound()
        }
        startTimerIfNeeded()
    }

    func tick() {
        guard isEnabled, isScreenAvailable, !isPaused, let deadline else { return }
        let seconds = max(Int(ceil(deadline - now())), 0)
        remainingSeconds = seconds
        guard seconds == 0 else { return }

        self.deadline = nil
        switch phase {
        case .countingDown, .snoozed:
            phase = .due
            didAutomaticallyPresentCurrentDue = false
            automaticallyPresentCardIfAllowed()
        case .activity:
            phase = .completed
            remainingSeconds = Self.completionFeedbackSeconds
            self.deadline = now() + TimeInterval(Self.completionFeedbackSeconds)
            automaticallyPresentCardIfAllowed()
        case .completed:
            startNewRound()
        case .disabled, .due, .paused, .waitingForUnlock:
            break
        }
    }

    func stopTicking() {
        stopTimer()
    }

    private func startNewRound() {
        phase = .countingDown
        remainingSeconds = interval.seconds
        deadline = now() + TimeInterval(interval.seconds)
        hasSnoozed = false
        isCardPresented = false
        didAutomaticallyPresentCurrentDue = false
        startTimerIfNeeded()
    }

    private func automaticallyPresentCardIfAllowed() {
        guard !presentationSuppressed else { return }
        isCardPresented = true
        didAutomaticallyPresentCurrentDue = true
    }

    private func startTimerIfNeeded() {
        guard automaticallyTicks, timer == nil, isEnabled else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
