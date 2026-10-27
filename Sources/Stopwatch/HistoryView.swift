import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject private var model = TimerModel.shared
    @State private var confirmingClear = false
    @State private var exportedMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("念佛记录")
                    .font(.title2.weight(.semibold))
                Spacer()
                if let exportedMessage {
                    Text(exportedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Button("导出 CSV") { export(kind: .csv) }
                Button("导出 JSON") { export(kind: .json) }
                Button("清空", role: .destructive) { confirmingClear = true }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    HeatmapCard(sessions: model.sessions)
                    dayList
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .confirmationDialog("清空全部念佛记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                model.clearAll()
                exportedMessage = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本机所有计时记录，无法撤销。导出 CSV 备份后再清空更稳妥。")
        }
    }

    // MARK: summary

    private var summary: some View {
        let calendar = Calendar.current
        let now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        let today = Stats.seconds(model.sessions, from: now, through: now)
        let weekSeconds = week.map { Stats.seconds(model.sessions, from: $0.start, through: now) } ?? 0
        let monthSeconds = month.map { Stats.seconds(model.sessions, from: $0.start, through: now) } ?? 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                         alignment: .leading, spacing: 12) {
            SummaryCard(title: "今日", value: TimeFormat.compact(today))
            SummaryCard(title: "本周", value: TimeFormat.compact(weekSeconds))
            SummaryCard(title: "本月", value: TimeFormat.compact(monthSeconds))
            SummaryCard(title: "累计", value: TimeFormat.compact(model.totalSeconds))
            SummaryCard(title: "连续天数", value: "\(model.streakDays) 天")
            SummaryCard(title: "总座数", value: "\(model.sessions.count) 座")
        }
    }

    // MARK: day list

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按日明细")
                .font(.headline)
            if model.dayStats.isEmpty {
                Text("暂无记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                ForEach(model.dayStats) { stat in
                    DayRow(stat: stat)
                }
            }
        }
    }

    // MARK: export

    private enum Kind { case csv, json }

    private func export(kind: Kind) {
        guard !model.sessions.isEmpty else {
            exportedMessage = "还没有可导出的记录"
            return
        }
        let isCSV = kind == .csv
        let panel = NSSavePanel()
        panel.nameFieldStringValue = isCSV ? "念佛记录.csv" : "念佛记录.json"
        panel.allowedContentTypes = isCSV ? [.commaSeparatedText] : [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let contents = isCSV ? Exporter.csv(model.sessions) : try Exporter.json(model.sessions)
            Exporter.write(contents, to: url)
            exportedMessage = "已导出：\(url.lastPathComponent)"
        } catch {
            exportedMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

struct DayRow: View {
    let stat: DayStat
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(TimeFormat.dayLabel.string(from: stat.day))
                        .frame(width: 120, alignment: .leading)
                    Spacer()
                    Text("\(stat.sessions.count) 座")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TimeFormat.compact(stat.seconds))
                        .monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                ForEach(stat.sessions) { session in
                    HStack {
                        Text("\(TimeFormat.timeLabel.string(from: session.start)) – \(TimeFormat.timeLabel.string(from: session.end))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(TimeFormat.clock(session.seconds))
                            .monospacedDigit()
                        Button {
                            TimerModel.shared.delete(session)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除这一座")
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        .contextMenu {
            Button("删除本日全部", role: .destructive) {
                TimerModel.shared.deleteDay(stat.day)
            }
        }
    }
}

struct HeatmapCard: View {
    let sessions: [Session]
    private let weeks = 36

    var body: some View {
        let calendar = mondayCalendar
        let dayMap = dictionaryByDay(calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        // Rows run Monday-first, so the grid always ends on the coming Sunday.
        let weekday = calendar.component(.weekday, from: today)
        let mondayIndex = (weekday + 5) % 7
        let alignedEnd = calendar.date(byAdding: .day, value: 6 - mondayIndex, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: alignedEnd) ?? today
        let columns = stride(from: 0, to: weeks * 7, by: 7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("近 \(weeks) 周")
                .font(.headline)
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 4) {
                    ForEach(["一", "三", "五"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, alignment: .leading)
                    }
                }
                .padding(.top, 1)
                ForEach(columns, id: \.self) { weekStart in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = calendar.date(byAdding: .day, value: row, to: weekStart) ?? weekStart
                            Rectangle()
                                .fill(color(for: dayMap[day] ?? 0, peak: dayMap.values.max() ?? 0))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.primary.opacity(day == today ? 0.35 : 0), lineWidth: 1)
                                )
                                .help("\(TimeFormat.dayLabel.string(from: day)) \(TimeFormat.compact(dayMap[day] ?? 0))")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text("少")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                    Rectangle()
                        .fill(palette(level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }

    private var mondayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private func dictionaryByDay(calendar: Calendar) -> [Date: Int] {
        var map: [Date: Int] = [:]
        for stat in Stats.dayStats(sessions, calendar: calendar) {
            map[stat.day] = stat.seconds
        }
        return map
    }

    private func color(for seconds: Int, peak: Int) -> Color {
        guard seconds > 0 else { return Color.primary.opacity(0.06) }
        let ratio = Double(seconds) / Double(max(seconds, peak))
        return palette(ratio <= 0.25 ? 1 : ratio <= 0.5 ? 2 : ratio <= 0.75 ? 3 : 4)
    }

    private func palette(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.06)
        case 1: return Color.orange.opacity(0.25)
        case 2: return Color.orange.opacity(0.45)
        case 3: return Color.orange.opacity(0.68)
        default: return Color.orange.opacity(0.9)
        }
    }
}
