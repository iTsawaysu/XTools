import Foundation
import Testing
@testable import XToolsCore

struct URLFetchHostPolicyTests {
    @Test func allowsPublicHosts() {
        #expect(URLFetchHostPolicy.evaluate(host: "example.com") == .allow)
        #expect(URLFetchHostPolicy.evaluate(host: "cdn.example.org") == .allow)
        #expect(URLFetchHostPolicy.evaluate(host: "8.8.8.8") == .allow)
    }

    @Test func deniesLoopbackAndLocalhost() {
        #expect(URLFetchHostPolicy.evaluate(host: "localhost") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "Foo.Localhost") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "127.0.0.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "127.1.2.3") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "::1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "[::1]") == .deny)
    }

    @Test func deniesPrivateAndLinkLocalIPv4() {
        #expect(URLFetchHostPolicy.evaluate(host: "10.0.0.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "172.16.0.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "172.31.255.255") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "192.168.1.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "169.254.1.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "169.254.169.254") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "100.64.0.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "0.0.0.0") == .deny)
    }

    @Test func allowsNonPrivate172Range() {
        #expect(URLFetchHostPolicy.evaluate(host: "172.15.0.1") == .allow)
        #expect(URLFetchHostPolicy.evaluate(host: "172.32.0.1") == .allow)
    }

    @Test func deniesMetadataHostnames() {
        #expect(URLFetchHostPolicy.evaluate(host: "metadata.google.internal") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "metadata") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "instance-data") == .deny)
    }

    @Test func deniesIPv6LinkLocalAndULA() {
        #expect(URLFetchHostPolicy.evaluate(host: "fe80::1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "fd12:3456:789a::1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "fc00::1") == .deny)
    }

    @Test func deniesIPv4MappedLoopback() {
        #expect(URLFetchHostPolicy.evaluate(host: "::ffff:127.0.0.1") == .deny)
        #expect(URLFetchHostPolicy.evaluate(host: "::ffff:192.168.0.1") == .deny)
    }

    @Test func deniesAnyPrivateAddressReturnedForAHostname() {
        #expect(
            URLFetchHostPolicy.evaluateResolvedAddresses(["93.184.216.34", "192.168.1.20"])
                == .deny
        )
        #expect(
            URLFetchHostPolicy.evaluateResolvedAddresses(["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"])
                == .allow
        )
        #expect(URLFetchHostPolicy.evaluateResolvedAddresses([]) == .deny)
    }

    @Test func normalizedURLRejectsPrivateHostsWithStableDiagnostic() throws {
        #expect {
            _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: "http://127.0.0.1/admin")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.privateNetworkDisallowed = error else {
                return false
            }
            return true
        }

        #expect {
            _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: "http://192.168.0.10/")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.privateNetworkDisallowed = error else {
                return false
            }
            return true
        }

        #expect {
            _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: "http://169.254.169.254/latest/meta-data/")
        } throws: { error in
            guard case HTMLToMarkdownURLFetchError.privateNetworkDisallowed = error else {
                return false
            }
            return true
        }

        let message = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .privateNetworkDisallowed)
        #expect(message == "不允许访问本地或私有网络地址。")
        ToolDiagnosticContract.expectFactual(
            message,
            sensitiveInputs: ["127.0.0.1", "192.168.0.10", "/latest/meta-data/"]
        )
    }
}

struct BinarySignaturesTests {
    @Test func pdfMatchesWithOrWithoutVersionHyphen() {
        #expect(BinarySignatures.match(in: Data("%PDF".utf8)) == .pdf)
        #expect(BinarySignatures.match(in: Data("%PDF-1.7".utf8)) == .pdf)
        #expect(BinarySignatures.match(in: Data("%PDF-".utf8)) == .pdf)
    }

    @Test func base64AndFileTypeDetectorAgreeOnSharedSignatures() {
        let samples: [(Data, String)] = [
            (Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "image/png"),
            (Data([0xFF, 0xD8, 0xFF, 0xE0]), "image/jpeg"),
            (Data("GIF89a".utf8), "image/gif"),
            (Data("%PDF".utf8), "application/pdf"),
            (Data("%PDF-1.4".utf8), "application/pdf"),
        ]

        for (bytes, mime) in samples {
            #expect(Base64Conversion.inferredFileType(for: bytes)?.mimeType == mime)
            let report = FileTypeDetector.inspect(
                fileName: "sample.bin",
                byteCount: Int64(bytes.count),
                leadingData: bytes
            )
            #expect(report.contentMIMEType == mime)
            #expect(report.resolvedMIMEType == mime)
        }
    }

    @Test func fileTypeDetectorStillSeesZipAndGzipBase64DoesNot() {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x00])
        let gzip = Data([0x1F, 0x8B, 0x08])
        #expect(Base64Conversion.inferredFileType(for: zip) == nil)
        #expect(Base64Conversion.inferredFileType(for: gzip) == nil)
        #expect(
            FileTypeDetector.inspect(fileName: "a.zip", byteCount: Int64(zip.count), leadingData: zip)
                .contentMIMEType == "application/zip"
        )
        #expect(
            FileTypeDetector.inspect(fileName: "a.gz", byteCount: Int64(gzip.count), leadingData: gzip)
                .contentMIMEType == "application/gzip"
        )
    }
}
