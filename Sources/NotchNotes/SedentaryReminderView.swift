import AppKit
import SwiftUI

enum SedentaryReminderAsset {
    static func image(for phase: SedentaryReminderPhase) -> NSImage? {
        let name: String
        switch phase {
        case .due:
            name = "naruto-wind-chime-reminder-v1"
        case .snoozed:
            name = "naruto-wind-chime-snoozed-v1"
        case .activity:
            name = "naruto-wind-chime-activity-v1"
        case .completed:
            name = "naruto-wind-chime-complete-v1"
        case .paused:
            name = "naruto-wind-chime-paused-v1"
        case .disabled, .countingDown, .waitingForUnlock:
            name = "naruto-wind-chime-idle-v1"
        }

        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "SedentaryReminder"
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

struct SedentaryReminderWidgetView: View {
    @ObservedObject var store: SedentaryReminderStore
    let language: AppLanguage

    var body: some View {
        Button {
            store.presentCard()
        } label: {
            reminderImage
                .frame(width: 92, height: 144)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.sedentaryReminderWidgetLabel)
        .accessibilityValue(language.sedentaryReminderStatus(for: store.phase))
        .popover(isPresented: cardBinding, arrowEdge: .top) {
            SedentaryReminderCard(store: store, language: language)
        }
    }

    @ViewBuilder
    private var reminderImage: some View {
        if let image = SedentaryReminderAsset.image(for: store.phase) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "figure.stand")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    private var cardBinding: Binding<Bool> {
        Binding(
            get: { store.isCardPresented },
            set: { presented in
                if presented { store.presentCard() } else { store.dismissCard() }
            }
        )
    }
}

struct SedentaryReminderToolbarButton: View {
    @ObservedObject var store: SedentaryReminderStore
    let language: AppLanguage

    var body: some View {
        Button {
            store.presentCard()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(SedentaryReminderToolbarButtonStyle(isDue: store.phase == .due))
        .help(language.sedentaryReminderStatus(for: store.phase))
        .accessibilityLabel(language.sedentaryReminderWidgetLabel)
        .accessibilityValue(language.sedentaryReminderStatus(for: store.phase))
        .popover(isPresented: cardBinding, arrowEdge: .bottom) {
            SedentaryReminderCard(store: store, language: language)
        }
    }

    private var iconName: String {
        switch store.phase {
        case .paused: return "pause.circle.fill"
        case .activity: return "figure.walk.motion"
        case .due: return "bell.badge.fill"
        default: return "bell.fill"
        }
    }

    private var cardBinding: Binding<Bool> {
        Binding(
            get: { store.isCardPresented },
            set: { presented in
                if presented { store.presentCard() } else { store.dismissCard() }
            }
        )
    }
}

private struct SedentaryReminderToolbarButtonStyle: ButtonStyle {
    let isDue: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDue ? Color.orange : Color.white.opacity(0.76))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isDue ? Color.orange.opacity(0.16) : Color.white.opacity(0.055))
            )
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

private struct SedentaryReminderCard: View {
    @ObservedObject var store: SedentaryReminderStore
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let image = SedentaryReminderAsset.image(for: store.phase) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 72)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.sedentaryReminderStatus(for: store.phase))
                        .font(.headline)
                    if let detail = detailText {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            actionButtons
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch store.phase {
        case .due:
            Button(language.takeBreakTitle) { store.startActivity() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            HStack {
                if !store.hasSnoozed {
                    Button(language.snoozeTitle) { store.snooze() }
                }
                Button(language.skipBreakTitle) { store.skipCurrentRound() }
            }
        case .countingDown, .snoozed:
            HStack {
                Button(language.takeBreakNowTitle) { store.startActivity() }
                Button(language.pauseReminderTitle) { store.pause() }
            }
        case .activity:
            Button(language.finishActivityTitle) { store.endActivityEarly() }
        case .completed:
            Button(language.dismissTitle) { store.dismissCard() }
        case .paused:
            Button(language.resumeReminderTitle) { store.resume() }
        case .disabled, .waitingForUnlock:
            EmptyView()
        }
    }

    private var detailText: String? {
        switch store.phase {
        case .countingDown, .snoozed, .activity:
            return language.remainingTimeText(seconds: store.remainingSeconds)
        case .due:
            return language.breakInvitationText
        case .completed:
            return language.breakCompletedText
        case .paused:
            return language.reminderPausedText
        case .disabled, .waitingForUnlock:
            return nil
        }
    }
}

extension AppLanguage {
    var sedentaryReminderTitle: String {
        self == .chinese ? "久坐提醒" : "Break Reminder"
    }

    var sedentaryReminderWidgetLabel: String {
        self == .chinese ? "鸣人风铃久坐提醒" : "Naruto wind chime break reminder"
    }

    var reminderIntervalTitle: String {
        self == .chinese ? "提醒间隔" : "Reminder Interval"
    }

    var activityDurationTitle: String {
        self == .chinese ? "活动时长" : "Break Duration"
    }

    func minutesTitle(_ minutes: Int) -> String {
        self == .chinese ? "\(minutes) 分钟" : "\(minutes) min"
    }

    var pauseReminderTitle: String { self == .chinese ? "暂停提醒" : "Pause Reminders" }
    var resumeReminderTitle: String { self == .chinese ? "恢复提醒" : "Resume Reminders" }
    var takeBreakTitle: String { self == .chinese ? "起来活动" : "Take a Break" }
    var takeBreakNowTitle: String { self == .chinese ? "立即活动" : "Move Now" }
    var snoozeTitle: String { self == .chinese ? "5 分钟后提醒" : "Remind in 5 min" }
    var skipBreakTitle: String { self == .chinese ? "跳过本次" : "Skip This Time" }
    var finishActivityTitle: String { self == .chinese ? "结束计时" : "Finish Timer" }
    var dismissTitle: String { self == .chinese ? "知道了" : "Done" }
    var breakInvitationText: String {
        self == .chinese ? "起来动一动，陪鸣人伸个懒腰吧。" : "Time to move and stretch with Naruto."
    }
    var breakCompletedText: String {
        self == .chinese ? "活动计时结束，按自己的节奏继续吧。" : "Break timer finished. Carry on at your own pace."
    }
    var reminderPausedText: String {
        self == .chinese ? "提醒已暂停，准备好时再恢复。" : "Reminders are paused. Resume when you're ready."
    }

    func sedentaryReminderStatus(for phase: SedentaryReminderPhase) -> String {
        switch phase {
        case .disabled: return self == .chinese ? "久坐提醒已关闭" : "Break reminders off"
        case .countingDown: return self == .chinese ? "等待下次活动" : "Waiting for the next break"
        case .due: return self == .chinese ? "该起来活动了" : "Time to move"
        case .snoozed: return self == .chinese ? "稍后提醒" : "Reminder snoozed"
        case .activity: return self == .chinese ? "活动计时中" : "Break in progress"
        case .completed: return self == .chinese ? "活动计时完成" : "Break timer complete"
        case .paused: return self == .chinese ? "久坐提醒已暂停" : "Break reminders paused"
        case .waitingForUnlock: return self == .chinese ? "等待屏幕解锁" : "Waiting for screen unlock"
        }
    }

    func remainingTimeText(seconds: Int) -> String {
        if seconds < 60 {
            return self == .chinese ? "剩余 \(seconds) 秒" : "\(seconds)s remaining"
        }
        let minutes = Int(ceil(Double(seconds) / 60))
        return self == .chinese ? "剩余 \(minutes) 分钟" : "\(minutes) min remaining"
    }
}
