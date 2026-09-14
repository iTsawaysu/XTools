import XToolsCore
import SwiftUI

struct IndexResultPresence<
    Value,
    UpdateID: Equatable,
    ResultContent: View,
    EmptyContent: View
>: View {
    let value: Value?
    let updateID: UpdateID
    let motion: IndexResultPresenceMotionPolicy
    let firstAppearance: IndexResultPresenceFirstAppearancePolicy
    private let resultContent: (Value) -> ResultContent
    private let emptyContent: () -> EmptyContent

    @State private var presentation: IndexResultPresenceState<Value>
    @State private var visibleHeight: CGFloat?
    @State private var emptyHeight: CGFloat?
    @State private var resultHeight: CGFloat?
    @State private var resultOpacity: Double
    @State private var completionRequest: IndexResultPresenceCompletion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        value: Value?,
        updateID: UpdateID,
        motion: IndexResultPresenceMotionPolicy = .animated,
        firstAppearance: IndexResultPresenceFirstAppearancePolicy = .animated,
        @ViewBuilder result: @escaping (Value) -> ResultContent,
        @ViewBuilder empty: @escaping () -> EmptyContent
    ) {
        self.value = value
        self.updateID = updateID
        self.motion = motion
        self.firstAppearance = firstAppearance
        resultContent = result
        emptyContent = empty
        _presentation = State(initialValue: IndexResultPresenceState(initialValue: value))
        _resultOpacity = State(initialValue: value == nil ? 0 : 1)
    }

    var body: some View {
        clippedTrack
            .allowsHitTesting(presentation.phase != .exiting)
            .accessibilityHidden(presentation.phase == .exiting)
            .overlay(alignment: .topLeading) {
                if presentation.phase != .empty {
                    emptyMeasurement
                }
            }
            .onPreferenceChange(IndexResultPresenceEmptyHeightKey.self) { height in
                updateEmptyHeight(height)
            }
            .onPreferenceChange(IndexResultPresenceResultHeightKey.self) { height in
                updateResultHeight(height)
            }
            .task(id: updateID) {
                applyTarget(value, reduceMotion: reduceMotion || motion == .immediate)
            }
            .onChange(of: reduceMotion) { enabled in
                if enabled {
                    applyTarget(value, reduceMotion: true)
                }
            }
            .task(id: completionRequest) {
                guard let completionRequest else { return }
                await finalize(completionRequest)
            }
    }

    private var clippedTrack: some View {
        visibleContent
            .frame(height: visibleHeight, alignment: .top)
            .clipped()
    }

    @ViewBuilder
    private var visibleContent: some View {
        if presentation.phase == .empty {
            emptyContent()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    heightReader(key: IndexResultPresenceEmptyHeightKey.self)
                }
        } else if let displayedValue {
            resultContent(displayedValue)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(resultOpacity)
                .background {
                    heightReader(key: IndexResultPresenceResultHeightKey.self)
                }
        }
    }

    private var displayedValue: Value? {
        switch presentation.phase {
        case .empty:
            nil
        case .appearing, .presented:
            value ?? presentation.snapshot
        case .exiting:
            presentation.snapshot
        }
    }

    private var emptyMeasurement: some View {
        emptyContent()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                heightReader(key: IndexResultPresenceEmptyHeightKey.self)
            }
    }

    private func heightReader<Key: PreferenceKey>(key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }

    @MainActor
    private func applyTarget(_ target: Value?, reduceMotion: Bool) {
        var next = presentation
        let action = next.update(
            to: target,
            reduceMotion: reduceMotion,
            firstAppearance: firstAppearance
        )
        guard action != .none else { return }

        withTransaction(ToolMotion.disabledTransaction) {
            presentation = next
            completionRequest = nil

            switch action {
            case let .appear(_, fadesIn):
                if fadesIn {
                    resultHeight = nil
                    resultOpacity = 0
                    visibleHeight = emptyHeight
                }
            case .exit:
                break
            case .settle:
                resultOpacity = target == nil ? 0 : 1
                visibleHeight = target == nil ? emptyHeight : nil
            case .none, .update:
                break
            }
        }

        switch action {
        case let .appear(generation, _):
            if let resultHeight {
                startAppearance(generation: generation, height: resultHeight)
            }
        case let .exit(generation):
            if let emptyHeight {
                startExit(generation: generation, height: emptyHeight)
            }
        case .none, .update, .settle:
            break
        }
    }

    @MainActor
    private func updateEmptyHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        emptyHeight = height

        switch presentation.phase {
        case .empty:
            setVisibleHeightImmediately(height)
        case .exiting where completionRequest == nil:
            startExit(generation: presentation.generation, height: height)
        case .appearing, .presented, .exiting:
            break
        }
    }

    @MainActor
    private func updateResultHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        resultHeight = height

        switch presentation.phase {
        case .appearing where completionRequest == nil:
            startAppearance(generation: presentation.generation, height: height)
        case .presented:
            setVisibleHeightImmediately(height)
        case .empty, .appearing, .exiting:
            break
        }
    }

    @MainActor
    private func startAppearance(generation: Int, height: CGFloat) {
        guard presentation.phase == .appearing,
              presentation.generation == generation,
              completionRequest == nil else { return }

        withToolAnimation(ToolMotion.Preset.resultPresenceAppearance, reduceMotion: reduceMotion) {
            visibleHeight = height
            resultOpacity = 1
        }
        completionRequest = .appearance(generation: generation)
    }

    @MainActor
    private func startExit(generation: Int, height: CGFloat) {
        guard presentation.phase == .exiting,
              presentation.generation == generation,
              completionRequest == nil else { return }

        withToolAnimation(ToolMotion.Preset.resultPresenceExit, reduceMotion: reduceMotion) {
            visibleHeight = height
            resultOpacity = 0
        }
        completionRequest = .exit(generation: generation)
    }

    @MainActor
    private func setVisibleHeightImmediately(_ height: CGFloat) {
        guard visibleHeight == nil || abs((visibleHeight ?? height) - height) > 0.5 else { return }
        withTransaction(ToolMotion.disabledTransaction) {
            visibleHeight = height
        }
    }

    @MainActor
    private func finalize(_ request: IndexResultPresenceCompletion) async {
        do {
            try await Task.sleep(nanoseconds: UInt64(request.duration * 1_000_000_000))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        var next = presentation
        guard next.finish(request) else { return }

        withTransaction(ToolMotion.disabledTransaction) {
            presentation = next
            completionRequest = nil
            resultOpacity = next.phase == .empty ? 0 : 1
            visibleHeight = next.phase == .empty ? emptyHeight : resultHeight
        }
    }
}

struct IndexScrollableResultPresence<
    Value,
    UpdateID: Equatable,
    ResultContent: View,
    EmptyContent: View
>: View {
    let value: Value?
    let updateID: UpdateID
    private let resultContent: (Value, Bool) -> ResultContent
    private let emptyContent: () -> EmptyContent

    @State private var presentation: IndexResultPresenceState<Value>
    @State private var visibleHeight: CGFloat?
    @State private var emptyHeight: CGFloat?
    @State private var resultContentHeight: CGFloat?
    @State private var appearanceStartsCollapsed = false
    @State private var resultOpacity: Double
    @State private var completionRequest: IndexResultPresenceCompletion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        value: Value?,
        updateID: UpdateID,
        @ViewBuilder result: @escaping (Value, Bool) -> ResultContent,
        @ViewBuilder empty: @escaping () -> EmptyContent
    ) {
        self.value = value
        self.updateID = updateID
        resultContent = result
        emptyContent = empty
        _presentation = State(initialValue: IndexResultPresenceState(initialValue: value))
        _resultOpacity = State(initialValue: value == nil ? 0 : 1)
    }

    var body: some View {
        GeometryReader { proxy in
            clippedTrack(maximumHeight: proxy.size.height)
                .allowsHitTesting(presentation.phase != .exiting)
                .accessibilityHidden(presentation.phase == .exiting)
                .overlay(alignment: .topLeading) {
                    if presentation.phase != .empty {
                        emptyMeasurement
                    }
                }
                .onPreferenceChange(IndexScrollableResultPresenceEmptyHeightKey.self) { height in
                    updateEmptyHeight(height)
                }
                .onPreferenceChange(IndexScrollableResultPresenceContentHeightKey.self) { height in
                    updateResultHeight(height, maximumHeight: proxy.size.height)
                }
                .task(id: updateID) {
                    applyTarget(value, reduceMotion: reduceMotion, maximumHeight: proxy.size.height)
                }
                .onChange(of: reduceMotion) { enabled in
                    if enabled {
                        applyTarget(value, reduceMotion: true, maximumHeight: proxy.size.height)
                    }
                }
                .task(id: completionRequest) {
                    guard let completionRequest else { return }
                    await finalize(completionRequest, maximumHeight: proxy.size.height)
                }
                .task(id: proxy.size.height) {
                    updateMaximumHeight(proxy.size.height)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func clippedTrack(maximumHeight: CGFloat) -> some View {
        visibleContent(maximumHeight: maximumHeight)
            .frame(height: visibleHeight, alignment: .top)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func visibleContent(maximumHeight: CGFloat) -> some View {
        if presentation.phase == .empty {
            emptyContent()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    heightReader(key: IndexScrollableResultPresenceEmptyHeightKey.self)
                }
        } else if let displayedValue {
            ScrollView {
                resultContent(displayedValue, presentation.phase == .presented)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: emptyHeight ?? 0, alignment: .topLeading)
                    .background {
                        heightReader(key: IndexScrollableResultPresenceContentHeightKey.self)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: resultViewportHeight(maximumHeight: maximumHeight), alignment: .top)
            .opacity(resultOpacity)
        }
    }

    private var displayedValue: Value? {
        switch presentation.phase {
        case .empty:
            nil
        case .appearing, .presented:
            value ?? presentation.snapshot
        case .exiting:
            presentation.snapshot
        }
    }

    private var emptyMeasurement: some View {
        emptyContent()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                heightReader(key: IndexScrollableResultPresenceEmptyHeightKey.self)
            }
    }

    private func heightReader<Key: PreferenceKey>(key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }

    private func resultViewportHeight(maximumHeight: CGFloat) -> CGFloat {
        let maximumHeight = max(0, maximumHeight)
        let proposedHeight = visibleHeight
            ?? cappedResultHeight(maximumHeight: maximumHeight)
            ?? maximumHeight
        return min(maximumHeight, max(0, proposedHeight))
    }

    private func cappedResultHeight(maximumHeight: CGFloat) -> CGFloat? {
        guard let resultContentHeight else { return nil }
        return min(resultContentHeight, max(0, maximumHeight))
    }

    private func collapsedPresenceHeight(
        fullHeight: CGFloat,
        emptyHeight: CGFloat
    ) -> CGFloat {
        let emptyBaseline = min(fullHeight, emptyHeight)
        guard abs(fullHeight - emptyBaseline) <= 0.5 else { return emptyBaseline }
        return max(0, emptyBaseline - ToolMotion.Distance.medium)
    }

    @MainActor
    private func applyTarget(
        _ target: Value?,
        reduceMotion: Bool,
        maximumHeight: CGFloat
    ) {
        var next = presentation
        let action = next.update(to: target, reduceMotion: reduceMotion)
        guard action != .none else { return }

        withTransaction(ToolMotion.disabledTransaction) {
            presentation = next
            completionRequest = nil

            switch action {
            case let .appear(_, fadesIn):
                appearanceStartsCollapsed = fadesIn
                if fadesIn {
                    resultContentHeight = nil
                    resultOpacity = 0
                    visibleHeight = emptyHeight
                }
            case .exit:
                appearanceStartsCollapsed = false
            case .settle:
                appearanceStartsCollapsed = false
                resultOpacity = target == nil ? 0 : 1
                visibleHeight = target == nil
                    ? emptyHeight
                    : cappedResultHeight(maximumHeight: maximumHeight)
            case .none, .update:
                break
            }
        }

        switch action {
        case let .appear(generation, _):
            if let height = cappedResultHeight(maximumHeight: maximumHeight) {
                startAppearance(generation: generation, height: height)
            }
        case let .exit(generation):
            if let emptyHeight {
                startExit(
                    generation: generation,
                    height: emptyHeight,
                    resultHeight: visibleHeight ?? emptyHeight
                )
            }
        case .none, .update, .settle:
            break
        }
    }

    @MainActor
    private func updateEmptyHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        emptyHeight = height

        switch presentation.phase {
        case .empty:
            setVisibleHeightImmediately(height)
        case .exiting where completionRequest == nil:
            startExit(
                generation: presentation.generation,
                height: height,
                resultHeight: visibleHeight ?? height
            )
        case .appearing, .presented, .exiting:
            break
        }
    }

    @MainActor
    private func updateResultHeight(_ height: CGFloat, maximumHeight: CGFloat) {
        guard height > 0 else { return }
        resultContentHeight = height
        let cappedHeight = min(height, max(0, maximumHeight))

        switch presentation.phase {
        case .appearing where completionRequest == nil:
            startAppearance(generation: presentation.generation, height: cappedHeight)
        case .presented:
            updatePresentedHeight(cappedHeight)
        case .empty, .appearing, .exiting:
            break
        }
    }

    @MainActor
    private func updatePresentedHeight(_ height: CGFloat) {
        guard let visibleHeight else {
            setVisibleHeightImmediately(height)
            return
        }
        guard abs(visibleHeight - height) > 0.5 else { return }

        withToolAnimation(ToolMotion.Preset.orderedContent, reduceMotion: reduceMotion) {
            self.visibleHeight = height
        }
    }

    @MainActor
    private func updateMaximumHeight(_ maximumHeight: CGFloat) {
        guard presentation.phase == .presented,
              let height = cappedResultHeight(maximumHeight: maximumHeight) else { return }
        setVisibleHeightImmediately(height)
    }

    @MainActor
    private func startAppearance(generation: Int, height: CGFloat) {
        guard presentation.phase == .appearing,
              presentation.generation == generation,
              completionRequest == nil else { return }

        if appearanceStartsCollapsed, let emptyHeight {
            setVisibleHeightImmediately(collapsedPresenceHeight(
                fullHeight: height,
                emptyHeight: emptyHeight
            ))
        }
        appearanceStartsCollapsed = false
        withToolAnimation(ToolMotion.Preset.resultPresenceAppearance, reduceMotion: reduceMotion) {
            visibleHeight = height
            resultOpacity = 1
        }
        completionRequest = .appearance(generation: generation)
    }

    @MainActor
    private func startExit(
        generation: Int,
        height: CGFloat,
        resultHeight: CGFloat
    ) {
        guard presentation.phase == .exiting,
              presentation.generation == generation,
              completionRequest == nil else { return }

        withToolAnimation(ToolMotion.Preset.resultPresenceExit, reduceMotion: reduceMotion) {
            visibleHeight = collapsedPresenceHeight(
                fullHeight: resultHeight,
                emptyHeight: height
            )
            resultOpacity = 0
        }
        completionRequest = .exit(generation: generation)
    }

    @MainActor
    private func setVisibleHeightImmediately(_ height: CGFloat) {
        guard visibleHeight == nil || abs((visibleHeight ?? height) - height) > 0.5 else { return }
        withTransaction(ToolMotion.disabledTransaction) {
            visibleHeight = height
        }
    }

    @MainActor
    private func finalize(
        _ request: IndexResultPresenceCompletion,
        maximumHeight: CGFloat
    ) async {
        do {
            try await Task.sleep(nanoseconds: UInt64(request.duration * 1_000_000_000))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        var next = presentation
        guard next.finish(request) else { return }

        withTransaction(ToolMotion.disabledTransaction) {
            presentation = next
            completionRequest = nil
            appearanceStartsCollapsed = false
            resultOpacity = next.phase == .empty ? 0 : 1
            visibleHeight = next.phase == .empty
                ? emptyHeight
                : cappedResultHeight(maximumHeight: maximumHeight)
        }
    }
}

private struct IndexScrollableResultPresenceEmptyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IndexScrollableResultPresenceContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IndexResultPresenceEmptyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IndexResultPresenceResultHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
