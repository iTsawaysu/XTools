import Foundation
import UniformTypeIdentifiers
@testable import XToolsCore
@testable import XTools

@MainActor
final class FakeImageWorkflowDialog: @unchecked Sendable {
    var saveURL: URL?
    var directoryURL: URL?
    var requestedSaveNames: [String] = []
    private(set) var requestedDirectoryMessages: [(prompt: String, message: String?)] = []

    init(
        saveURL: URL? = nil,
        directoryURL: URL? = nil
    ) {
        self.saveURL = saveURL
        self.directoryURL = directoryURL
    }

    func selectSaveURL(defaultFilename: String, allowedContentTypes: [UTType]) async -> URL? {
        requestedSaveNames.append(defaultFilename)
        return saveURL
    }

    func selectDirectory(prompt: String, message: String?) async -> URL? {
        requestedDirectoryMessages.append((prompt, message))
        return directoryURL
    }

    var asDialog: ImageWorkflowDialog {
        ImageWorkflowDialog(
            selectSaveURL: { [self] filename, types in
                await self.selectSaveURL(defaultFilename: filename, allowedContentTypes: types)
            },
            selectDirectory: { [self] prompt, message in
                await self.selectDirectory(prompt: prompt, message: message)
            }
        )
    }
}

final class FakeImageWorkflowReader: @unchecked Sendable {
    var dataByURL: [URL: Data]
    var byteCountsByURL: [URL: Int]
    var nonRegularURLs: Set<URL>
    var readDelayByURL: [URL: TimeInterval]
    var error: Error?
    private let readURLsLock = NSLock()
    private var storedReadURLs: [URL] = []

    var readURLs: [URL] {
        readURLsLock.lock()
        defer { readURLsLock.unlock() }
        return storedReadURLs
    }

    init(
        dataByURL: [URL: Data] = [:],
        byteCountsByURL: [URL: Int] = [:],
        nonRegularURLs: Set<URL> = [],
        readDelayByURL: [URL: TimeInterval] = [:],
        error: Error? = nil
    ) {
        self.dataByURL = dataByURL
        self.byteCountsByURL = byteCountsByURL
        self.nonRegularURLs = nonRegularURLs
        self.readDelayByURL = readDelayByURL
        self.error = error
    }

    func isRegularFile(at url: URL) throws -> Bool {
        if let error { throw error }
        return !nonRegularURLs.contains(url)
    }

    func byteCount(for url: URL) throws -> Int? {
        if let error { throw error }
        return byteCountsByURL[url] ?? dataByURL[url]?.count
    }

    func readData(from url: URL) throws -> Data {
        if let error { throw error }
        readURLsLock.lock()
        storedReadURLs.append(url)
        readURLsLock.unlock()
        if let delay = readDelayByURL[url] {
            let start = Date()
            while Date().timeIntervalSince(start) < delay {
                if Task.isCancelled { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        return dataByURL[url] ?? Data()
    }

    var asReader: ImageWorkflowFileReader {
        ImageWorkflowFileReader(
            isRegularFile: { [self] url in
                try self.isRegularFile(at: url)
            },
            byteCount: { [self] url in
                try self.byteCount(for: url)
            },
            readDataWithLimit: { [self] url, _ in
                try self.readData(from: url)
            }
        )
    }
}

final class FakeImageWorkflowWriter: @unchecked Sendable {
    var error: Error?
    var failAfter: Int?
    private(set) var writes: [(data: Data, url: URL)] = []

    init(error: Error? = nil, failAfter: Int? = nil) {
        self.error = error
        self.failAfter = failAfter
    }

    func write(_ data: Data, to url: URL) throws {
        if let failAfter {
            if writes.count >= failAfter {
                throw error ?? CocoaError(.fileWriteUnknown)
            }
            writes.append((data, url))
            return
        }
        if let error {
            throw error
        }
        writes.append((data, url))
    }

    var asWriter: ImageWorkflowFileWriter {
        ImageWorkflowFileWriter(
            writeHandler: { [self] data, url in
                try self.write(data, to: url)
            }
        )
    }
}

extension ImageWorkflowClient {
    init(
        dialog: FakeImageWorkflowDialog,
        reader: FakeImageWorkflowReader,
        writer: FakeImageWorkflowWriter
    ) {
        self.init(
            dialog: dialog.asDialog,
            reader: reader.asReader,
            writer: writer.asWriter
        )
    }

    init(
        dialog: FakeImageWorkflowDialog,
        reader: FakeImageWorkflowReader,
        writer: ImageWorkflowFileWriter = ImageWorkflowFileWriter()
    ) {
        self.init(
            dialog: dialog.asDialog,
            reader: reader.asReader,
            writer: writer
        )
    }

    init(
        dialog: FakeImageWorkflowDialog,
        reader: ImageWorkflowFileReader = ImageWorkflowFileReader(),
        writer: FakeImageWorkflowWriter
    ) {
        self.init(
            dialog: dialog.asDialog,
            reader: reader,
            writer: writer.asWriter
        )
    }

    init(
        dialog: ImageWorkflowDialog = ImageWorkflowDialog(),
        reader: FakeImageWorkflowReader,
        writer: FakeImageWorkflowWriter
    ) {
        self.init(
            dialog: dialog,
            reader: reader.asReader,
            writer: writer.asWriter
        )
    }

    init(
        dialog: FakeImageWorkflowDialog,
        reader: ImageWorkflowFileReader = ImageWorkflowFileReader(),
        writer: ImageWorkflowFileWriter = ImageWorkflowFileWriter()
    ) {
        self.init(
            dialog: dialog.asDialog,
            reader: reader,
            writer: writer
        )
    }

    init(
        dialog: ImageWorkflowDialog = ImageWorkflowDialog(),
        reader: FakeImageWorkflowReader,
        writer: ImageWorkflowFileWriter = ImageWorkflowFileWriter()
    ) {
        self.init(
            dialog: dialog,
            reader: reader.asReader,
            writer: writer
        )
    }

    init(
        dialog: ImageWorkflowDialog = ImageWorkflowDialog(),
        reader: ImageWorkflowFileReader = ImageWorkflowFileReader(),
        writer: FakeImageWorkflowWriter
    ) {
        self.init(
            dialog: dialog,
            reader: reader,
            writer: writer.asWriter
        )
    }
}
