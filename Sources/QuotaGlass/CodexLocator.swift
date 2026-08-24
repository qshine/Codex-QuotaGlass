import AppKit
import Foundation

enum CodexLocator {
    @MainActor
    static func locateExecutable() -> URL? {
        if let override = ProcessInfo.processInfo.environment["QUOTAGLASS_CODEX_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            let bundled = appURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("codex", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }

        let knownPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }

        return nil
    }

    @MainActor
    static func openOfficialClient() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        } else if let downloadURL = URL(string: "https://chatgpt.com/codex") {
            NSWorkspace.shared.open(downloadURL)
        }
    }
}
