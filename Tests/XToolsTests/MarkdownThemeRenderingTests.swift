import AppKit
import os
import SwiftUI
import Testing
@testable import XTools

/// 预览渲染回归：indexClay 令牌下的代表文档必须产出有限且非零的布局，
/// 块级/行内图片必须各自路由到对应出口（这正是原 vendored 主题测试锁定的
/// app 侧行为；库自带主题随 MarkdownUI 移除而不再适用）。
@MainActor
struct MarkdownThemeRenderingTests {
    @Test func indexClayPreviewRendersRepresentativeDocumentAndRoutesImages() async {
        let requests = ImageRequests()
        let content = IndexMarkdownPreviewContent(
            blocks: MarkdownDocument.parse(Self.markdown),
            imageProvider: MarkdownPreviewImageProvider(
                authorized: true,
                policy: .httpAndHTTPSOnly,
                loader: { url in
                    requests.block.withLock { $0.append(url) }
                    return AnyView(Image(systemName: "photo").accessibilityLabel("Block symbol"))
                }
            ),
            inlineImageProvider: MarkdownPreviewInlineImageProvider(
                authorized: true,
                policy: .httpAndHTTPSOnly,
                loader: { url, _ in
                    requests.inline.withLock { $0.append(url) }
                    return Image(systemName: "photo")
                }
            )
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 1800)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }

        let rendered = await waitForInitialImages(in: hostingView, requests: requests)
        #expect(rendered, "The document must invoke both local image providers")
        hostingView.layoutSubtreeIfNeeded()

        let size = hostingView.fittingSize
        #expect(size.width.isFinite && size.width > 0, "indexClay must have finite nonzero width")
        #expect(size.height.isFinite && size.height > 0, "indexClay must have finite nonzero height")
        let empty = NSHostingView(rootView: IndexMarkdownPreviewContent(blocks: MarkdownDocument.parse("")))
        empty.frame = hostingView.frame
        empty.layoutSubtreeIfNeeded()
        #expect(size.height > empty.fittingSize.height, "indexClay must occupy more height than an empty document")

        let block = Set(requests.block.withLock { $0 })
        let inline = Set(requests.inline.withLock { $0 })
        #expect(block == [Self.blockImageURL], "Only the fixture's block image may reach its provider")
        #expect(inline == [Self.inlineImageURL], "Only the fixture's inline image may reach its provider")
    }

    @Test func indexClayPreviewKeepsUnauthorizedImagesOutOfProviders() {
        let requests = ImageRequests()
        let content = IndexMarkdownPreviewContent(
            blocks: MarkdownDocument.parse(Self.markdown),
            imageProvider: MarkdownPreviewImageProvider(
                authorized: false,
                policy: .httpAndHTTPSOnly,
                loader: { url in
                    requests.block.withLock { $0.append(url) }
                    return AnyView(Image(systemName: "photo"))
                }
            ),
            inlineImageProvider: MarkdownPreviewInlineImageProvider(
                authorized: false,
                policy: .httpAndHTTPSOnly,
                loader: { url, _ in
                    requests.inline.withLock { $0.append(url) }
                    return Image(systemName: "photo")
                }
            )
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 900)
        hostingView.layoutSubtreeIfNeeded()

        #expect(requests.block.withLock { $0.isEmpty }, "Unauthorized block images must not reach the loader")
        #expect(requests.inline.withLock { $0.isEmpty }, "Unauthorized inline images must not reach the loader")
    }

    private static let blockImageURL = URL(string: "https://fixture.invalid/block.png")!
    private static let inlineImageURL = URL(string: "https://fixture.invalid/inline.png")!

    private static let markdown = """
        # Theme heading one

        ## Theme heading two

        ### Theme heading three

        #### Theme heading four

        ##### Theme heading five

        ###### Theme heading six

        Ordinary **strong** and *emphasis* and ~~strike~~ with `inline code`, [a link](https://fixture.invalid/link), and an inline image ![Inline symbol](https://fixture.invalid/inline.png).

        > Quoted evidence survives rendering.

        ```swift
        let answer = 42
        ```

        - Bulleted item
        - Another item

        1. Numbered item
        2. Second item

        - [x] Finished task
        - [ ] Pending task

        | Name | Detail |
        | :--- | ---: |
        | Row one | **Table cell alpha** |
        | Row two | Table cell beta |

        ---

        ![Block symbol](https://fixture.invalid/block.png)
        """

    private func waitForInitialImages(
        in hostingView: NSHostingView<IndexMarkdownPreviewContent>,
        requests: ImageRequests
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            if !requests.block.withLock({ $0.isEmpty })
                && !requests.inline.withLock({ $0.isEmpty }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }
}

private final class ImageRequests: Sendable {
    let block = OSAllocatedUnfairLock(initialState: [URL]())
    let inline = OSAllocatedUnfairLock(initialState: [URL]())
}
