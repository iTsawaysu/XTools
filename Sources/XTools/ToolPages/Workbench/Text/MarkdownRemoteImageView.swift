import SwiftUI
import XToolsCore

/// Display only: the Core authorization session owns networking, decoding and
/// shared resource costs for block and inline images alike.
struct MarkdownRemoteImageView: View {
    let url: URL
    let session: MarkdownRemoteImageSession?
    @State private var loadedImage: CGImage?
    @State private var failure: String?

    nonisolated init(url: URL, session: MarkdownRemoteImageSession?) {
        self.url = url
        self.session = session
    }

    private struct RequestIdentity: Hashable {
        let url: URL
        let sessionID: UUID?
    }

    var body: some View {
        Group {
            if let loadedImage, session?.isCancelled == false {
                Image(decorative: loadedImage, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if let failure {
                Text(failure)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            } else {
                Text(session == nil ? "图片加载会话已结束。" : "正在加载图片…")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
        }
        .task(id: RequestIdentity(url: url, sessionID: session?.id)) {
            loadedImage = nil
            failure = nil
            guard let session else { return }
            do {
                let result = try await session.image(for: url)
                guard !Task.isCancelled, !session.isCancelled else { return }
                loadedImage = result.image
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, !session.isCancelled else { return }
                failure = (error as? MarkdownRemoteImageError)?.message
                    ?? MarkdownRemoteImageError.requestFailed.message
            }
        }
    }
}
