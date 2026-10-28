import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = TimerModel.shared
        if ProcessInfo.processInfo.environment["NIANFO_DEMO"] == "1", model.sessions.isEmpty {
            model.seed(SampleData.sessions())
        }
        // The menu bar text is easy to miss on a crowded (or notched) menu bar, so the
        // window with the timer always comes up on launch.
        HistoryWindow.shared.show()
    }

    /// Relaunching from Finder or Launchpad should surface the timer again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HistoryWindow.shared.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

struct MenuBarLabel: View {
    @ObservedObject private var model = TimerModel.shared

    var body: some View {
        if model.hasActiveSession {
            Text("念佛 \(TimeFormat.clock(model.elapsedSeconds)) · \(model.seatCount) 声")
                .monospacedDigit()
        } else {
            Text("佛 \(TimeFormat.clock(model.todaySeconds)) · \(model.todayCount) 声")
                .monospacedDigit()
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject private var model = TimerModel.shared
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 2) {
                Text(TimeFormat.clock(model.elapsedSeconds))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.hasActiveSession ? Color.primary : Color.secondary)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            HStack {
                Spacer()
                TapButton(size: 96)
                Spacer()
            }

            controls

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("最近")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if model.recentSessions.isEmpty {
                    Text("还没有记录，点一下中间的圆即可开始。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(model.recentSessions.prefix(4)) { session in
                        HStack {
                            Text(TimeFormat.dayLabel.string(from: session.start))
                            Text(TimeFormat.timeLabel.string(from: session.start))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if session.count > 0 {
                                Text("\(session.count) 声")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(TimeFormat.compact(session.seconds))
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            HStack {
                Button("计时窗口") { HistoryWindow.shared.show() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 300)
        .confirmationDialog("放弃本座？已念的 \(model.seatCount) 声不会保存。",
                            isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { model.discardActive() }
            Button("继续念", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日 \(TimeFormat.compact(model.todaySeconds)) · \(model.todayCount) 声")
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

                Button("放弃") {
                    if model.seatCount > 0 {
                        confirmingDiscard = true
                    } else {
                        model.discardActive()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .controlSize(.large)
        } else {
            Button("开始念佛") { model.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The 一念 counter: one tap is one 南无阿弥陀佛. Tapping while idle also starts the seat.
struct TapButton: View {
    @ObservedObject private var model = TimerModel.shared
    let size: CGFloat
    /// On the 念佛 page the button sits on the Buddha image, so it drops the dark label.
    var onImage: Bool = false

    var body: some View {
        Button {
            model.tap()
        } label: {
            ZStack {
                Circle()
                    .fill(onImage
                          ? Color.white.opacity(model.seatCount > 0 ? 0.16 : 0.08)
                          : Color.orange.opacity(model.seatCount > 0 ? 0.22 : 0.10))
                    .overlay(Circle().stroke(onImage ? Color.orange : Color.orange.opacity(0.75),
                                             lineWidth: onImage ? 3 : 2))
                VStack(spacing: 2) {
                    Text("\(model.seatCount)")
                        .font(.system(size: size * 0.32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(onImage ? Color.white : Color.primary)
                    Text("一声一念")
                        .font(.system(size: size * 0.11))
                        .foregroundStyle(onImage ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("点一下＝念一声南无阿弥陀佛")
        .keyboardShortcut(.defaultAction)
    }
}
