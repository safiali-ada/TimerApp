import Foundation

/// Completed focus sessions per calendar day, kept in UserDefaults.
@MainActor
final class FocusStats: ObservableObject {
    struct Day: Codable, Equatable {
        var seconds = 0
        var sessions = 0
    }

    @Published private(set) var days: [String: Day]

    private static let key = "focusStats"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        days = data.flatMap { try? JSONDecoder().decode([String: Day].self, from: $0) } ?? [:]
    }

    func record(seconds: Int, on date: Date = Date()) {
        let key = Self.formatter.string(from: date)
        var day = days[key] ?? Day()
        day.seconds += seconds
        day.sessions += 1
        days[key] = day
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func day(_ date: Date) -> Day { days[Self.formatter.string(from: date)] ?? Day() }

    var today: Day { day(Date()) }

    /// Consecutive days with at least one session. Today not having one yet doesn't break the streak.
    var streak: Int {
        let calendar = Calendar.current
        var date = Date()
        if today.sessions == 0 { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while day(date).sessions > 0 {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    /// The last seven days, oldest first.
    var week: [(date: Date, day: Day)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            return (date, day(date))
        }
    }

    static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
