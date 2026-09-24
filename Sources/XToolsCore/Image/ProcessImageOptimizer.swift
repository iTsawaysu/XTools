import Darwin
import Foundation

/// Runs bundled `pngquant` (lossy) and `oxipng` (lossless) as child processes to
/// shrink PNG output beyond what ImageIO produces. Non-PNG formats and any
/// failure path return `nil` so `ImageProcessor` keeps its ImageIO bytes.
///
/// License note: `pngquant`/`libimagequant` are GPL-3. Shipping this optimizer
/// requires the app itself to be distributed under a GPL-3-compatible license.
/// `oxipng` is MIT. See the task research doc for the full analysis.
public struct ProcessImageOptimizer: ExternalImageOptimizing {
    private let locator: any ImageOptimizerToolLocating
    private let runProcess: @Sendable (String, [String], Data) -> Data?

    public init(
        locator: any ImageOptimizerToolLocating,
        runProcess: (@Sendable (String, [String], Data) -> Data?)? = nil
    ) {
        self.locator = locator
        self.runProcess = runProcess ?? { path, args, input in
            ProcessImageOptimizer.defaultRunProcess(path, args, input, timeout: 30)
        }
    }

    public func optimize(_ data: Data, format: ImageFileFormat, lossy: Bool) -> Data? {
        guard format == .png else { return nil }

        if lossy, let pngquant = locator.pngquantPath {
            // `--` ends options; read stdin, write stdout, keep going even if the
            // gain is small (we compare sizes ourselves below).
            if let optimized = runProcess(pngquant, ["--quality=65-90", "--strip", "--", "-"], data),
               !optimized.isEmpty,
               optimized.count < data.count {
                return optimized
            }
        }

        if let oxipng = locator.oxipngPath {
            if let optimized = runProcess(oxipng, ["--stdout", "--quiet", "-o", "2", "-"], data),
               !optimized.isEmpty,
               optimized.count < data.count {
                return optimized
            }
        }

        return nil
    }

    static func defaultRunProcess(
        _ path: String,
        _ args: [String],
        _ input: Data,
        timeout: TimeInterval
    ) -> Data? {
        guard !input.isEmpty, !Task<Never, Never>.isCancelled else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()

        defer {
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGTERM)
                let grace = DispatchTime.now() + .milliseconds(200)
                while process.isRunning && DispatchTime.now() < grace {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            try? stdinPipe.fileHandleForWriting.close()
            try? stdoutPipe.fileHandleForReading.close()
        }

        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading
        let writeFD = writer.fileDescriptor
        let readFD = reader.fileDescriptor
        let writeFlags = fcntl(writeFD, F_GETFL)
        let readFlags = fcntl(readFD, F_GETFL)
        guard writeFlags >= 0, readFlags >= 0,
              fcntl(writeFD, F_SETNOSIGPIPE, 1) >= 0,
              fcntl(writeFD, F_SETFL, writeFlags | O_NONBLOCK) >= 0,
              fcntl(readFD, F_SETFL, readFlags | O_NONBLOCK) >= 0 else { return nil }

        let deadline = DispatchTime.now() + timeout
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var written = 0
        var stdinOpen = true
        var reachedEOF = false
        while true {
            if Task<Never, Never>.isCancelled || DispatchTime.now() >= deadline {
                return nil
            }
            if reachedEOF && !process.isRunning { break }

            var descriptors = [
                pollfd(fd: reachedEOF ? -1 : readFD, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0),
                pollfd(fd: stdinOpen ? writeFD : -1, events: Int16(POLLOUT | POLLHUP | POLLERR), revents: 0)
            ]
            let ready = descriptors.withUnsafeMutableBufferPointer {
                Darwin.poll($0.baseAddress, nfds_t($0.count), 50)
            }
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { continue }

            if descriptors[0].revents != 0 {
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(readFD, $0.baseAddress, min($0.count, input.count - output.count))
                }
                if count < 0 {
                    if errno != EAGAIN && errno != EINTR { return nil }
                } else if count == 0 {
                    reachedEOF = true
                } else {
                    output.append(contentsOf: buffer.prefix(count))
                    if output.count >= input.count { return nil }
                }
            }

            if stdinOpen && descriptors[1].revents != 0 {
                let count = input.withUnsafeBytes { bytes in
                    Darwin.write(writeFD, bytes.baseAddress!.advanced(by: written), min(65_536, input.count - written))
                }
                if count < 0 {
                    if errno != EAGAIN && errno != EINTR { return nil }
                } else if count == 0 {
                    return nil
                } else {
                    written += count
                    if written == input.count {
                        try? writer.close()
                        stdinOpen = false
                    }
                }
            }
        }

        guard written == input.count, process.terminationStatus == 0 else { return nil }
        return output
    }
}
