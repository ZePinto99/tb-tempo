import Foundation
import UserNotifications

struct NotificationSettings: Codable, Sendable {
    var globalEnabled: Bool
    var hour: Int
    var minute: Int
    var horizonDays: Int
    var rollingLimit: Int

    static var current: NotificationSettings {
        NotificationSettings(
            globalEnabled: UserDefaults.standard.bool(forKey: "notificationsEnabled"),
            hour: UserDefaults.standard.object(forKey: "notificationHour") as? Int ?? 9,
            minute: UserDefaults.standard.object(forKey: "notificationMinute") as? Int ?? 0,
            horizonDays: 90,
            rollingLimit: 50
        )
    }
}

struct NotificationCandidate: Hashable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let airDate: Date?
    let isWatched: Bool
    let isActive: Bool
    let isEnabled: Bool
}

struct PlannedNotification: Hashable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
}

protocol NotificationScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func reschedule(candidates: [NotificationCandidate], settings: NotificationSettings) async throws
}

enum NotificationPlanner {
    static func plan(
        candidates: [NotificationCandidate],
        settings: NotificationSettings,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlannedNotification] {
        guard settings.globalEnabled else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: settings.horizonDays, to: today) else { return [] }
        return candidates.compactMap { candidate -> PlannedNotification? in
            guard candidate.isEnabled, candidate.isActive, !candidate.isWatched, let airDate = candidate.airDate else { return nil }
            let releaseDay = calendar.startOfDay(for: airDate)
            guard releaseDay >= today, releaseDay <= horizon else { return nil }
            var components = calendar.dateComponents([.year, .month, .day], from: releaseDay)
            components.hour = settings.hour
            components.minute = settings.minute
            components.second = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }
            return PlannedNotification(identifier: candidate.identifier, title: candidate.title, body: candidate.body, date: fireDate)
        }
        .sorted { $0.date < $1.date }
        .prefix(max(0, settings.rollingLimit))
        .map { $0 }
    }
}

actor LocalNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func reschedule(candidates: [NotificationCandidate], settings: NotificationSettings) async throws {
        let planned = NotificationPlanner.plan(candidates: candidates, settings: settings)
        let existing = await center.pendingNotificationRequests()
        let managed = existing.map(\.identifier).filter { $0.hasPrefix("tbtempo.episode.") }
        center.removePendingNotificationRequests(withIdentifiers: managed)
        let calendar = Calendar.autoupdatingCurrent
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}
