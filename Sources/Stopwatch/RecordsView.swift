import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Range totals shared by the records page and the exported image.
struct PracticeSummary {
    let today: Int
    let week: Int
    let month: Int
    let total: Int
    let streak: Int
    let seats: Int
    let names: Int

    init(sessions: [Session], now: Date = Date(), liveNames: Int = 0) {
        let calendar = Calendar.current
        today = Stats.seconds(sessions, from: now, through: now)
        week = calendar.dateInterval(of: .weekOfYear, for: now)
            .map { Stats.seconds(sessions, from: $0.start, through: now) } ?? 0
        month = calendar.dateInterval(of: .month, for: now)
            .map { Stats.seconds(sessions, from: $0.start, through: now) } ?? 0
        total = sessions.reduce(0) { $0 + $1.seconds }
        streak = Stats.streak(sessions, now: now)
        seats = sessions.count
        names = sessions.reduce(0) { $0 + $1.count } + liveNames
    }
}

struct RecordsView: View {
    @ObservedObject private var model = TimerModel.shared
    @State private var confirmingClear = false
    @State private var exportMessage: String?
    @State private var exported: ExportedImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("念佛记录")
                    .font(.title2.weight(.semibold))
                Spacer()
                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("导出图片") { exportImage() }
                    .disabled(model.sessions.isEmpty)
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
        .confirmationDialog("清空全部念佛记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                model.clearAll()
                exportMessage = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除 SQLite 中的全部念佛记录，无法撤销。先生成一张统计图留档更稳妥。")
        }
        .sheet(item: $exported) { image in
            ExportPreview(image: image)
        }
    }

    private var summary: some View {
        let values = PracticeSummary(sessions: model.sessions, now: Date(),
                                     liveNames: model.seatCount)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                         alignment: .leading, spacing: 12) {
            SummaryCard(title: "今日", value: TimeFormat.compact(values.today))
            SummaryCard(title: "本周", value: TimeFormat.compact(values.week))
            SummaryCard(title: "本月", value: TimeFormat.compact(values.month))
            SummaryCard(title: "累计", value: TimeFormat.compact(values.total))
            SummaryCard(title: "连续天数", value: "\(values.streak) 天 · \(values.seats) 座")
            SummaryCard(title: "佛号", value: "\(values.names) 声")
        }
    }

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

    /// Renders the statistics as a picture and shows it — the export is the image itself.
    private func exportImage() {
        let card = ExportCardView(sessions: model.sessions)
            .environment(\.colorScheme, .light)
        guard let image = OffscreenRender.image(of: card, width: 760),
              let png = OffscreenRender.png(image) else {
            exportMessage = "生成图片失败"
            return
        }
        exportMessage = "已生成 \(png.count / 1024) KB"
        exported = ExportedImage(png: png)
    }
}

struct ExportedImage: Identifiable {
    let id = UUID()
    let png: Data
}

struct ExportPreview: View {
    @Environment(\.dismiss) private var dismiss
    let image: ExportedImage
    @State private var savedMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("念佛统计图")
                .font(.headline)
            if let nsImage = NSImage(data: image.png) {
                ScrollView {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                }
                .frame(width: 560, height: 520)
                .background(Color(nsColor: .textBackgroundColor))
                .cardSurface()
            }
            if let savedMessage {
                Text(savedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("关闭") { dismiss() }
                Button("存储为图片…") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Exporter.suggestedFileName()
        panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        savedMessage = Exporter.write(image.png, to: url)
    }
}

/// The exported picture: everything worth keeping from the archive on one page.
struct ExportCardView: View {
    let sessions: [Session]
    private let summary: PracticeSummary

    init(sessions: [Session]) {
        self.sessions = sessions
        self.summary = PracticeSummary(sessions: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("念佛统计")
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
                Text(TimeFormat.dateLabel.string(from: Date()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      alignment: .leading, spacing: 12) {
                BigStat(label: "累计念佛", value: TimeFormat.compact(summary.total))
                BigStat(label: "佛号", value: "\(summary.names) 声")
                BigStat(label: "连续", value: "\(summary.streak) 天 · \(summary.seats) 座")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      alignment: .leading, spacing: 12) {
                BigStat(label: "今日", value: TimeFormat.compact(summary.today), small: true)
                BigStat(label: "本周", value: TimeFormat.compact(summary.week), small: true)
                BigStat(label: "本月", value: TimeFormat.compact(summary.month), small: true)
            }

            HeatmapCard(sessions: sessions, cell: 15)

            VStack(alignment: .leading, spacing: 6) {
                Text("最近十座")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(sessions.sorted { $0.start > $1.start }.prefix(10)) { session in
                    HStack(spacing: 0) {
                        Text(TimeFormat.dayLabel.string(from: session.start))
                            .frame(width: 110, alignment: .leading)
                        Text(TimeFormat.timeLabel.string(from: session.start))
                            .frame(width: 56, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if session.count > 0 {
                            Text("\(session.count) 声")
                                .frame(width: 60, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                        Text(TimeFormat.compact(session.seconds))
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
            }

            Divider()

            HStack {
                Text("南无阿弥陀佛")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("本地记录 · 念佛计时")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(width: 760, alignment: .leading)
        .background(Color.white)
    }
}

private struct BigStat: View {
    let label: String
    let value: String
    var small = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: small ? 15 : 19, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .cardSurface()
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
        .cardSurface()
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
                    if stat.count > 0 {
                        Text("\(stat.count) 声")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
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
                        if session.count > 0 {
                            Text("\(session.count) 声")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
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
        .cardSurface()
        .contextMenu {
            Button("删除本日全部", role: .destructive) {
                TimerModel.shared.deleteDay(stat.day)
            }
        }
    }
}

struct HeatmapCard: View {
    let sessions: [Session]
    /// The exported picture is narrower than the window, so it asks for smaller cells.
    var cell: CGFloat = 18
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
                                .frame(width: cell, height: cell)
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
        .cardSurface()
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
