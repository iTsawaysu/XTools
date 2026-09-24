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
