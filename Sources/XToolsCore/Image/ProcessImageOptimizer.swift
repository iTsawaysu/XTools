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
        self.runProcess = runProcess ?? ProcessImageOptimizer.defaultRunProcess
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

    private static let defaultRunProcess: @Sendable (String, [String], Data) -> Data? = { path, args, input in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Write stdin on a background queue while we drain stdout, so large
        // images cannot deadlock on full pipe buffers.
        let writer = DispatchQueue(label: "image-optimizer-stdin")
        writer.async {
            stdinPipe.fileHandleForWriting.write(input)
            try? stdinPipe.fileHandleForWriting.close()
        }

        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return output
    }
}
