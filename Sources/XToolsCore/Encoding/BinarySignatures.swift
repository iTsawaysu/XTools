import Foundation

/// Shared magic-byte / content-signature table for binary sniffing.
/// Used by Base64 file typing and FileTypeDetector so rules cannot drift.
enum BinarySignatures {
    enum Match: Equatable, Sendable {
        case png
        case jpeg
        case gif
        case pdf
        case zip
        case gzip
    }

    static func match(in data: Data) -> Match? {
        if data.isEmpty {
            return nil
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }

        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }

        if data.starts(with: Array("GIF87a".utf8)) || data.starts(with: Array("GIF89a".utf8)) {
            return .gif
        }

        // Accept "%PDF" with or without the version hyphen so Base64 and
        // FileTypeDetector stay aligned on truncated or nonstandard headers.
        if data.starts(with: Array("%PDF".utf8)) {
            return .pdf
        }

        if data.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
            || data.starts(with: [0x50, 0x4B, 0x07, 0x08]) {
            return .zip
        }

        if data.starts(with: [0x1F, 0x8B]) {
            return .gzip
        }

        return nil
    }

    static func mimeType(for match: Match) -> String {
        switch match {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .gif: return "image/gif"
        case .pdf: return "application/pdf"
        case .zip: return "application/zip"
        case .gzip: return "application/gzip"
        }
    }

    static func fileExtension(for match: Match) -> String {
        switch match {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .pdf: return "pdf"
        case .zip: return "zip"
        case .gzip: return "gz"
        }
    }
}
