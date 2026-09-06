import Foundation

struct ShellReply: Decodable, Sendable {
    var ok: Bool
    var output: String?
    var error: String?
    var database: String?
}

actor ShellSession {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var buffer = Data()
    private var continuation: CheckedContinuation<ShellReply, Error>?
    private var timer: Task<Void, Never>?
    private var generation = 0
    private var connectedID: UUID?
    private let executable: URL
    private let timeout: Duration

    init(executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TableViewerShell"), timeout: Duration = .seconds(25)) {
        self.executable = executable; self.timeout = timeout
    }

    func execute(_ code: String, profile: ConnectionProfile, secret: String) async throws -> ShellReply {
        guard continuation == nil else { throw DatabaseFailure(String(localized: "Shell 正在运行。")) }
        if connectedID != profile.id || process?.isRunning != true {
            stop()
            try start()
            let reply = try await request(["type": "connect", "uri": secret, "database": profile.database])
            guard reply.ok else { stop(); throw DatabaseFailure(reply.error ?? String(localized: "Shell 连接失败。")) }
            connectedID = profile.id
        }
        return try await request(["type": "eval", "code": code])
    }

    func stop(message: String = String(localized: "Shell 已停止；已执行的写入不会自动撤销。")) {
        generation += 1
        timer?.cancel(); timer = nil
        output?.readabilityHandler = nil; errorOutput?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); try? errorOutput?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; errorOutput = nil; connectedID = nil; buffer.removeAll()
        let pending = continuation; continuation = nil
        pending?.resume(throwing: DatabaseFailure(message))
    }

    private func start() throws {
        let process = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable; process.arguments = ["--mongo-shell-worker", "--tableviewer-language", Bundle.main.preferredLocalizations.first ?? "en"]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        let current = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data, generation: current) }
        }
        // Driver diagnostic logs must not become terminal protocol or expose connection credentials.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] _ in Task { await self?.exited(generation: current) } }
        do { try process.run() } catch {
            stdout.fileHandleForReading.readabilityHandler = nil; stderr.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        self.process = process; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; errorOutput = stderr.fileHandleForReading
    }

    private func request(_ object: [String: Any]) async throws -> ShellReply {
        let data = Data((try jsonText(object) + "\n").utf8)
        return try await withCheckedThrowingContinuation { pending in
            continuation = pending
            timer = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout); try Task.checkCancellation() } catch { return }
                await self?.stop(message: String(localized: "Shell 运行超时，执行进程已结束。写入可能已完成，请刷新数据确认。"))
            }
            do { try input?.write(contentsOf: data) }
            catch { stop(message: error.localizedDescription) }
        }
    }

    private func receive(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }
        buffer.append(data)
        if buffer.count > 2_000_000 { stop(message: String(localized: "Shell 输出过大，执行已停止；请缩小查询范围。")); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let reply = try? JSONDecoder().decode(ShellReply.self, from: line), let pending = continuation else { continue }
            timer?.cancel(); timer = nil; continuation = nil
            pending.resume(returning: reply)
        }
    }
    private func exited(generation: Int) { if generation == self.generation { stop(message: String(localized: "Shell 执行进程已退出，下次运行将重新连接。")) } }
}
