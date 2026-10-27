import Foundation

enum Exporter {
    static func csv(_ sessions: [Session]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = ["开始时间,结束时间,时长(秒),时长(分),佛号数,座次"]
        let sorted = sessions.sorted { $0.start < $1.start }
        for (index, s) in sorted.enumerated() {
            lines.append("\(formatter.string(from: s.start)),\(formatter.string(from: s.end)),\(s.seconds),\(String(format: "%.2f", Double(s.seconds) / 60)),\(s.count),\(index + 1)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ sessions: [Session]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions.sorted { $0.start < $1.start })
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func write(_ contents: String, to url: URL) -> URL {
        try? contents.data(using: .utf8)?.write(to: url)
        return url
    }
}
