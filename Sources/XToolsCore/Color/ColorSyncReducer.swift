import Foundation

public struct CSSColorWorkspaceState: Equatable, Sendable {
    public var draft: String
    public internal(set) var draftStatus: CSSColorDraftStatus
    public internal(set) var diagnostic: CSSColorDiagnostic?
    public internal(set) var lastValidColor: CSSColor?
    public internal(set) var sourceFamily: CSSColorSyntaxFamily?
    public internal(set) var predefinedSpace: CSSColorSpace?
    public internal(set) var hsl: SIMD3<Double>

    public init(defaultInput: String = "#7C8CFF") {
        draft = defaultInput
        draftStatus = .empty
        diagnostic = nil
        lastValidColor = nil
        sourceFamily = nil
        predefinedSpace = nil
        hsl = .zero
        CSSColorWorkspaceReducer.reduce(state: &self, action: .draftChanged(defaultInput))
    }

    public var visibleColor: CSSColor? {
        draftStatus == .empty ? nil : lastValidColor
    }

    public var formattedValues: [CSSColorFormattedValue] {
        visibleColor.map(CSSColorFormatter.values(for:)) ?? []
    }

    public var isUsingLastValidResult: Bool {
        (draftStatus == .incomplete || draftStatus == .invalid) && lastValidColor != nil
    }

    public var isMappedToSRGB: Bool {
        visibleColor.map { CSSColorGamutMapping.sRGB(for: $0).wasMapped } ?? false
    }

    public var alpha: Double {
        lastValidColor?.alpha ?? 1
    }
}

public enum CSSColorWorkspaceAction: Equatable, Sendable {
    case draftChanged(String)
    case alphaChanged(Double)
    case hslChanged(hue: Double, saturation: Double, lightness: Double)
    case systemColorPicked(red: Double, green: Double, blue: Double, alpha: Double)
}

public enum CSSColorWorkspaceReducer {
    public static func reduce(state: inout CSSColorWorkspaceState, action: CSSColorWorkspaceAction) {
        switch action {
        case let .draftChanged(draft):
            state.draft = draft
            let result = CSSColorParser.classify(draft)
            state.draftStatus = result.status
            state.diagnostic = result.diagnostic
            if let parsed = result.parsed {
                applyValid(parsed, to: &state, rewriteDraft: false)
            }

        case let .alphaChanged(alpha):
            guard let current = state.lastValidColor,
                  let color = try? CSSColor(xyzD65: current.xyzD65, alpha: alpha) else { return }
            let family = state.sourceFamily ?? .rgb
            applyValid(
                CSSParsedColor(color: color, family: family, predefinedSpace: state.predefinedSpace),
                to: &state,
                rewriteDraft: true
            )

        case let .hslChanged(hue, saturation, lightness):
            let alpha = state.lastValidColor?.alpha ?? 1
            guard let color = try? CSSColor(
                components: SIMD3(hue, saturation, lightness),
                space: .hsl,
                alpha: alpha
            ) else { return }
            applyValid(CSSParsedColor(color: color, family: .hsl), to: &state, rewriteDraft: true)

        case let .systemColorPicked(red, green, blue, alpha):
            guard let color = try? CSSColor(
                components: SIMD3(red, green, blue).map { min(max($0, 0), 1) },
                space: .sRGB,
                alpha: alpha
            ) else { return }
            applyValid(CSSParsedColor(color: color, family: .rgb), to: &state, rewriteDraft: true)
        }
    }

    private static func applyValid(
        _ parsed: CSSParsedColor,
        to state: inout CSSColorWorkspaceState,
        rewriteDraft: Bool
    ) {
        state.lastValidColor = parsed.color
        state.sourceFamily = parsed.family
        state.predefinedSpace = parsed.predefinedSpace
        state.draftStatus = .valid
        state.diagnostic = nil
        let mapped = CSSColorGamutMapping.sRGB(for: parsed.color)
        state.hsl = CSSColorMath.hslFromSRGB(mapped.components)
        if rewriteDraft {
            state.draft = CSSColorFormatter.inputText(
                for: parsed.color,
                family: parsed.family,
                predefinedSpace: parsed.predefinedSpace
            )
        }
    }
}

private extension SIMD3 where Scalar == Double {
    func map(_ transform: (Double) -> Double) -> SIMD3<Double> {
        SIMD3(transform(x), transform(y), transform(z))
    }
}
