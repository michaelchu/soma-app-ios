import Foundation
import UserNotifications

// MARK: - Daily measurement reminders (local notifications)

@MainActor
final class ReminderManager: ObservableObject {
    static let shared = ReminderManager()

    @Published private(set) var errorMessage: String?

    private let enabledKey = "soma.reminderEnabled"
    private let timeKey = "soma.reminderTime" // seconds since midnight

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            apply()
        }
    }
    /// Time of day for the reminder, as seconds since midnight. Default 8:00 AM.
    @Published var timeSeconds: Int {
        didSet {
            UserDefaults.standard.set(timeSeconds, forKey: timeKey)
            apply()
        }
    }

    var time: Date {
        get {
            var comps = DateComponents()
            comps.hour = timeSeconds / 3600
            comps.minute = (timeSeconds % 3600) / 60
            return Calendar.current.date(from: comps) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            timeSeconds = (comps.hour ?? 8) * 3600 + (comps.minute ?? 0) * 60
        }
    }

    var timeLabel: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: time)
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
        self.timeSeconds = UserDefaults.standard.object(forKey: timeKey) as? Int ?? 8 * 3600
    }

    func requestPermission() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                errorMessage = nil
                return true
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                errorMessage = granted ? nil : "Notifications are disabled. Enable them in Settings to use reminders."
                return granted
            case .denied:
                errorMessage = "Notifications are disabled. Enable them in Settings to use reminders."
                return false
            @unknown default:
                errorMessage = "Could not determine notification permission."
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Schedules (or cancels) the daily notification to match current settings.
    func apply() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["soma.daily-reminder"])
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to measure"
        content.body = "Take your blood pressure reading."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = timeSeconds / 3600
        comps.minute = (timeSeconds % 3600) / 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "soma.daily-reminder",
            content: content,
            trigger: trigger
        )
        center.add(request) { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription
            }
        }
    }
}
