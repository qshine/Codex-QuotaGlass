@preconcurrency import AppKit
import Combine
import Foundation
import QuotaGlassCore
import SwiftUI

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published private(set) var state: QuotaState = .loading
    @Published var isExpanded = false
    @Published private(set) var showsLaunchPrompt: Bool

    let launchAtLogin = LaunchAtLoginManager()

    private let provider: any RateLimitProvider
    private var streamTask: Task<Void, Never>?

    init(provider: any RateLimitProvider) {
        self.provider = provider
        showsLaunchPrompt = !UserDefaults.standard.bool(forKey: "hasAnsweredLaunchAtLoginPrompt")
    }

    var livePercent: Int? {
        guard case .available(let snapshot) = state else { return nil }
        return snapshot.selected.remainingPercent
    }

    var visibleSnapshot: QuotaSnapshot? {
        state.snapshot
    }

    var selectedWindow: QuotaWindow? {
        visibleSnapshot?.selected
    }

    var headline: String {
        switch state {
        case .loading: "正在连接 Codex"
        case .available(let snapshot): snapshot.selected.displayName
        case .stale: "数据已过期"
        case .clientMissing: "未找到 Codex"
        case .loginRequired: "需要登录 Codex"
        case .unsupportedVersion: "版本暂不兼容"
        case .unavailable: "额度暂不可用"
        }
    }

    var stateDetail: String? {
        switch state {
        case .stale(let snapshot):
            return "上次同步于 \(snapshot.lastUpdated.formatted(date: .omitted, time: .shortened))"
        case .clientMissing:
            return "请安装官方 ChatGPT/Codex 客户端"
        case .loginRequired(let message), .unsupportedVersion(let message):
            return message
        case .unavailable(let message):
            return message
        default:
            return nil
        }
    }

    func start() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self, provider] in
            let stream = await provider.stateStream()
            for await nextState in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.apply(nextState)
                }
            }
        }
        Task { await provider.start() }
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        await provider.stop()
    }

    func refresh() {
        Task { await provider.refresh() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
    }

    func answerLaunchPrompt(enable: Bool) {
        UserDefaults.standard.set(true, forKey: "hasAnsweredLaunchAtLoginPrompt")
        showsLaunchPrompt = false
        if enable { setLaunchAtLogin(true) }
    }

    func openOfficialClient() {
        CodexLocator.openOfficialClient()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func resetText(at date: Date = Date()) -> String {
        guard let reset = selectedWindow?.resetsAt else { return "重置时间未知" }
        let interval = max(0, reset.timeIntervalSince(date))
        if interval == 0 { return "等待额度重置" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return "\(formatter.string(from: interval) ?? "即将")后重置"
    }

    private func apply(_ nextState: QuotaState) {
        let nextPercent: Int?
        if case .available(let snapshot) = nextState {
            nextPercent = snapshot.selected.remainingPercent
        } else {
            nextPercent = nil
        }

        withAnimation(.easeInOut(duration: 0.8)) {
            state = nextState
        }

        if nextPercent == nil, isExpanded, nextState.snapshot == nil {
            isExpanded = false
        }
    }
}
