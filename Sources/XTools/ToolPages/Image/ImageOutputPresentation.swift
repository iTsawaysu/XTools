import XToolsCore
import SwiftUI

enum ImageOutputPresentation {
    static func sizeChangeText(_ assessment: ImageOutputAssessment) -> String {
        let percent = assessment.sizeDeltaPercent
        if percent < 0 {
            return "减少 \(abs(percent))%"
        }
        if percent > 0 {
            return "增大 \(percent)%"
        }
        return "无变化"
    }

    static func outputSummary(_ assessment: ImageOutputAssessment, includeQuality: Bool = true) -> String {
        var parts = [
            assessment.output.format.displayName,
            ByteSizeFormatter.format(bytes: assessment.output.byteCount),
            sizeChangeText(assessment)
        ]
        if includeQuality, let quality = assessment.output.quality {
            parts.append("实际质量 \(Int(quality * 100))%")
        }
        return parts.joined(separator: " · ")
    }

    static func processingOutputSummary(_ assessment: ImageOutputAssessment) -> String {
        outputSummary(assessment, includeQuality: false)
    }

    static func compressionStatus(_ assessment: ImageOutputAssessment) -> String {
        guard assessment.canSave else {
            return blockedCompressionMessage
        }

        let output = assessment.output
        let size = "\(output.pixelWidth)×\(output.pixelHeight)"
        let qualityText = output.quality.map { "，实际质量 \(Int($0 * 100))%" } ?? ""
        return "可保存，输出 \(output.format.displayName)，尺寸 \(size)\(qualityText)"
    }

    static var blockedCompressionMessage: String {
        "未生成更小文件"
    }

    static func color(for assessment: ImageOutputAssessment) -> Color {
        switch assessment.severity {
        case .success:
            return ToolTheme.success
        case .warning, .blocked:
            return ToolTheme.warning
        }
    }
}
