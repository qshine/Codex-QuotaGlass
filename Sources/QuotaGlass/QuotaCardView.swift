import QuotaGlassCore
import SwiftUI

struct QuotaCardView: View {
    @ObservedObject var model: QuotaViewModel

    private var isStale: Bool {
        if case .stale = model.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            HourglassVisual(percent: model.livePercent, isStale: isStale)

            Text(model.livePercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(model.headline)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let detail = model.stateDetail
                let message = detail ?? model.resetText(at: timeline.date)
                Text(message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(detail == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if model.showsLaunchPrompt {
                launchPrompt
            }

            if model.isExpanded, let snapshot = model.visibleSnapshot {
                Divider().opacity(0.5)
                details(snapshot)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 226)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            guard model.visibleSnapshot != nil else { return }
            withAnimation(.snappy(duration: 0.28)) {
                model.isExpanded.toggle()
            }
        }
        .contextMenu { contextMenu }
    }

    private var header: some View {
        HStack {
            Label("QuotaGlass", systemImage: "hourglass")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
        .foregroundStyle(.secondary)
    }

    private var launchPrompt: some View {
        VStack(spacing: 7) {
            Text("登录 Mac 后自动显示沙漏？")
                .font(.system(size: 11, weight: .medium))
            HStack(spacing: 8) {
                Button("暂不") { model.answerLaunchPrompt(enable: false) }
                Button("开启") { model.answerLaunchPrompt(enable: true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func details(_ snapshot: QuotaSnapshot) -> some View {
        VStack(spacing: 7) {
            ForEach(snapshot.windows) { window in
                HStack(spacing: 8) {
                    Circle()
                        .fill(window.id == snapshot.selected.id ? Color.yellow : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(window.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text("\(window.remainingPercent)%")
                        .monospacedDigit()
                }
                .font(.system(size: 10, design: .rounded))
            }

            Text("同步于 \(snapshot.lastUpdated.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("立即刷新") { model.refresh() }
        Button(model.launchAtLogin.isEnabled ? "关闭登录时启动" : "登录时启动") {
            model.setLaunchAtLogin(!model.launchAtLogin.isEnabled)
        }
        Divider()
        Button("打开官方客户端") { model.openOfficialClient() }
        Button("关于 QuotaGlass") { model.isExpanded = true }
        Divider()
        Button("退出") { model.quit() }
    }
}
