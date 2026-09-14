import SwiftUI

/// The header stays at the call site; this view only owns the expandable body.
struct ToolDisclosureBody<Content: View>: View {
    let isExpanded: Bool
    var topSpacing: CGFloat = 0
    var bottomSpacing: CGFloat = 0
    var animation: Animation? = ToolMotion.Preset.accordion
    var unmountDelay: TimeInterval
    private let content: Content

    @State private var measuredContentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var hasMeasuredContentHeight = false
    @State private var keepsContentMounted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isExpanded: Bool,
        topSpacing: CGFloat = 0,
        bottomSpacing: CGFloat = 0,
        animation: Animation? = ToolMotion.Preset.accordion,
        unmountDelay: TimeInterval = ToolMotion.Duration.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
        self.animation = animation
        self.unmountDelay = unmountDelay
        self.content = content()
        _keepsContentMounted = State(initialValue: isExpanded)
    }

    private var shouldRenderContent: Bool {
        isExpanded || keepsContentMounted
    }

    private var resolvedAnimation: Animation? {
        guard let animation else { return nil }
        return ToolMotion.animation(animation, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shouldRenderContent {
                VStack(alignment: .leading, spacing: 0) {
                    if topSpacing > 0 {
                        Color.clear
                            .frame(height: topSpacing)
                            .accessibilityHidden(true)
                    }

                    content

                    if bottomSpacing > 0 {
                        Color.clear
                            .frame(height: bottomSpacing)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ToolDisclosureBodyHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
        }
        .frame(height: visibleHeight, alignment: .top)
        .clipped()
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .onPreferenceChange(ToolDisclosureBodyHeightKey.self) { height in
            let wasMeasured = hasMeasuredContentHeight
            measuredContentHeight = height
            hasMeasuredContentHeight = true

            guard isExpanded else { return }
            setVisibleHeight(height, animated: wasMeasured)
        }
        .onChange(of: isExpanded) { expanded in
            if expanded {
                keepsContentMounted = true
                if hasMeasuredContentHeight {
                    setVisibleHeight(measuredContentHeight, animated: true)
                }
            } else {
                setVisibleHeight(0, animated: true)
            }
        }
        .task(id: isExpanded) {
            await updateMountedContent()
        }
    }

    @MainActor
    private func updateMountedContent() async {
        if isExpanded {
            keepsContentMounted = true
            return
        }

        guard keepsContentMounted else { return }
        if resolvedAnimation != nil, unmountDelay > 0 {
            let delay = UInt64(unmountDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        guard !Task.isCancelled else { return }
        keepsContentMounted = false
    }

    @MainActor
    private func setVisibleHeight(_ height: CGFloat, animated: Bool) {
        guard animated, let animation else {
            withTransaction(ToolMotion.disabledTransaction) {
                visibleHeight = height
            }
            return
        }

        withToolAnimation(animation, reduceMotion: reduceMotion) {
            visibleHeight = height
        }
    }
}

private struct ToolDisclosureBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
