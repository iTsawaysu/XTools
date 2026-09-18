import MarkdownUI
import SwiftUI

/// Rendered Markdown preview backed by swift-markdown-ui (full GFM: tables,
/// task lists, fenced code, images) with a Clay-matched theme. This is the
/// `.markdownPreview` output presentation; monospaced source reading stays on
/// `IndexReadOnlyTextSurface`.
struct IndexMarkdownPreviewSurface: View {
    let text: String
    var placeholder: String = IndexEmptyStateCopy.outputWillShowHere
    var fillsHeight = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical) {
                Markdown(text)
                    .markdownTheme(.indexClay)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .opacity(text.isEmpty ? 0 : 1)
            .accessibilityHidden(text.isEmpty)

            if text.isEmpty {
                Text(placeholder)
                    .font(ToolTypography.body)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel(placeholder)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: fillsHeight ? 60 : 220,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}

@MainActor
private enum IndexClayMarkdownPalette {
    static let text = ToolTheme.textPrimary
    static let accent = ToolTheme.accent
    static let field = ToolTheme.editorBackground
}

@MainActor
extension Theme {
    /// Prose reading theme mapped onto the Clay design tokens: warm
    /// primary/secondary text, Clay accent links, and code surfaces that
    /// match the editor field background. Built in stages: one long builder
    /// chain overloads the type checker under StrictConcurrency.
    static let indexClay: Theme = {
        let inline = Theme()
            .text {
                ForegroundColor(IndexClayMarkdownPalette.text)
                FontSize(13)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                BackgroundColor(IndexClayMarkdownPalette.field)
            }
            .link {
                ForegroundColor(IndexClayMarkdownPalette.accent)
                UnderlineStyle(Text.LineStyle(pattern: .solid))
            }
            .strong {
                FontWeight(.semibold)
            }

        let withHeadings = inline
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 20, bottom: 10)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(20)
                        ForegroundColor(IndexClayMarkdownPalette.text)
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 16, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(16)
                        ForegroundColor(IndexClayMarkdownPalette.text)
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 12, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(14)
                        ForegroundColor(IndexClayMarkdownPalette.text)
                    }
            }

        return withHeadings
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                    }
                    .padding(12)
                    .background(IndexClayMarkdownPalette.field)
                    .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                    .markdownMargin(top: 8, bottom: 8)
            }
            .table { configuration in
                configuration.label
                    .markdownMargin(top: 8, bottom: 8)
                    .markdownTableBackgroundStyle(
                        .alternatingRows(IndexClayMarkdownPalette.field, IndexClayMarkdownPalette.field)
                    )
            }
    }()
}
