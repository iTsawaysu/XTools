import AppKit
import MarkdownUI
import os
import SwiftUI
import Testing
@testable import XTools

@MainActor
struct MarkdownThemeRenderingTests {
    @Test func allThemesRenderRepresentativeDocumentAndUpdateInOneHost() async {
        let requests = ImageRequests()
        let hostingView = NSHostingView(rootView: ThemePreview(theme: .basic, content: "", requests: requests))
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

        let themes: [(String, Theme, Bool)] = [
            ("basic", .basic, false),
            ("gitHub", .gitHub, false),
            ("docC", .docC, false),
            ("indexClay", .indexClay, false),
            ("publicActorContract", Self.publicActorContractTheme(), true),
        ]

        for (index, (name, theme, overrides)) in themes.enumerated() {
            hostingView.rootView = ThemePreview(
                theme: theme,
                content: Self.markdown,
                requests: requests,
                usesPublicStyleOverrides: overrides
            )
            hostingView.layoutSubtreeIfNeeded()
            if index == 0 {
                let rendered = await waitForInitialImages(in: hostingView, requests: requests)
                #expect(rendered, "The document must invoke both local image providers")
            } else {
                await Task.yield()
                hostingView.layoutSubtreeIfNeeded()
            }

            let size = hostingView.fittingSize
            #expect(size.width.isFinite && size.width > 0, "\(name) must have finite nonzero width")
            #expect(size.height.isFinite && size.height > 0, "\(name) must have finite nonzero height")
            let empty = NSHostingView(rootView: Markdown("").markdownTheme(theme))
            empty.frame = hostingView.frame
            empty.layoutSubtreeIfNeeded()
            #expect(size.height > empty.fittingSize.height, "\(name) must occupy more height than an empty document")
        }

        let block = Set(requests.block.withLock { $0 })
        let inline = Set(requests.inline.withLock { $0 })
        #expect(block == [Self.blockImageURL], "Only the fixture's block image may reach its provider")
        #expect(inline == [Self.inlineImageURL], "Only the fixture's inline image may reach its provider")
    }

    private static let blockImageURL = URL(string: "https://fixture.invalid/block.png")!
    private static let inlineImageURL = URL(string: "https://fixture.invalid/inline.png")!

    private static func publicActorContractTheme() -> Theme {
        let block: @MainActor (BlockConfiguration) -> BlockConfiguration.Label = { $0.label }
        let code: @MainActor (CodeBlockConfiguration) -> CodeBlockConfiguration.Label = { $0.label }
        let cell: @MainActor (TableCellConfiguration) -> TableCellConfiguration.Label = { $0.label }
        let task: @MainActor (TaskListMarkerConfiguration) -> Text = {
            Text($0.isCompleted ? "Done" : "Open")
        }
        let marker: @MainActor (ListMarkerConfiguration) -> Text = { Text("\($0.itemNumber).") }
        let rule: @MainActor () -> Divider = { Divider() }
        let directBlock = BlockStyle(body: block)
        let directRule = BlockStyle<Void>(body: rule)

        var theme = Theme.actorContractHeading
            .heading2(body: block)
            .heading3(body: block)
            .heading4(body: block)
            .heading5(body: block)
            .heading6(body: block)
            .paragraph(body: block)
            .blockquote(body: block)
            .codeBlock(body: code)
            .image(body: block)
            .list(body: block)
            .listItem(body: block)
            .taskListMarker(body: task)
            .bulletedListMarker(body: marker)
            .numberedListMarker(body: marker)
            .table(body: block)
            .tableCell(body: cell)
            .thematicBreak(body: rule)
        theme.heading2 = directBlock
        theme.thematicBreak = directRule
        return theme
    }

    fileprivate static let markdown = """
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
        in hostingView: NSHostingView<ThemePreview>,
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

@MainActor
extension Theme {
    fileprivate static let actorContractHeading = Theme().heading1 { @MainActor configuration in
        configuration.label
            .markdownMargin(top: 8, bottom: 4)
            .markdownTextStyle {
                FontWeight(.semibold)
                ForegroundColor(.red)
            }
    }
}

private struct ThemePreview: View {
    let theme: Theme
    let content: String
    let requests: ImageRequests
    var usesPublicStyleOverrides = false

    @ViewBuilder
    var body: some View {
        if usesPublicStyleOverrides {
            let block: @MainActor (BlockConfiguration) -> BlockConfiguration.Label = { $0.label }
            let rule: @MainActor () -> Divider = { Divider() }
            markdown
                .markdownBlockStyle(\.paragraph, body: block)
                .markdownBlockStyle(\.thematicBreak, body: rule)
        } else {
            markdown
        }
    }

    private var markdown: some View {
        Markdown(content)
            .markdownTheme(theme)
            .markdownImageProvider(BlockSymbolProvider(requests: requests))
            .markdownInlineImageProvider(InlineSymbolProvider(requests: requests))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private final class ImageRequests: Sendable {
    let block = OSAllocatedUnfairLock(initialState: [URL]())
    let inline = OSAllocatedUnfairLock(initialState: [URL]())
}

private struct BlockSymbolProvider: ImageProvider {
    let requests: ImageRequests

    func makeImage(url: URL?) -> some View {
        if let url {
            requests.block.withLock { $0.append(url) }
        }
        return Image(systemName: "photo")
            .accessibilityLabel("Block symbol")
    }
}

private struct InlineSymbolProvider: InlineImageProvider {
    let requests: ImageRequests

    func image(with url: URL, label: String) async throws -> Image {
        requests.inline.withLock { $0.append(url) }
        return Image(systemName: "photo")
    }
}
