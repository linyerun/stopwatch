import Foundation

enum Exporter {
    static func suggestedFileName(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd"
        return "念佛统计-\(formatter.string(from: date)).png"
    }

    /// Writes the PNG and returns a line the UI can show as-is.
    static func write(_ data: Data, to url: URL) -> String {
        do {
            try data.write(to: url)
            return "已保存到 \(url.path)"
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
    }
}
