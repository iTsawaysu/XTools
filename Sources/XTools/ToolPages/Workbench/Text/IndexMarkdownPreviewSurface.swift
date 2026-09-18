import MarkdownUI
import SwiftUI
import XToolsCore

/// Rendered Markdown preview backed by swift-markdown-ui (full GFM: tables,
/// task lists, fenced code, images) with a Clay-matched theme. This is the
/// `.markdownPreview` output presentation; monospaced source reading stays on
/// `IndexReadOnlyTextSurface`.
struct IndexMarkdownPreviewSurface: View {
    let text: String
    var placeholder: String = IndexEmptyStateCopy.outputWillShowHere
    var fillsHeight = false
    var remoteImagePolicy: MarkdownRemoteImagePolicy = .publicHTTPAndHTTPS
    var accessibilityTitle: String? = nil
    @Environment(\.markdownPreviewAuthorizationGeneration) private var authorizationGeneration
    @State private var remoteImageAuthorization = MarkdownRemoteImageAuthorizationState()
    @State private var remoteImageDetection = MarkdownRemoteImageDetectionState()

    private var authorizationScope: MarkdownRemoteImageAuthorizationScope {
        MarkdownRemoteImageAuthorizationScope(
            resultText: text,
            generation: authorizationGeneration
        )
    }

    private var remoteImagesAuthorized: Bool {
        remoteImageAuthorization.isAuthorized(for: authorizationScope)
    }

    private var containsRemoteImages: Bool {
        remoteImageDetection.containsRemoteImages(for: authorizationScope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if containsRemoteImages, !remoteImagesAuthorized {
                remoteImageAuthorizationBanner
            }

            ZStack(alignment: .topLeading) {
                ScrollView(.vertical) {
                    Markdown(text)
                        .markdownTheme(.indexClay)
                        .markdownImageProvider(
                            MarkdownPreviewImageProvider(
                                authorized: remoteImagesAuthorized,
                                policy: remoteImagePolicy
                            )
                        )
                        .markdownInlineImageProvider(
                            MarkdownPreviewInlineImageProvider(
                                authorized: remoteImagesAuthorized,
                                policy: remoteImagePolicy
                            )
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .opacity(text.isEmpty ? 0 : 1)
                .accessibilityHidden(text.isEmpty)
                .accessibilityElement(children: .contain)
                .modifier(MarkdownPreviewAccessibilityTitle(title: accessibilityTitle))

                if text.isEmpty {
                    Text(placeholder)
                        .font(ToolTypography.body)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .accessibilityLabel(placeholder)
                }
            }

        }
        .onChange(of: authorizationScope) { _ in
            remoteImageAuthorization.revoke()
        }
        .task(id: authorizationScope) {
            let scope = authorizationScope
            guard remoteImageDetection.beginDetection(for: scope) else { return }
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            let source = text
            let containsRemoteImages = await Task.detached(priority: .utility) {
                MarkdownRemoteImageDetector.containsRemoteImage(in: source)
            }.value
            guard !Task.isCancelled else { return }
            remoteImageDetection.publish(
                containsRemoteImages: containsRemoteImages,
                for: scope,
                currentScope: authorizationScope
            )
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

    private var remoteImageAuthorizationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .accessibilityHidden(true)
            Text("远程图片默认不会加载。")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            Spacer(minLength: 0)
            Button("加载远程图片") {
                remoteImageAuthorization.authorize(authorizationScope)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel("加载当前 Markdown 结果中的远程图片")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ToolTheme.accentSoft, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(ToolTheme.accentBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MarkdownPreviewAccessibilityTitle: ViewModifier {
    let title: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title {
            content.accessibilityLabel(title)
        } else {
            content
        }
    }
}

private struct MarkdownPreviewAuthorizationGenerationKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var markdownPreviewAuthorizationGeneration: Int {
        get { self[MarkdownPreviewAuthorizationGenerationKey.self] }
        set { self[MarkdownPreviewAuthorizationGenerationKey.self] = newValue }
    }
}

struct MarkdownRemoteImageAuthorizationScope: Hashable, Sendable {
    let resultText: String
    let generation: Int
}

/// A bounded one-result cache for the parser-backed remote-image scan. The
/// current scope gates publication so cancelled work cannot reveal an
/// authorization action for an obsolete Markdown result.
struct MarkdownRemoteImageDetectionState: Equatable {
    private var detectedScope: MarkdownRemoteImageAuthorizationScope?
    private var detectedValue: Bool?

    mutating func beginDetection(for scope: MarkdownRemoteImageAuthorizationScope) -> Bool {
        guard detectedScope != scope || detectedValue == nil else { return false }
        detectedScope = scope
        detectedValue = nil
        return true
    }

    mutating func publish(
        containsRemoteImages: Bool,
        for scope: MarkdownRemoteImageAuthorizationScope,
        currentScope: MarkdownRemoteImageAuthorizationScope
    ) {
        guard scope == currentScope, detectedScope == scope else { return }
        detectedValue = containsRemoteImages
    }

    func containsRemoteImages(for scope: MarkdownRemoteImageAuthorizationScope) -> Bool {
        detectedScope == scope && detectedValue == true
    }
}

struct MarkdownRemoteImageAuthorizationState: Equatable {
    private var authorizedScope: MarkdownRemoteImageAuthorizationScope?

    mutating func authorize(_ scope: MarkdownRemoteImageAuthorizationScope) {
        authorizedScope = scope
    }

    mutating func revoke() {
        authorizedScope = nil
    }

    func isAuthorized(for scope: MarkdownRemoteImageAuthorizationScope) -> Bool {
        authorizedScope == scope
    }
}

struct MarkdownRemoteImagePolicy: Sendable {
    typealias Evaluator = @Sendable (URL) -> Bool

    private let evaluator: Evaluator

    init(allows: @escaping Evaluator) {
        self.evaluator = allows
    }

    func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty,
              HTMLToMarkdownURLFetchService.isValidHost(host),
              URLFetchHostPolicy.evaluate(host: host) == .allow else {
            return false
        }
        return evaluator(url)
    }

    static let publicHTTPAndHTTPS = Self { _ in true }
    static let httpAndHTTPSOnly = publicHTTPAndHTTPS
}

enum MarkdownRemoteImageDetector {
    static let maximumSourceByteCount = 5 * 1024 * 1024
    static let maximumRenderedHTMLByteCount = 10 * 1024 * 1024

    static func containsRemoteImage(in markdown: String) -> Bool {
        guard !markdown.isEmpty,
              markdown.utf8.count <= maximumSourceByteCount else {
            return false
        }

        // MarkdownUI renders raw HTML as text and does not route `<img>`
        // through either image provider. Remove those tags before asking the
        // same public GFM parser used by the preview to resolve inline and
        // reference-style Markdown images. Code spans/fences remain protected
        // by the parser and therefore cannot become image nodes.
        let markdownWithoutRawImages = markdown.replacingOccurrences(
            of: #"(?is)<img\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        let renderedHTML = MarkdownContent(markdownWithoutRawImages).renderHTML()
        guard renderedHTML.utf8.count <= maximumRenderedHTMLByteCount else {
            return false
        }

        let pattern = #"(?is)<img\b[^>]*\bsrc\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let fullRange = NSRange(renderedHTML.startIndex..., in: renderedHTML)
        for match in expression.matches(in: renderedHTML, range: fullRange) {
            for captureIndex in 1...3 where match.range(at: captureIndex).location != NSNotFound {
                guard let range = Range(match.range(at: captureIndex), in: renderedHTML),
                      let url = URL(string: String(renderedHTML[range])),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      url.host?.isEmpty == false else {
                    continue
                }
                return true
            }
        }
        return false
    }
}

struct MarkdownPreviewImageProvider: ImageProvider {
    typealias Loader = (URL) -> AnyView

    let authorized: Bool
    let policy: MarkdownRemoteImagePolicy
    let loader: Loader

    init(
        authorized: Bool,
        policy: MarkdownRemoteImagePolicy,
        loader: @escaping Loader = { url in
            AnyView(DefaultImageProvider.default.makeImage(url: url))
        }
    ) {
        self.authorized = authorized
        self.policy = policy
        self.loader = loader
    }

    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        let decision = url.map {
            MarkdownRemoteImageLoadDecision(authorized: authorized, url: $0, policy: policy)
        } ?? .deniedByPolicy

        if let url, decision == .load {
            loader(url)
        } else {
            Text(decision.statusText ?? "图片地址未获准加载。")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .accessibilityLabel(decision.statusText ?? "图片地址未获准加载")
        }
    }
}

struct MarkdownPreviewInlineImageProvider: InlineImageProvider {
    typealias Loader = @Sendable (URL, String) async throws -> Image

    let authorized: Bool
    let policy: MarkdownRemoteImagePolicy
    let loader: Loader

    init(
        authorized: Bool,
        policy: MarkdownRemoteImagePolicy,
        loader: @escaping Loader = { url, label in
            try await DefaultInlineImageProvider.default.image(with: url, label: label)
        }
    ) {
        self.authorized = authorized
        self.policy = policy
        self.loader = loader
    }

    func image(with url: URL, label: String) async throws -> Image {
        switch MarkdownRemoteImageLoadDecision(authorized: authorized, url: url, policy: policy) {
        case .blockedUntilExplicitAction:
            return blockedImage(accessibilityDescription: "远程图片未加载")
        case .deniedByPolicy:
            return blockedImage(accessibilityDescription: "图片地址未获准加载")
        case .load:
            return try await loader(url, label)
        }
    }

    private func blockedImage(accessibilityDescription: String) -> Image {
        let image = NSImage(
            systemSymbolName: "nosign",
            accessibilityDescription: accessibilityDescription
        ) ?? NSImage()
        return Image(nsImage: image)
    }
}

enum MarkdownRemoteImageLoadDecision: Equatable {
    case blockedUntilExplicitAction
    case deniedByPolicy
    case load

    init(authorized: Bool, url: URL, policy: MarkdownRemoteImagePolicy) {
        if !authorized {
            self = .blockedUntilExplicitAction
        } else if policy.allows(url) {
            self = .load
        } else {
            self = .deniedByPolicy
        }
    }

    var statusText: String? {
        switch self {
        case .blockedUntilExplicitAction:
            return "远程图片未加载。"
        case .deniedByPolicy:
            return "图片地址未获准加载。"
        case .load:
            return nil
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
