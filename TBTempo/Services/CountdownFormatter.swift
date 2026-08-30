import Foundation

enum CountdownFormatter {
    static func daysRemaining(until date: Date?, from now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Int? {
        guard let date else { return nil }
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    static func text(until date: Date?, from now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let days = daysRemaining(until: date, from: now, calendar: calendar) else {
            return String(localized: "date not confirmed")
        }
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "tomorrow")
        case let value where value > 1: return String(localized: "in \(value) days")
        case -1: return String(localized: "yesterday")
        default: return String(localized: "released")
        }
    }
}
