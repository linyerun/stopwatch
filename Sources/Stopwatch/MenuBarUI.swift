import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = TimerModel.shared
        if ProcessInfo.processInfo.environment["NIANFO_DEMO"] == "1", model.sessions.isEmpty {
            model.seed(SampleData.sessions())
        }
        // Nothing to point at the app on first run, so show the records window.
        if !model.hasSavedData || ProcessInfo.processInfo.environment["NIANFO_OPEN_WINDOW"] == "1" {
            HistoryWindow.shared.show()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

struct MenuBarLabel: View {
    @ObservedObject private var model = TimerModel.shared

    var body: some View {
        if model.hasActiveSession {
            Text("念佛 \(TimeFormat.clock(model.elapsedSeconds))")
                .monospacedDigit()
        } else {
            Text("佛 \(TimeFormat.clock(model.todaySeconds))")
                .monospacedDigit()
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject private var model = TimerModel.shared
    private var elapsed: Int { model.elapsedSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 2) {
                Text(TimeFormat.clock(elapsed))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.hasActiveSession ? Color.primary : Color.secondary)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            controls

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("最近")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if model.recentSessions.isEmpty {
                    Text("还没有记录，按下开始即可。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(model.recentSessions.prefix(4)) { session in
                        HStack {
                            Text(TimeFormat.dayLabel.string(from: session.start))
                            Text(TimeFormat.timeLabel.string(from: session.start))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TimeFormat.compact(session.seconds))
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            HStack {
                Button("记录窗口") { HistoryWindow.shared.show() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日 \(TimeFormat.compact(model.todaySeconds))")
                    .font(.subheadline.weight(.medium))
                Text("连续 \(model.streakDays) 天 · \(model.sessions.count) 座")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.isRunning ? Color.red.opacity(0.85) : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
        }
    }

    private var statusLine: String {
        if model.isRunning { return "念佛中" }
        if model.isPaused { return "已暂停" }
        return "未开始"
    }

    @ViewBuilder
    private var controls: some View {
        if model.hasActiveSession {
            HStack(spacing: 8) {
                Button(model.isRunning ? "暂停" : "继续") {
                    model.isRunning ? model.pause() : model.resume()
                }
                .frame(maxWidth: .infinity)

                Button("结束本座") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("放弃") { model.discardActive() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.large)
        } else {
            Button("开始念佛") { model.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
