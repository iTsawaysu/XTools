import Foundation

public enum ImageOutputWorkflow: Equatable, Sendable {
    case compression
    case conversion
    case watermark
    case grayscale
}

public enum ImageOutputSeverity: Equatable, Sendable {
    case success
    case warning
    case blocked
}

public enum ImageOutputBlockReason: Equatable, Sendable {
    case compressionNotSmallerThanOriginal
}

public struct ImageOutputAssessment: Equatable, Sendable {
    public let workflow: ImageOutputWorkflow
    public let output: ProcessedImage
    public let canSave: Bool
    public let severity: ImageOutputSeverity
    public let requiresExplicitLargerSave: Bool
    public let blockReason: ImageOutputBlockReason?
    public let sizeDeltaPercent: Int
}

public enum ImageOutputPolicy {
    public static func assess(
        _ output: ProcessedImage,
        for workflow: ImageOutputWorkflow
    ) -> ImageOutputAssessment {
        let sizeDeltaPercent = Self.sizeDeltaPercent(for: output)

        switch workflow {
        case .compression:
            let canSave = output.isSmallerThanOriginal
            return ImageOutputAssessment(
                workflow: workflow,
                output: output,
                canSave: canSave,
                severity: canSave ? .success : .blocked,
                requiresExplicitLargerSave: false,
                blockReason: canSave ? nil : .compressionNotSmallerThanOriginal,
                sizeDeltaPercent: sizeDeltaPercent
            )
        case .conversion, .watermark, .grayscale:
            let isLarger = output.isLargerThanOriginal
            return ImageOutputAssessment(
                workflow: workflow,
                output: output,
                canSave: true,
                severity: isLarger ? .warning : .success,
                requiresExplicitLargerSave: isLarger,
                blockReason: nil,
                sizeDeltaPercent: sizeDeltaPercent
            )
        }
    }

    private static func sizeDeltaPercent(for output: ProcessedImage) -> Int {
        guard output.originalByteCount > 0 else { return 0 }
        let ratio = (Double(output.byteCount) / Double(output.originalByteCount) - 1.0) * 100
        return Int(ratio.rounded())
    }
}
