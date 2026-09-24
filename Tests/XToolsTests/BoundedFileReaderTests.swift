import Foundation
@testable import XTools
import Testing

struct BoundedFileReaderTests {
    @Test func readsExactlyTheBudgetAndRejectsTheNextByte() throws {
        let url = try sourcePackageRoot()
            .appendingPathComponent("Tests/XToolsTests/BoundedFileReaderTests.swift")
        let expected = try Data(contentsOf: url)
        #expect(!expected.isEmpty)

        #expect(try BoundedFileReader.read(from: url, maxBytes: expected.count) == expected)
        #expect(try BoundedFileReader.read(from: url, maxBytes: Int.max) == expected)
        expectTooLarge(url, maxBytes: expected.count - 1)
        expectTooLarge(url, maxBytes: 0)
        expectTooLarge(url, maxBytes: -1)
    }

    @Test func cancelledReadStopsBeforeOpeningTheFile() async throws {
        let missingURL = URL(fileURLWithPath: "/nonexistent/bounded-reader-cancelled")
        let read = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try BoundedFileReader.read(from: missingURL, maxBytes: 8)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        #expect(await read.value)
    }

    @Test func droppedEditorFilesUseBoundedReaderAndPreserveTextEncodings() throws {
        let url = try sourcePackageRoot()
            .appendingPathComponent("Tests/XToolsTests/Fixtures/test.md")
        let data = try BoundedFileReader.read(from: url, maxBytes: 15_000_000)
        #expect(IndexCaretTextView.readDroppedContent(from: url) == String(data: data, encoding: .utf8))
        #expect(IndexCaretTextView.readDroppedContent(from: url.deletingLastPathComponent()) == nil)
        #expect(IndexCaretTextView.readDroppedContent(from: URL(fileURLWithPath: "/dev/null")) == nil)
        #expect(IndexCaretTextView.decodeDroppedContent("测试".data(using: .utf16)!) == "测试")
    }

    @Test func droppedEditorFilesReadRegularFileSymlinks() throws {
        let fixture = try sourcePackageRoot()
            .appendingPathComponent("Tests/XToolsTests/Fixtures/test.md")
        let temporaryLink = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xtools-dropped-link-\(UUID().uuidString)")
        let retainedDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/tmp", isDirectory: true)
        let retainedLink = retainedDirectory.appendingPathComponent(temporaryLink.lastPathComponent)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: temporaryLink, withDestinationURL: fixture)
        defer { try? FileManager.default.moveItem(at: temporaryLink, to: retainedLink) }

        let expected = try String(contentsOf: fixture, encoding: .utf8)
        #expect(IndexCaretTextView.readDroppedContent(from: temporaryLink) == expected)
        #expect(IndexCaretTextView.readDroppedContent(from: URL(fileURLWithPath: "/dev/null")) == nil)
    }

    @Test func base64ImportPathsPreserveTheirSizeFailures() async throws {
        let url = try sourcePackageRoot()
            .appendingPathComponent("Tests/XToolsTests/BoundedFileReaderTests.swift")
        let expected = try Data(contentsOf: url)
        let limit = expected.count

        let selected = await Base64FileWorkflow.readSelection(from: url, maxBytes: limit)
        guard case .success(let selection) = selected else {
            Issue.record("Expected selected file at the exact byte limit")
            return
        }
        #expect(selection.data == expected)
        #expect(
            await Base64FileWorkflow.readSelection(from: url, maxBytes: limit - 1)
                == .failure(.tooLarge(fileName: url.lastPathComponent, maxBytes: limit - 1))
        )

        let encodedText = await Base64FileWorkflow.readEncodedText(from: url, maxBytes: limit)
        guard case .success(let input) = encodedText else {
            Issue.record("Expected UTF-8 text at the exact byte limit")
            return
        }
        #expect(input.text == String(data: expected, encoding: .utf8))
        #expect(
            await Base64FileWorkflow.readEncodedText(from: url, maxBytes: limit - 1)
                == .failure(.externalEncodedTextTooLarge(maxBytes: limit - 1))
        )
    }

    private func expectTooLarge(_ url: URL, maxBytes: Int) {
        do {
            _ = try BoundedFileReader.read(from: url, maxBytes: maxBytes)
            Issue.record("Expected a read-budget failure for \(maxBytes) bytes")
        } catch BoundedFileReader.ReadError.tooLarge {
        } catch {
            Issue.record("Expected a read-budget failure, got \(error)")
        }
    }
}
