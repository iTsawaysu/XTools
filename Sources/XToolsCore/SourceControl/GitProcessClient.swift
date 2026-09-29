import Foundation

/// 执行器固定允许的 Git 命令白名单（不经过 shell）。扫描期每仓只发
/// statusV2/remote/branches/defaultBranch 四条；更新期再加 repositoryRoot
/// 与 pullFastForward。历史上逐条查询 branch/revision/upstream/divergence
/// 的形态已由单次 porcelain v2 合并，白名单随之一并收缩。
public enum GitCommandKind: Sendable, Equatable, Hashable {
    case repositoryRoot
    case remote
    case branches
    case defaultBranch
    case statusV2
    case pullFastForward
}

public struct GitCommandRequest: Sendable, Equatable {
    public let kind: GitCommandKind
    public let repositoryPath: String
    public let argument: String?

    public init(kind: GitCommandKind, repositoryPath: String, argument: String? = nil) {
        self.kind = kind
        self.repositoryPath = repositoryPath
        self.argument = argument
    }
}

public struct GitProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol GitProcessClient: Sendable {
    func run(_ request: GitCommandRequest, timeout: Duration) async throws -> GitProcessOutput
}

/// Executes a fixed allow-list of Git commands without invoking a shell.
///
/// The transport never blocks a Swift cooperative thread: pipes are drained
/// from readability handlers, process exit is awaited through the termination
/// handler, and both the timeout and the post-exit pipe drain are bounded.
/// Live child processes are capped so a large workspace scan cannot flood the
/// machine with concurrent Git launches.
public struct SystemGitProcessClient: GitProcessClient, Sendable {
    public let executableURL: URL
    public let maximumOutputBytes: Int
    private let inFlight: ProcessGate

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        maximumOutputBytes: Int = 1_048_576,
        maximumConcurrentProcesses: Int = 12
    ) {
        self.executableURL = executableURL
        self.maximumOutputBytes = max(4_096, maximumOutputBytes)
        self.inFlight = ProcessGate(permits: maximumConcurrentProcesses)
    }

    public func run(_ request: GitCommandRequest, timeout: Duration) async throws -> GitProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SourceControlError.gitUnavailable
        }
        try Task.checkCancellation()
        await inFlight.acquire()
        defer { inFlight.release() }
        try Task.checkCancellation()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = makeProcess(for: request, outputPipe: outputPipe, errorPipe: errorPipe)
        let runner = ProcessRunner(
            process: process,
            stdoutHandle: outputPipe.fileHandleForReading,
            stderrHandle: errorPipe.fileHandleForReading,
            maximumOutputBytes: maximumOutputBytes
        )
        try runner.launch()
        return try await withTaskCancellationHandler {
            let output = try await runner.collect(timeout: timeout)
            if Task.isCancelled { throw SourceControlError.cancelled }
            return output
        } onCancel: {
            runner.terminate()
        }
    }

    private func makeProcess(for request: GitCommandRequest, outputPipe: Pipe, errorPipe: Pipe) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = request.arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -oBatchMode=yes"
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment.removeValue(forKey: "GIT_DIR")
        environment.removeValue(forKey: "GIT_WORK_TREE")
        process.environment = environment
        return process
    }
}

private extension GitCommandRequest {
    var arguments: [String] {
        let path = repositoryPath
        let common = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "pull.rebase=false", "-c", "rebase.autoStash=false", "-C", path]
        switch kind {
        case .repositoryRoot: return common + ["rev-parse", "--show-toplevel"]
        case .remote: return common + ["remote", "-v"]
        case .branches: return common + ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"]
        case .defaultBranch: return common + ["symbolic-ref", "--short", "refs/remotes/\(argument ?? "origin")/HEAD"]
        case .statusV2: return common + ["status", "--porcelain=v2", "--branch", "--untracked-files=normal"]
        case .pullFastForward: return common + ["pull", "--ff-only"]
        }
    }
}

/// Bounds how many Git child processes may run at once. Waiting callers only
/// hold a suspended continuation, never a thread.
private final class ProcessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) { self.permits = max(1, permits) }

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if permits > 0 {
                permits -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        if let waiter = waiters.first {
            waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            permits += 1
            lock.unlock()
        }
    }
}

/// Runs one Git child process and collects its output without ever blocking
/// the calling thread. Exactly one of `.cancelled`, `.timedOut`, or a result
/// is produced per run, and every wait has a deadline.
private final class ProcessRunner: @unchecked Sendable {
    private static let drainGrace: Duration = .milliseconds(500)
    private static let killEscalation: Duration = .seconds(2)

    private let process: Process
    private let stdout: PipeCollector
    private let stderr: PipeCollector
    private let lock = NSLock()
    private var terminated = false
    private var timedOut = false
    private var exitStatusCode: Int32?
    private var exitWaiter: CheckedContinuation<Int32, Never>?

    init(process: Process, stdoutHandle: FileHandle, stderrHandle: FileHandle, maximumOutputBytes: Int) {
        self.process = process
        self.stdout = PipeCollector(handle: stdoutHandle, maximumBytes: maximumOutputBytes)
        self.stderr = PipeCollector(handle: stderrHandle, maximumBytes: maximumOutputBytes)
    }

    func launch() throws {
        process.terminationHandler = { [weak self] process in
            self?.markExit(process.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            throw SourceControlError.gitUnavailable
        }
        stdout.start()
        stderr.start()
    }

    /// Terminates the child. Safe to call from the timeout timer, the
    /// cancellation handler, or both at once.
    func terminate() {
        lock.lock()
        guard !terminated else { lock.unlock(); return }
        terminated = true
        lock.unlock()
        process.terminate()
        Task { [weak self] in
            try? await Task.sleep(for: Self.killEscalation)
            guard let self, !self.hasExited else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
    }

    func collect(timeout: Duration) async throws -> GitProcessOutput {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.terminate()
            self?.markTimedOut()
        }
        defer { timer.cancel() }

        var stdoutText = ""
        var stderrText = ""
        var exitCode: Int32 = -1
        await withTaskGroup(of: CollectEvent.self) { group in
            group.addTask { await .stdoutDone(self.stdout.finish()) }
            group.addTask { await .stderrDone(self.stderr.finish()) }
            group.addTask { await .exited(self.exitCode()) }

            var gotStdout = false
            var gotStderr = false
            var gotExit = false
            var grace: Task<Void, Never>?
            defer { grace?.cancel() }
            while let event = await group.next() {
                switch event {
                case .stdoutDone(let text):
                    stdoutText = text
                    gotStdout = true
                case .stderrDone(let text):
                    stderrText = text
                    gotStderr = true
                case .exited(let code):
                    exitCode = code
                    gotExit = true
                    // A grandchild (for example an orphaned ssh from ls-remote)
                    // can keep the pipe write end open after Git exits, so the
                    // drain gets one bounded grace window instead of waiting
                    // for an EOF that may never come.
                    grace = Task { [weak self] in
                        try? await Task.sleep(for: Self.drainGrace)
                        self?.stdout.abandon()
                        self?.stderr.abandon()
                    }
                }
                if gotStdout, gotStderr, gotExit { break }
            }
            group.cancelAll()
        }
        stdout.releaseHandle()
        stderr.releaseHandle()

        if timedOutFlag() { throw SourceControlError.timedOut }
        return GitProcessOutput(exitCode: exitCode, standardOutput: stdoutText, standardError: stderrText)
    }

    private func timedOutFlag() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return timedOut
    }

    private var hasExited: Bool {
        lock.lock(); defer { lock.unlock() }
        return exitStatusCode != nil
    }

    private func markExit(_ code: Int32) {
        lock.lock()
        exitStatusCode = code
        let waiter = exitWaiter
        exitWaiter = nil
        lock.unlock()
        waiter?.resume(returning: code)
    }

    private func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    private func exitCode() async -> Int32 {
        await withCheckedContinuation { continuation in
            registerExitWaiter(continuation)
        }
    }

    private func registerExitWaiter(_ continuation: CheckedContinuation<Int32, Never>) {
        lock.lock()
        if let code = exitStatusCode {
            lock.unlock()
            continuation.resume(returning: code)
            return
        }
        exitWaiter = continuation
        lock.unlock()
    }
}

private enum CollectEvent: Sendable {
    case stdoutDone(String)
    case stderrDone(String)
    case exited(Int32)
}

/// Collects one pipe through readability callbacks. Nothing here occupies a
/// thread: the collector either reaches EOF or is abandoned once the process
/// is gone, and the waiter always resumes exactly once.
private final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let maximumBytes: Int
    private var buffer = Data()
    private var reachedEnd = false
    private var abandoned = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(handle: FileHandle, maximumBytes: Int) {
        self.handle = handle
        self.maximumBytes = maximumBytes
    }

    func start() {
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.consume(chunk)
        }
    }

    private func consume(_ chunk: Data) {
        lock.lock()
        if reachedEnd || abandoned {
            handle.readabilityHandler = nil
            lock.unlock()
            return
        }
        if chunk.isEmpty {
            reachedEnd = true
            handle.readabilityHandler = nil
        } else if buffer.count < maximumBytes {
            buffer.append(chunk.prefix(maximumBytes - buffer.count))
        }
        let waiter = reachedEnd ? self.waiter : nil
        if reachedEnd { self.waiter = nil }
        lock.unlock()
        waiter?.resume()
    }

    /// Waits for EOF and returns everything collected up to that point.
    func finish() async -> String {
        await withCheckedContinuation { continuation in
            registerFinishWaiter(continuation)
        }
        return collectedText()
    }

    private func registerFinishWaiter(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if reachedEnd {
            lock.unlock()
            continuation.resume()
            return
        }
        waiter = continuation
        lock.unlock()
    }

    private func collectedText() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    /// Stops collecting and resumes the waiter with the bytes gathered so far.
    func abandon() {
        lock.lock()
        guard !reachedEnd else { lock.unlock(); return }
        abandoned = true
        handle.readabilityHandler = nil
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    /// Closes the descriptor. In the abandoned case the close is delayed so an
    /// in-flight readability callback can never touch a closed handle.
    func releaseHandle() {
        if hasReachedEnd() {
            try? handle.close()
        } else {
            Task { [self] in
                try? await Task.sleep(for: .seconds(1))
                closeHandle()
            }
        }
    }

    private func hasReachedEnd() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reachedEnd
    }

    private func closeHandle() {
        try? handle.close()
    }
}
