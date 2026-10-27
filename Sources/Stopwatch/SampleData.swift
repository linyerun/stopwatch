import Foundation

/// Builds the .app-free sample history used by `NIANFO_DEMO=1` so the UI can be
/// shown and verified without writing to the real records file.
enum SampleData {
    static func sessions(now: Date = .now) -> [Session] {
        let calendar = Calendar.current
        let minutes: [[Int]] = [
            [25, 35], [15], [30, 30, 12], [45], [20, 25], [50], [30]
        ]
        var result: [Session] = []
        for (daysBack, dayMinutes) in minutes.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            for (index, minute) in dayMinutes.enumerated() {
                guard let start = calendar.date(bySettingHour: 6 + index * 7, minute: index * 13,
                                                second: 0, of: day) else { continue }
                let end = start.addingTimeInterval(TimeInterval(minute * 60))
                result.append(Session(start: start, end: end, seconds: minute * 60,
                                      count: minute * 8))
            }
        }
        return result
    }
}
