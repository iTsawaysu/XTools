import AppKit
import SwiftUI
import XToolsCore

struct IndexOutputSurface: View {
    let text: String
    let placeholder: String
    var minHeight: CGFloat = 220
    var fillsHeight = false
    var scrollsInternally = true
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var lineNumbers = false
    var colorize: ((String) -> AttributedString)? = nil
    var embedsFlat = false

    private var showsGutter: Bool { lineNumbers }
    private var effectiveMinHeight: CGFloat { fillsHeight ? 60 : minHeight }

    var body: some View {
        Group {
            if text.isEmpty {
                placeholderBody
            } else {
                if scrollsInternally {
                    ScrollView {
                        outputBody
                    }
                } else {
                    outputBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(
            embedsFlat ? Color.clear : ToolTheme.editorBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            if !embedsFlat {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var outputBody: some View {
        if showsGutter {
            gutteredBody
        } else if let colorize {
            colorizedBody(colorize)
        } else {
            plainBody
        }
    }

    private var placeholderBody: some View {
        HStack(alignment: .top, spacing: 0) {
            if showsGutter {
                Text("1")
                    .font(ToolTypography.monoCaption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: IndexEditorLineNumberGutterView.numberColumnWidth, alignment: .trailing)
                    .padding(.trailing, IndexEditorLineNumberGutter.width - IndexEditorLineNumberGutterView.numberColumnWidth)
            }
            Text(placeholder)
                .font(ToolTypography.body)
                .foregroundStyle(ToolTheme.textTertiary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .padding(.leading, showsGutter ? 13 : 0)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: effectiveMinHeight,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .padding(.leading, showsGutter ? 0 : 13)
        .overlay(alignment: .leading) {
            if showsGutter {
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(width: 0.5)
                    .padding(.leading, IndexEditorLineNumberGutter.width)
            }
        }
    }

    private var plainBody: some View {
        Text(indexWrappingAttributedText(text, lineBreakMode: lineBreakMode))
            .font(ToolTypography.codeBody)
            .foregroundStyle(ToolTheme.textSecondary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .topLeading)
            .padding(12)
    }

    private func colorizedBody(_ colorize: @escaping (String) -> AttributedString) -> some View {
        let lines = text.components(separatedBy: "\n")
        var combined = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                combined.append(AttributedString("\n"))
            }
            // Empty lines keep a space so layout height matches the prior per-line path.
            combined.append(line.isEmpty ? AttributedString(" ") : colorize(line))
        }

        return Text(indexWrappingAttributedText(combined, lineBreakMode: lineBreakMode))
            .font(ToolTypography.codeBody)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .topLeading)
            .padding(12)
    }

    private var gutteredBody: some View {
        let lines = text.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(index + 1)")
                        .font(ToolTypography.monoCaption)
                        .monospacedDigit()
                        .foregroundStyle(ToolTheme.textTertiary)
                        .frame(width: IndexEditorLineNumberGutterView.numberColumnWidth, alignment: .trailing)
                        .padding(.trailing, IndexEditorLineNumberGutter.width - IndexEditorLineNumberGutterView.numberColumnWidth)
                    lineText(line)
                        .font(ToolTypography.codeBody)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 13)
                }
                .lineSpacing(6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: effectiveMinHeight, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.trailing, 13)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(width: 0.5)
                .padding(.leading, IndexEditorLineNumberGutter.width)
        }
    }

    @ViewBuilder
    private func lineText(_ line: String) -> some View {
        if let colorize {
            Text(indexWrappingAttributedText(line.isEmpty ? AttributedString(" ") : colorize(line), lineBreakMode: lineBreakMode))
        } else {
            Text(indexWrappingAttributedText(line.isEmpty ? " " : line, lineBreakMode: lineBreakMode))
                .foregroundStyle(ToolTheme.textSecondary)
        }
    }
}

