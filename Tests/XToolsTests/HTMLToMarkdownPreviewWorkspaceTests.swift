import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

struct HTMLToMarkdownPreviewWorkspaceTests {
    @MainActor
    @Test func productionProvidersKeepTheScopedLoaderIdleUntilAuthorization() async throws {
        let url = try #require(URL(string: "https://images.example.com/diagram.png"))
        let session = MarkdownRemoteImageSession(loader: { _ in
            throw MarkdownRemoteImageError.requestFailed
        })
        let block = MarkdownPreviewImageProvider(authorized: false, policy: .httpAndHTTPSOnly, session: session)
        let inline = MarkdownPreviewInlineImageProvider(authorized: false, policy: .httpAndHTTPSOnly, session: session)
        _ = block.makeImage(url: url)
        _ = try await inline.image(with: url, label: "diagram")
        #expect(await session.resourceUsage.urlCount == 0)

        let authorized = MarkdownPreviewInlineImageProvider(authorized: true, policy: .httpAndHTTPSOnly, session: session)
        _ = try await authorized.image(with: url, label: "diagram")
        #expect(await session.resourceUsage.urlCount == 1, "The default inline provider must enter the app-owned session")
        session.cancel()
    }

    @Test func authorizationScopeDistinguishesCanonicallyEquivalentSourceBytes() {
        let composed = MarkdownRemoteImageAuthorizationScope(resultText: "![é](https://example.com/a.png)", generation: 1)
        let decomposed = MarkdownRemoteImageAuthorizationScope(resultText: "![e\u{301}](https://example.com/a.png)", generation: 1)
        var authorization = MarkdownRemoteImageAuthorizationState()
        authorization.authorize(composed)
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
        #expect(!authorization.isAuthorized(for: decomposed))
    }

    @Test func remoteImagePolicyBlocksRequestsUntilCurrentResultIsExplicitlyAuthorized() throws {
        let allowed = try #require(URL(string: "https://images.example.com/diagram.png"))
        let denied = try #require(URL(string: "file:///tmp/diagram.png"))
        let requests = PreviewImageRequestRecorder()
        let policy = MarkdownRemoteImagePolicy { url in
            requests.record(url)
            return url.host == "images.example.com"
        }

        #expect(MarkdownRemoteImageLoadDecision(authorized: false, url: allowed, policy: policy) == .blockedUntilExplicitAction)
        #expect(requests.urls.isEmpty, "默认预览不应评估或请求远程图片")

        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: allowed, policy: policy) == .load)
        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: denied, policy: policy) == .deniedByPolicy)
        #expect(requests.urls == [allowed], "安全基线应在自定义 evaluator 前拒绝 file URL")
    }

    @MainActor
    @Test func blockAndInlineProvidersMakeZeroRequestsBeforeAuthorization() async throws {
        let url = try #require(URL(string: "https://images.example.com/diagram.png"))
        let requests = PreviewImageRequestRecorder()
        let blockProvider = MarkdownPreviewImageProvider(
            authorized: false,
            policy: .httpAndHTTPSOnly,
            loader: { requestedURL in
                requests.record(requestedURL)
                return AnyView(EmptyView())
            }
        )
        let inlineProvider = MarkdownPreviewInlineImageProvider(
            authorized: false,
            policy: .httpAndHTTPSOnly,
            loader: { requestedURL, _ in
                requests.record(requestedURL)
                return Image(systemName: "photo")
            }
        )

        _ = blockProvider.makeImage(url: url)
        _ = try await inlineProvider.image(with: url, label: "diagram")

        #expect(requests.urls.isEmpty)
    }

    @MainActor
    @Test func providersRequestOnlyAuthorizedAndAllowedURLs() async throws {
        let allowed = try #require(URL(string: "https://images.example.com/diagram.png"))
        let denied = try #require(URL(string: "file:///tmp/private.png"))
        let requests = PreviewImageRequestRecorder()
        let policy = MarkdownRemoteImagePolicy { $0.scheme == "https" }
        let blockProvider = MarkdownPreviewImageProvider(
            authorized: true,
            policy: policy,
            loader: { requestedURL in
                requests.record(requestedURL)
                return AnyView(EmptyView())
            }
        )
        let inlineProvider = MarkdownPreviewInlineImageProvider(
            authorized: true,
            policy: policy,
            loader: { requestedURL, _ in
                requests.record(requestedURL)
                return Image(systemName: "photo")
            }
        )

        _ = blockProvider.makeImage(url: allowed)
        _ = blockProvider.makeImage(url: denied)
        _ = try await inlineProvider.image(with: allowed, label: "allowed")
        _ = try await inlineProvider.image(with: denied, label: "private path")

        #expect(requests.urls == [allowed, allowed])
    }

    @Test func authorizationIsScopedToBothInputGenerationAndResultText() {
        let current = MarkdownRemoteImageAuthorizationScope(resultText: "same", generation: 1)
        var authorization = MarkdownRemoteImageAuthorizationState()
        authorization.authorize(current)

        #expect(authorization.isAuthorized(for: current))
        #expect(!authorization.isAuthorized(for: .init(resultText: "changed", generation: 1)))
        #expect(!authorization.isAuthorized(for: .init(resultText: "same", generation: 2)))

        authorization.revoke()
        #expect(!authorization.isAuthorized(for: current))
    }

    @Test func remoteImageDetectionCacheRejectsStalePublicationAndReusesCurrentResult() {
        let previous = MarkdownRemoteImageAuthorizationScope(resultText: "old", generation: 1)
        let current = MarkdownRemoteImageAuthorizationScope(resultText: "new", generation: 2)
        var detection = MarkdownRemoteImageDetectionState()

        let beganPrevious = detection.beginDetection(for: previous)
        let beganCurrent = detection.beginDetection(for: current)
        #expect(beganPrevious)
        #expect(beganCurrent)
        detection.publish(containsRemoteImages: true, for: previous, currentScope: current)
        #expect(!detection.containsRemoteImages(for: current))

        detection.publish(containsRemoteImages: true, for: current, currentScope: current)
        #expect(detection.containsRemoteImages(for: current))
        let reparsesCurrent = detection.beginDetection(for: current)
        #expect(!reparsesCurrent, "The one-entry cache should not reparse an unchanged result")
    }

    @Test func defaultRemoteImagePolicyOnlyAllowsHTTPAndHTTPSURLs() throws {
        let https = try #require(URL(string: "https://example.com/image.png"))
        let http = try #require(URL(string: "http://example.com/image.png"))
        let file = try #require(URL(string: "file:///tmp/image.png"))
        let relative = try #require(URL(string: "images/image.png"))

        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: https, policy: .httpAndHTTPSOnly) == .load)
        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: http, policy: .httpAndHTTPSOnly) == .load)
        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: file, policy: .httpAndHTTPSOnly) == .deniedByPolicy)
        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: relative, policy: .httpAndHTTPSOnly) == .deniedByPolicy)
        #expect(MarkdownRemoteImageLoadDecision.deniedByPolicy.statusText == "图片地址未获准加载。")
        #expect(MarkdownRemoteImageLoadDecision.deniedByPolicy.statusText?.contains("file:") == false)
    }

    @Test func remoteImageDetectorUsesRenderedGFMNodesAndIgnoresCodeExamples() {
        let supportedRemoteImages = [
            "![inline](https://images.example.com/inline.png)",
            "![reference][diagram]\n\n[diagram]: https://images.example.com/reference.png",
            "before ![inline image](http://images.example.com/a.png) after",
        ]
        for markdown in supportedRemoteImages {
            #expect(MarkdownRemoteImageDetector.containsRemoteImage(in: markdown))
        }

        let unsupportedOrNonRemote = [
            "plain text",
            "![relative](images/local.png)",
            "![file](file:///tmp/local.png)",
            "[ordinary link](https://images.example.com/not-an-image.png)",
            "`![inline code](https://images.example.com/code.png)`",
            "```markdown\n![fenced](https://images.example.com/fenced.png)\n```",
            "```html\n<img src=\"https://images.example.com/fenced-html.png\">\n```",
            "<img src=\"https://images.example.com/raw-html.png\">",
        ]
        for markdown in unsupportedOrNonRemote {
            #expect(!MarkdownRemoteImageDetector.containsRemoteImage(in: markdown))
        }
    }

    @Test func remoteImageDetectorIsBoundedBeforeParsing() {
        let oversized = String(
            repeating: "x",
            count: MarkdownRemoteImageDetector.maximumSourceByteCount + 1
        ) + "![late](https://images.example.com/late.png)"

        #expect(!MarkdownRemoteImageDetector.containsRemoteImage(in: oversized))
    }

    @Test func defaultPolicyRejectsSSRFHostsBeforeInjectedEvaluator() throws {
        let evaluations = PreviewImageRequestRecorder()
        let policy = MarkdownRemoteImagePolicy { url in
            evaluations.record(url)
            return true
        }
        let deniedURLs = [
            "http://localhost/image.png",
            "http://sub.localhost/image.png",
            "http://127.0.0.1/image.png",
            "http://10.0.0.1/image.png",
            "http://172.16.0.1/image.png",
            "http://192.168.1.1/image.png",
            "http://169.254.169.254/latest/meta-data",
            "http://100.64.0.1/image.png",
            "http://[::1]/image.png",
            "http://[fe80::1]/image.png",
            "http://[fd00::1]/image.png",
            "http://metadata.google.internal/computeMetadata/v1/",
        ]

        for rawURL in deniedURLs {
            let url = try #require(URL(string: rawURL))
            #expect(
                MarkdownRemoteImageLoadDecision(authorized: true, url: url, policy: policy)
                    == .deniedByPolicy
            )
        }
        #expect(evaluations.urls.isEmpty, "SSRF 安全基线不得调用可注入 evaluator")

        let publicURL = try #require(URL(string: "https://images.example.com/public.png"))
        #expect(MarkdownRemoteImageLoadDecision(authorized: true, url: publicURL, policy: policy) == .load)
        #expect(evaluations.urls == [publicURL])
    }

    @MainActor
    @Test func renderedPreviewPreferenceRoundTripsThroughStore() {
        let defaults = UserDefaults(suiteName: "HTMLToMarkdownPreviewWorkspaceTests.\(UUID().uuidString)")!
        let store = ToolPreferenceStore(defaults: defaults)

        let model = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(model.showsRenderedPreview == true, "Preview mode is the default presentation")

        model.showsRenderedPreview = false
        let rehydrated = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(rehydrated.showsRenderedPreview == false, "The source/preview choice persists across workspace rehydration")

        rehydrated.showsRenderedPreview = true
        let restored = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(restored.showsRenderedPreview == true)
    }

    @MainActor
    @Test func pageMountsWithoutOverflowAtStandardDetailWidth() {
        let defaults = UserDefaults(suiteName: "HTMLToMarkdownPreviewWorkspaceTests.Mount.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexHTMLToMarkdownPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        let overflowing = Self.horizontallyOverflowingViews(in: hostingView)
        #expect(overflowing.isEmpty, Comment(rawValue: overflowing.map {
            "View \(type(of: $0)) bounds \($0.convert($0.bounds, to: hostingView)) exceed hosting width \(hostingView.bounds.width)"
        }.joined(separator: "\n")))
    }

    @MainActor
    @Test func overflowAuditCatchesNestedOffsetButAllowsClippedScrollDocuments() {
        let hostingRoot = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 400))
        let parent = NSView(frame: NSRect(x: 500, y: 0, width: 180, height: 100))
        let child = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        hostingRoot.addSubview(parent)
        parent.addSubview(child)

        // 两个局部 frame 都满足旧断言，但子视图在根坐标的右边界是 800。
        #expect(parent.frame.maxX <= hostingRoot.bounds.maxX)
        #expect(child.frame.maxX <= hostingRoot.bounds.maxX)
        #expect(child.convert(child.bounds, to: hostingRoot).maxX == 800)
        #expect(Self.horizontallyOverflowingViews(in: hostingRoot).contains { $0 === child })

        let clipView = NSClipView(frame: NSRect(x: 20, y: 120, width: 100, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        hostingRoot.addSubview(clipView)
        clipView.documentView = document
        let overflowing = Self.horizontallyOverflowingViews(in: hostingRoot)
        #expect(overflowing.count == 1 && overflowing[0] === child)
    }

    @MainActor
    private static func horizontallyOverflowingViews(in hostingRoot: NSView) -> [NSView] {
        let rootBounds = hostingRoot.bounds
        let tolerance: CGFloat = 1
        var overflowing: [NSView] = []

        func inspect(_ view: NSView) {
            let frameInRoot = view.convert(view.bounds, to: hostingRoot)
            if frameInRoot.minX < rootBounds.minX - tolerance ||
                frameInRoot.maxX > rootBounds.maxX + tolerance {
                overflowing.append(view)
            }
            for child in view.subviews {
                // Scroll documents may legitimately exceed their clip viewport; the
                // clip view itself still has to fit inside the hosting root.
                if let clipView = view as? NSClipView,
                   let documentView = clipView.documentView,
                   child === documentView {
                    continue
                }
                inspect(child)
            }
        }

        inspect(hostingRoot)
        return overflowing
    }
}

private final class PreviewImageRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []

    var urls: [URL] {
        lock.withLock { storedURLs }
    }

    func record(_ url: URL) {
        lock.withLock { storedURLs.append(url) }
    }
}
