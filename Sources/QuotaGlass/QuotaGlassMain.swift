@preconcurrency import AppKit
import Foundation

@main
enum QuotaGlassMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--probe") {
            let delegate = ProbeDelegate()
            application.delegate = delegate
            application.setActivationPolicy(.prohibited)
            application.run()
            _ = delegate
            return
        }

        guard let instanceLock = SingleInstanceLock(identifier: "com.jianxun.quotaglass") else {
            return
        }

        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(instanceLock) {
            application.run()
        }
        _ = delegate
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let provider = CodexRateLimitProvider(pollInterval: .seconds(600))

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let stream = await provider.stateStream()
            await provider.start()

            let timeout = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                print(#"{"ok":false,"error":"timeout"}"#)
                await provider.stop()
                NSApplication.shared.terminate(nil)
            }

            for await state in stream {
                switch state {
                case .available(let snapshot):
                    timeout.cancel()
                    let output: [String: Any] = [
                        "ok": true,
                        "source": snapshot.selected.sourceID,
                        "window": snapshot.selected.displayName,
                        "remainingPercent": snapshot.selected.remainingPercent,
                        "windowCount": snapshot.windows.count,
                        "resetsAt": snapshot.selected.resetsAt?.timeIntervalSince1970 as Any
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: output),
                       let line = String(data: data, encoding: .utf8) {
                        print(line)
                    }
                    await provider.stop()
                    NSApplication.shared.terminate(nil)
                    break

                case .clientMissing:
                    timeout.cancel()
                    print(#"{"ok":false,"error":"clientMissing"}"#)
                    await provider.stop()
                    NSApplication.shared.terminate(nil)

                case .loginRequired(let message), .unsupportedVersion(let message):
                    timeout.cancel()
                    let safeMessage = message ?? "unknown"
                    let output = ["ok": false, "error": safeMessage] as [String: Any]
                    if let data = try? JSONSerialization.data(withJSONObject: output),
                       let line = String(data: data, encoding: .utf8) {
                        print(line)
                    }
                    await provider.stop()
                    NSApplication.shared.terminate(nil)

                default:
                    continue
                }
            }
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let provider = CodexRateLimitProvider()
    private var viewModel: QuotaViewModel?
    private var panelController: DesktopPanelController?
    private var wakeObserver: NSObjectProtocol?
    private var terminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = QuotaViewModel(provider: provider)
        self.viewModel = viewModel
        panelController = DesktopPanelController(viewModel: viewModel)
        panelController?.show()
        viewModel.start()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            Task { @MainActor in viewModel?.refresh() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        Task { [weak self, weak sender] in
            await self?.viewModel?.stop()
            await MainActor.run {
                sender?.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
