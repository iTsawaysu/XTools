import AppKit

public enum ImageWatermarkSizing {
    public static let ratioRange: ClosedRange<Double> = 0.10...0.80
    public static let defaultRatio = 0.30

    private static let referenceFontSize: CGFloat = 1_000

    public static func clampedRatio(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return defaultRatio }
        return min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound)
    }

    public static func fontSize(
        text: String,
        sizeRatio: Double,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> Double {
        let width = max(pixelWidth, 1)
        let height = max(pixelHeight, 1)
        let ratio = clampedRatio(sizeRatio)
        guard !text.isEmpty else { return 1 }

        let referenceFont = font(ofSize: referenceFontSize)
        let referenceWidth = (text as NSString).size(withAttributes: [
            .font: referenceFont
        ]).width
        guard referenceWidth.isFinite, referenceWidth > 0 else { return 1 }

        let targetWidth = Double(width) * ratio
        let widthMatchedSize = Double(referenceFontSize) * targetWidth / Double(referenceWidth)
        let heightLimit = Double(height) * ratioRange.upperBound
        return min(max(widthMatchedSize, 1), max(heightLimit, 1))
    }

    static func font(ofSize size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .bold)
    }
}
