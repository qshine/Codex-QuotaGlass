@preconcurrency import Foundation
@preconcurrency import Network
import QuotaGlassCore

actor CodexRateLimitProvider: RateLimitProvider {
    private let pollInterval: Duration
    private let staleInterval: TimeInterval
    private let debugEnabled = ProcessInfo.processInfo.environment["QUOTAGLASS_DEBUG"] == "1"

    private var continuations: [UUID: AsyncStream<QuotaState>.Continuation] = [:]
    private var currentState: QuotaState = .loading
    private var lastSnapshot: QuotaSnapshot?

    private var process: Process?
    private var inputHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    private var nextRequestID = 1
    private var quotaRequestIDs: Set<Int> = []
    private var reconnectAttempt = 0
    private var started = false
    private var stopping = false
    private var connecting = false

    init(pollInterval: Duration = .seconds(45), staleInterval: TimeInterval = 60) {
        self.pollInterval = pollInterval
        self.staleInterval = staleInterval
    }

    func stateStream() -> AsyncStream<QuotaState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentState)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        stopping = false
        publish(.loading)
        startNetworkMonitoring()
        startMaintenanceTasks()
        await connect()
    }

    func refresh() async {
        guard started, !stopping else { return }
        guard let process, process.isRunning else {
            await connect()
            return
        }
        guard quotaRequestIDs.isEmpty else { return }

        do {
            let id = allocateRequestID()
            quotaRequestIDs.insert(id)
            try send([
                "id": id,
                "method": "account/rateLimits/read",
                "params": NSNull()
            ])
        } catch {
            quotaRequestIDs.removeAll()
            publishFailure("无法向 Codex 请求额度：\(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    func stop() async {
        guard started else { return }
        stopping = true
        started = false

        pollTask?.cancel()
        staleTask?.cancel()
        reconnectTask?.cancel()
        readTask?.cancel()
        pollTask = nil
        staleTask = nil
        reconnectTask = nil
        readTask = nil

        networkMonitor?.cancel()
        networkMonitor = nil

        try? inputHandle?.close()
        inputHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        self.process = nil
        quotaRequestIDs.removeAll()

        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    private func connect() async {
        guard started, !stopping, !connecting else { return }
        if let process, process.isRunning { return }
        connecting = true
        defer { connecting = false }

        guard let executable = await MainActor.run(body: CodexLocator.locateExecutable) else {
            publish(.clientMissing)
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = debugEnabled ? FileHandle.standardError : errorOutput

        process.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            Task { await self?.processDidExit(status: status) }
        }

        do {
            try process.run()
            debugLog("started \(executable.path)")
            self.process = process
            inputHandle = input.fileHandleForWriting
            beginReading(output: output)
            try sendInitialization()
            await refresh()
        } catch {
            self.process = nil
            inputHandle = nil
            publishFailure("无法启动 Codex App Server：\(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    private func beginReading(output: Pipe) {
        readTask?.cancel()
        readTask = Task.detached(priority: .utility) { [weak self] in
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    await self?.handle(line: line)
                }
            } catch {
                await self?.readerFailed(error)
            }
        }
    }

    private func sendInitialization() throws {
        let initializeID = allocateRequestID()
        try send([
            "id": initializeID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "quotaglass",
                    "title": "QuotaGlass",
                    "version": "0.1.0"
                ],
                "capabilities": ["experimentalApi": true]
            ]
        ])
        try send(["method": "initialized", "params": NSNull()])
    }

    private func send(_ object: [String: Any]) throws {
        guard let inputHandle else {
            throw ProviderError.disconnected
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func handle(line: String) {
        let message = AppServerMessageDecoder.decode(line: line)
        debugLog("received \(debugSummary(for: message))")
        switch message {
        case .rateLimitResponse(let id, let result):
            guard quotaRequestIDs.remove(id) != nil else { return }
            guard let snapshot = QuotaMapper.snapshot(from: result) else {
                publish(.unsupportedVersion("Codex 未返回可识别的额度窗口"))
                return
            }
            reconnectAttempt = 0
            lastSnapshot = snapshot
            publish(.available(snapshot))

        case .errorResponse(let id, let error):
            if let id { quotaRequestIDs.remove(id) }
            classifyAndPublish(error)

        case .notification(let method):
            if method == "account/rateLimits/updated" {
                quotaRequestIDs.removeAll()
                Task { await refresh() }
            }

        case .malformedRateLimitResponse(let id, let reason):
            quotaRequestIDs.remove(id)
            publish(.unsupportedVersion("无法解析 Codex 额度响应：\(reason)"))

        case .otherResponse, .unknown:
            break
        }
    }

    private func classifyAndPublish(_ error: RPCErrorPayload) {
        let lowercase = error.message.lowercased()
        if error.code == 401 || lowercase.contains("login") || lowercase.contains("auth") || lowercase.contains("unauthorized") {
            publish(.loginRequired(error.message))
        } else if error.code == -32601 || lowercase.contains("method not found") || lowercase.contains("unsupported") {
            publish(.unsupportedVersion(error.message))
        } else {
            publishFailure(error.message)
        }
    }

    private func startMaintenanceTasks() {
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }

        staleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self?.checkStaleness()
            }
        }
    }

    private func checkStaleness(now: Date = Date()) {
        guard let snapshot = lastSnapshot, snapshot.isStale(at: now, threshold: staleInterval) else { return }
        if case .available = currentState {
            publish(.stale(snapshot))
        }
    }

    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { await self?.networkBecameAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "com.jianxun.quotaglass.network", qos: .utility))
        networkMonitor = monitor
    }

    private func networkBecameAvailable() async {
        reconnectAttempt = 0
        if process?.isRunning == true {
            await refresh()
        } else {
            await connect()
        }
    }

    private func processDidExit(status: Int32) {
        guard !stopping else { return }
        process = nil
        inputHandle = nil
        quotaRequestIDs.removeAll()
        publishFailure("Codex App Server 已退出（状态码 \(status)）")
        scheduleReconnect()
    }

    private func readerFailed(_ error: Error) {
        guard !stopping else { return }
        publishFailure("Codex 数据连接中断：\(error.localizedDescription)")
    }

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        FileHandle.standardError.write(Data("[QuotaGlass] \(message)\n".utf8))
    }

    private func debugSummary(for message: AppServerIncomingMessage) -> String {
        switch message {
        case .rateLimitResponse(let id, _): "rate-limit response id=\(id)"
        case .errorResponse(let id, let error): "error response id=\(id.map(String.init) ?? "none") code=\(error.code.map(String.init) ?? "none")"
        case .notification(let method): "notification \(method)"
        case .otherResponse(let id): "other response id=\(id)"
        case .malformedRateLimitResponse(let id, _): "malformed rate-limit response id=\(id)"
        case .unknown: "unknown message"
        }
    }

    private func publishFailure(_ message: String) {
        if let snapshot = lastSnapshot, snapshot.isStale(at: Date(), threshold: staleInterval) {
            publish(.stale(snapshot))
        } else if lastSnapshot == nil {
            publish(.unavailable(message))
        }
    }

    private func scheduleReconnect() {
        guard started, !stopping, reconnectTask == nil else { return }
        let delay = Duration.seconds(ReconnectBackoff.delay(forAttempt: reconnectAttempt))
        reconnectAttempt += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.clearReconnectTaskAndConnect()
        }
    }

    private func clearReconnectTaskAndConnect() async {
        reconnectTask = nil
        await connect()
    }

    private func allocateRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func publish(_ state: QuotaState) {
        currentState = state
        continuations.values.forEach { $0.yield(state) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

private enum ProviderError: LocalizedError {
    case disconnected

    var errorDescription: String? {
        "Codex App Server 尚未连接"
    }
}
