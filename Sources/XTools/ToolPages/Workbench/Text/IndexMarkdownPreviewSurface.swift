import AppKit
import SwiftUI
import XToolsCore

/// Rendered Markdown preview backed by the in-house GFM renderer
/// (swift-cmark parsing + IndexMarkdownPreviewContent Clay views). This is the
/// `.markdownPreview` output presentation; monospaced source reading stays on
/// `IndexReadOnlyTextSurface`.
struct IndexMarkdownPreviewSurface: View {
    let text: String
    // SwiftUI must re-evaluate this view for NFC/NFD-only changes even when no
    // parent generation is supplied; String's canonical equality is too broad.
    private let exactTextIdentity: JSONExactTextIdentity
    var placeholder: String = IndexEmptyStateCopy.outputWillShowHere
    var fillsHeight = false
    var remoteImagePolicy: MarkdownRemoteImagePolicy = .publicHTTPAndHTTPS
    var accessibilityTitle: String? = nil
    @Environment(\.markdownPreviewAuthorizationGeneration) private var authorizationGeneration
    @State private var remoteImageAuthorization = MarkdownRemoteImageAuthorizationState()
    @State private var remoteImageDetection = MarkdownRemoteImageDetectionState()
    @State private var remoteImageLoader: MarkdownRemoteImageSession?
    @State private var parseCache = MarkdownParseCache()

    init(
        text: String,
        placeholder: String = IndexEmptyStateCopy.outputWillShowHere,
        fillsHeight: Bool = false,
        remoteImagePolicy: MarkdownRemoteImagePolicy = .publicHTTPAndHTTPS,
        accessibilityTitle: String? = nil
    ) {
        self.text = text
        self.exactTextIdentity = JSONExactTextIdentity(text)
        self.placeholder = placeholder
        self.fillsHeight = fillsHeight
        self.remoteImagePolicy = remoteImagePolicy
        self.accessibilityTitle = accessibilityTitle
    }

    private var authorizationScope: MarkdownRemoteImageAuthorizationScope {
        MarkdownRemoteImageAuthorizationScope(
            resultText: text,
            generation: authorizationGeneration
        )
    }

    private var remoteImagesAuthorized: Bool {
        remoteImageAuthorization.isAuthorized(for: authorizationScope)
            && remoteImageLoader?.isCancelled == false
    }

    private var containsRemoteImages: Bool {
        remoteImageDetection.containsRemoteImages(for: authorizationScope)
    }

    private var parsedBlocks: [MarkdownBlock] {
        self.parseCache.blocks(for: self.exactTextIdentity, text: self.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if containsRemoteImages, !remoteImagesAuthorized {
                remoteImageAuthorizationBanner
            }

            ZStack(alignment: .topLeading) {
                ScrollView(.vertical) {
                    IndexMarkdownPreviewContent(
                        blocks: self.parsedBlocks,
                        imageProvider: MarkdownPreviewImageProvider(
                            authorized: remoteImagesAuthorized,
                            policy: remoteImagePolicy,
                            session: remoteImageLoader
                        ),
                        inlineImageProvider: MarkdownPreviewInlineImageProvider(
                            authorized: remoteImagesAuthorized,
                            policy: remoteImagePolicy,
                            session: remoteImageLoader
                        )
                    )
                    // Inline image caches key by image source, not provider
                    // identity. Refresh this read-only tree when authorization
                    // changes so revoked images cannot linger.
                    .id(remoteImagesAuthorized ? remoteImageLoader?.id : nil)
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
            revokeRemoteImages()
        }
        .onDisappear { revokeRemoteImages() }
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
                remoteImageLoader?.cancel()
                remoteImageLoader = MarkdownRemoteImageSession()
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

    private func revokeRemoteImages() {
        remoteImageAuthorization.revoke()
        remoteImageLoader?.cancel()
        remoteImageLoader = nil
    }
}

/// 单条目解析缓存：授权开关等 body 重算不再重新解析未变化的文档。
/// 只在 MainActor（视图内）访问；故意不做成 Observable——缓存变化永不触发
/// 视图刷新，identity 由 JSONExactTextIdentity 保证字节级一致。
@MainActor
final class MarkdownParseCache {
    private var cachedIdentity: JSONExactTextIdentity?
    private var cachedBlocks: [MarkdownBlock] = []

    func blocks(for identity: JSONExactTextIdentity, text: String) -> [MarkdownBlock] {
        if self.cachedIdentity == identity {
            return self.cachedBlocks
        }
        let blocks = MarkdownDocument.parse(text)
        self.cachedIdentity = identity
        self.cachedBlocks = blocks
        return blocks
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generation == rhs.generation && lhs.resultText.utf8.elementsEqual(rhs.resultText.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(generation)
        let combined: Void? = resultText.utf8.withContiguousStorageIfAvailable {
            hasher.combine(bytes: UnsafeRawBufferPointer($0))
        }
        if combined == nil {
            Data(resultText.utf8).withUnsafeBytes { hasher.combine(bytes: $0) }
        }
    }
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

    /// 与预览的加载行为严格对齐：只有 Markdown 语法的图片（含引用式，解析期
    /// 已由 cmark 解析为 image 节点）会经图片出口加载；原始 HTML（`<img>`）在
    /// 预览中按纯文本渲染，因此不算可加载图片。直接遍历 GFM AST 判定。
    static func containsRemoteImage(in markdown: String) -> Bool {
        guard !markdown.isEmpty,
              markdown.utf8.count <= maximumSourceByteCount else {
            return false
        }
        return MarkdownDocument.parse(markdown).contains { $0.containsLoadableRemoteImage }
    }
}

private extension MarkdownBlock {
    var containsLoadableRemoteImage: Bool {
        switch self {
        case .paragraph(let content), .heading(_, let content):
            return content.contains { $0.containsLoadableRemoteImage }
        case .blockquote(let children):
            return children.contains { $0.containsLoadableRemoteImage }
        case .bulletedList(_, let items), .numberedList(_, _, let items):
            return items.contains { $0.children.contains { $0.containsLoadableRemoteImage } }
        case .taskList(_, let items):
            return items.contains { $0.children.contains { $0.containsLoadableRemoteImage } }
        case .table(_, let rows):
            return rows.contains { row in
                row.cells.contains { $0.content.contains { $0.containsLoadableRemoteImage } }
            }
        case .codeBlock, .htmlBlock, .thematicBreak:
            return false
        }
    }
}

private extension MarkdownInline {
    var containsLoadableRemoteImage: Bool {
        switch self {
        case .image(let source, _):
            return Self.isLoadableRemoteURL(source)
        case .link(_, let children), .emphasis(let children), .strong(let children),
            .strikethrough(let children):
            return children.contains { $0.containsLoadableRemoteImage }
        case .text, .softBreak, .lineBreak, .code, .html:
            return false
        }
    }

    private static func isLoadableRemoteURL(_ source: String) -> Bool {
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }
}

struct MarkdownPreviewImageProvider {
    typealias Loader = (URL) -> AnyView

    let authorized: Bool
    let policy: MarkdownRemoteImagePolicy
    let loader: Loader

    init(
        authorized: Bool,
        policy: MarkdownRemoteImagePolicy,
        session: MarkdownRemoteImageSession? = nil,
        loader: Loader? = nil
    ) {
        self.authorized = authorized
        self.policy = policy
        self.loader = loader ?? { url in
            AnyView(MarkdownRemoteImageView(url: url, session: session))
        }
    }

    /// 环境缺省出口：未授权占位；正常链路由 Surface 注入当前会话的出口。
    static var unavailable: Self {
        .init(authorized: false, policy: .httpAndHTTPSOnly)
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

struct MarkdownPreviewInlineImageProvider {
    typealias Loader = @Sendable (URL, String) async throws -> Image

    let authorized: Bool
    let policy: MarkdownRemoteImagePolicy
    let loader: Loader

    init(
        authorized: Bool,
        policy: MarkdownRemoteImagePolicy,
        session: MarkdownRemoteImageSession? = nil,
        loader: Loader? = nil
    ) {
        self.authorized = authorized
        self.policy = policy
        self.loader = loader ?? { url, label in
            guard let session else { throw CancellationError() }
            let image = try await session.image(for: url)
            try Task.checkCancellation()
            guard !session.isCancelled else { throw CancellationError() }
            return Image(image.image, scale: 1, label: Text(label))
        }
    }

    /// 环境缺省出口：未授权占位；正常链路由 Surface 注入当前会话的出口。
    static var unavailable: Self {
        .init(authorized: false, policy: .httpAndHTTPSOnly)
    }

    func image(with url: URL, label: String) async throws -> Image {
        switch MarkdownRemoteImageLoadDecision(authorized: authorized, url: url, policy: policy) {
        case .blockedUntilExplicitAction:
            return blockedImage(accessibilityDescription: "远程图片未加载")
        case .deniedByPolicy:
            return blockedImage(accessibilityDescription: "图片地址未获准加载")
        case .load:
            do {
                return try await loader(url, label)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = (error as? MarkdownRemoteImageError)?.message
                    ?? MarkdownRemoteImageError.requestFailed.message
                return blockedImage(accessibilityDescription: message)
            }
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
