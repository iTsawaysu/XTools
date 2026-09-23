import Foundation
import UniformTypeIdentifiers

public enum FileTypeEvidenceSpecificity: Equatable, Sendable {
    case specific
    case genericText
    case genericContainer
}

public struct FileTypeEvidence: Equatable, Sendable {
    public let typeIdentifier: String?
    public let mimeType: String
    public let specificity: FileTypeEvidenceSpecificity
}

public enum FileTypeEvidenceAgreement: Equatable, Sendable {
    case matching
    case compatible
    case conflicting
    case contentOnly
    case extensionOnly
    case indeterminate
    case unknown
}

public enum FileTypeContentStatus: Equatable, Sendable {
    case available
    case empty
    case unreadable
}

public struct FileTypeReport: Equatable, Sendable {
    public let fileName: String
    public let fileExtension: String
    public let extensionEvidence: FileTypeEvidence?
    public let contentEvidence: FileTypeEvidence?
    public let resolvedEvidence: FileTypeEvidence?
    public let evidenceAgreement: FileTypeEvidenceAgreement
    public let contentStatus: FileTypeContentStatus
    public let fileSize: String
    public let headerBytes: String

    public var extensionMIMEType: String {
        extensionEvidence?.mimeType ?? "(未知)"
    }

    public var contentMIMEType: String {
        if let contentEvidence {
            return contentEvidence.mimeType
        }

        switch contentStatus {
        case .available:
            return "(未知)"
        case .empty:
            return "(空文件)"
        case .unreadable:
            return "(无法读取)"
        }
    }

    public var resolvedMIMEType: String {
        resolvedEvidence?.mimeType ?? "(未知)"
    }

    public var conflictDiagnostic: String? {
        guard evidenceAgreement == .conflicting,
              extensionEvidence != nil,
              contentEvidence != nil,
              let resolvedEvidence else {
            return nil
        }

        return "扩展名与内容不一致，最终按内容判定为 \(resolvedEvidence.mimeType)。"
    }
}

public enum FileTypeDetector {
    public static let leadingByteLimit = 64

    public enum InspectionIssue: LocalizedError, Equatable {
        case notRegularFile
        case metadataReadFailed
        case contentReadFailed

        public var errorDescription: String? {
            switch self {
            case .notRegularFile:
                return "所选项目不是普通文件。"
            case .metadataReadFailed:
                return "无法读取文件的基本信息。"
            case .contentReadFailed:
                return "无法读取文件开头内容，内容签名和文件头可能不完整。"
            }
        }
    }

    public static func diagnosticMessage(for error: Error, defaultIssue: InspectionIssue) -> String {
        if let issue = error as? InspectionIssue,
           let message = issue.errorDescription {
            return message
        }
        return defaultIssue.errorDescription ?? "文件探测失败。"
    }

    public static func inspect(fileName: String, byteCount: Int64?, leadingData: Data?) -> FileTypeReport {
        let rawExtension = (fileName as NSString).pathExtension
        let fileExtension = rawExtension.isEmpty ? "(无)" : rawExtension
        let extensionEvidence = extensionEvidence(for: fileExtension)
        let contentEvidence = leadingData.flatMap(detectedFileEvidence)
        let resolution = resolve(extensionEvidence: extensionEvidence, contentEvidence: contentEvidence)

        return FileTypeReport(
            fileName: fileName,
            fileExtension: fileExtension,
            extensionEvidence: extensionEvidence,
            contentEvidence: contentEvidence,
            resolvedEvidence: resolution.evidence,
            evidenceAgreement: resolution.agreement,
            contentStatus: contentStatus(for: leadingData),
            fileSize: fileSizeText(byteCount: byteCount),
            headerBytes: headerBytesHex(from: leadingData)
        )
    }

    static func fileSizeText(byteCount: Int64?) -> String {
        guard let byteCount else { return "(未知)" }
        return ByteSizeFormatter.format(bytes: byteCount)
    }

    static func headerBytesHex(from data: Data?) -> String {
        guard let data else { return "(无法读取)" }
        let bytes = data.prefix(16)
        if bytes.isEmpty { return "(空文件)" }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private struct EvidenceResolution {
        let evidence: FileTypeEvidence?
        let agreement: FileTypeEvidenceAgreement
    }

    private static func extensionEvidence(for fileExtension: String) -> FileTypeEvidence? {
        guard fileExtension != "(无)",
              let type = UTType(filenameExtension: fileExtension.lowercased()),
              let mimeType = type.preferredMIMEType else {
            return nil
        }

        return FileTypeEvidence(
            typeIdentifier: type.identifier,
            mimeType: mimeType,
            specificity: .specific
        )
    }

    private static func contentStatus(for data: Data?) -> FileTypeContentStatus {
        guard let data else { return .unreadable }
        return data.isEmpty ? .empty : .available
    }

    private static func resolve(
        extensionEvidence: FileTypeEvidence?,
        contentEvidence: FileTypeEvidence?
    ) -> EvidenceResolution {
        switch (extensionEvidence, contentEvidence) {
        case (nil, nil):
            return EvidenceResolution(evidence: nil, agreement: .unknown)
        case (nil, let contentEvidence?):
            return EvidenceResolution(evidence: contentEvidence, agreement: .contentOnly)
        case (let extensionEvidence?, nil):
            return EvidenceResolution(evidence: extensionEvidence, agreement: .extensionOnly)
        case (let extensionEvidence?, let contentEvidence?):
            if evidenceMatches(extensionEvidence, contentEvidence) {
                return EvidenceResolution(
                    evidence: preferredEvidence(extensionEvidence: extensionEvidence, contentEvidence: contentEvidence),
                    agreement: .matching
                )
            }

            if evidenceIsCompatible(extensionEvidence, contentEvidence) {
                return EvidenceResolution(
                    evidence: preferredEvidence(extensionEvidence: extensionEvidence, contentEvidence: contentEvidence),
                    agreement: .compatible
                )
            }

            if contentEvidence.specificity == .specific {
                return EvidenceResolution(evidence: contentEvidence, agreement: .conflicting)
            }

            return EvidenceResolution(evidence: extensionEvidence, agreement: .indeterminate)
        }
    }

    private static func preferredEvidence(
        extensionEvidence: FileTypeEvidence,
        contentEvidence: FileTypeEvidence
    ) -> FileTypeEvidence {
        switch contentEvidence.specificity {
        case .specific:
            return contentEvidence
        case .genericText, .genericContainer:
            return extensionEvidence
        }
    }

    private static func evidenceMatches(_ lhs: FileTypeEvidence, _ rhs: FileTypeEvidence) -> Bool {
        if let lhsIdentifier = lhs.typeIdentifier,
           let rhsIdentifier = rhs.typeIdentifier,
           lhsIdentifier == rhsIdentifier {
            return true
        }
        return lhs.mimeType.caseInsensitiveCompare(rhs.mimeType) == .orderedSame
    }

    private static func evidenceIsCompatible(_ lhs: FileTypeEvidence, _ rhs: FileTypeEvidence) -> Bool {
        guard let lhsType = uniformType(for: lhs),
              let rhsType = uniformType(for: rhs) else {
            return false
        }

        if lhsType.conforms(to: rhsType) || rhsType.conforms(to: lhsType) {
            return true
        }

        if lhsType.conforms(to: .text) && rhsType.conforms(to: .text) {
            return true
        }

        if rhs.specificity == .genericContainer,
           (lhsType.conforms(to: .archive) || lhsType.conforms(to: .zip)) {
            return true
        }

        return false
    }

    private static func uniformType(for evidence: FileTypeEvidence) -> UTType? {
        if let typeIdentifier = evidence.typeIdentifier,
           let type = UTType(typeIdentifier) {
            return type
        }
        return UTType(mimeType: evidence.mimeType)
    }

    private static func evidence(mimeType: String, specificity: FileTypeEvidenceSpecificity) -> FileTypeEvidence {
        let type = UTType(mimeType: mimeType)
        return FileTypeEvidence(
            typeIdentifier: type?.identifier,
            mimeType: mimeType,
            specificity: specificity
        )
    }

    private static func detectedFileEvidence(from data: Data) -> FileTypeEvidence? {
        if data.isEmpty {
            return nil
        }

        if let match = BinarySignatures.match(in: data) {
            let specificity: FileTypeEvidenceSpecificity
            switch match {
            case .zip:
                specificity = .genericContainer
            case .png, .jpeg, .gif, .pdf, .gzip:
                specificity = .specific
            }
            return evidence(
                mimeType: BinarySignatures.mimeType(for: match),
                specificity: specificity
            )
        }

        if looksLikeUTF8Text(data) {
            let isJSON = looksLikeJSON(data)
            return evidence(
                mimeType: isJSON ? "application/json" : "text/plain",
                specificity: isJSON ? .specific : .genericText
            )
        }

        return nil
    }

    private static func looksLikeUTF8Text(_ data: Data) -> Bool {
        guard String(data: data, encoding: .utf8) != nil else {
            return false
        }

        return data.allSatisfy { byte in
            byte == 0x09
                || byte == 0x0A
                || byte == 0x0D
                || byte >= 0x20
        }
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }
}
