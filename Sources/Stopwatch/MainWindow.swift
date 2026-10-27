import SwiftUI
import AppKit

/// Two pages: 念佛 is the practice surface over the Amitabha backdrop, 记录 is the archive.
struct MainWindow: View {
    enum Page: Hashable { case chanting, records }

    @State private var page: Page = .chanting

    var body: some View {
        ZStack {
            if page == .chanting {
                BuddhaGround()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }

            VStack(spacing: 0) {
                HStack {
                    Picker("页面", selection: $page) {
                        Text("念佛").tag(Page.chanting)
                        Text("记录").tag(Page.records)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                switch page {
                case .chanting: ChantingView()
                case .records: RecordsView()
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .modifier(DarkOnBackpage(isDark: page == .chanting))
    }
}

/// The 念佛 page sits on a dark photograph, so its controls must stay light-on-dark;
/// 记录 keeps following the system appearance.
private struct DarkOnBackpage: ViewModifier {
    let isDark: Bool

    func body(content: Content) -> some View {
        if isDark {
            content.colorScheme(.dark)
        } else {
            content
        }
    }
}

/// The practice page: the seat timer, the 一念 counter, and today's totals — nothing else,
/// so the screen stays quiet while chanting.
struct ChantingView: View {
    @ObservedObject private var model = TimerModel.shared
    @State private var confirmingDiscard = false

    var body: some View {
        // One floating dock at the foot of the image: the statue stays whole above it,
        // and timer, counter, actions and totals share a single aligned surface.
        VStack(spacing: 12) {
            BuddhaFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .shadow(color: .black.opacity(0.6), radius: 4, y: 1)

            dock
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .confirmationDialog("放弃本座？已念的 \(model.seatCount) 声不会保存。",
                            isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { model.discardActive() }
            Button("继续念", role: .cancel) {}
        }
    }

    private var dock: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("本座")
                    .font(.caption2)
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.55))
                Text(TimeFormat.clock(model.elapsedSeconds))
                    .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            dockDivider

            TapButton(size: 104, onImage: true)

            VStack(alignment: .trailing, spacing: 10) {
                controls

                HStack(spacing: 20) {
                    FootStat(label: "今日", value: TimeFormat.compact(model.todaySeconds))
                    FootStat(label: "今日佛号", value: "\(model.todayCount) 声")
                    FootStat(label: "连续", value: "\(model.streakDays) 天")
                    FootStat(label: "累计", value: TimeFormat.compact(model.totalSeconds))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(LinearGradient(colors: [Color.black.opacity(0.52), Color.black.opacity(0.34)],
                                   startPoint: .bottom, endPoint: .top),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    private var dockDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 56)
    }

    private var statusLine: String {
        if model.isRunning { return "念佛中 · 回车或点圆钮各计一声" }
        if model.isPaused { return "已暂停 · 点圆钮继续计数" }
        return "点圆钮即开始本座并计第一声"
    }

    @ViewBuilder
    private var controls: some View {
        if model.hasActiveSession {
            HStack(spacing: 10) {
                Button(model.isRunning ? "暂停" : "继续") {
                    model.isRunning ? model.pause() : model.resume()
                }
                .buttonStyle(GlassButton())

                Button("结束本座") { model.finish() }
                    .buttonStyle(GlassButton(prominent: true))

                Button("放弃") {
                    if model.seatCount > 0 {
                        confirmingDiscard = true
                    } else {
                        model.discardActive()
                    }
                }
                .buttonStyle(GlassButton())
            }
        } else {
            Button("开始念佛") { model.start() }
                .buttonStyle(GlassButton(prominent: true))
        }
    }
}

private struct FootStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

/// Capsule buttons legible on the photograph.
struct GlassButton: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(prominent ? Color.orange : Color.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0 : 0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func cardSurface() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}
