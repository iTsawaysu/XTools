import Foundation

public protocol ExternalImageOptimizing: Sendable {
    func optimize(_ data: Data, format: ImageFileFormat, lossy: Bool) -> Data?
}

public struct NoExternalImageOptimizer: ExternalImageOptimizing {
    public init() {}

    public func optimize(_ data: Data, format: ImageFileFormat, lossy: Bool) -> Data? {
        nil
    }
}

public protocol ImageOptimizerToolLocating: Sendable {
    var pngquantPath: String? { get }
    var oxipngPath: String? { get }
}

public struct FileSystemImageOptimizerToolLocator: ImageOptimizerToolLocating {
    private let searchDirectories: [String]

    public init(searchDirectories: [String]) {
        self.searchDirectories = searchDirectories
    }

    public var pngquantPath: String? { resolve("pngquant") }
    public var oxipngPath: String? { resolve("oxipng") }

    private func resolve(_ name: String) -> String? {
        for directory in searchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
