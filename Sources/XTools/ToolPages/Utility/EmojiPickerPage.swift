import AppKit
import XToolsCore
import SwiftUI

@MainActor
final class EmojiToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<EmojiToolWorkspaceModel>(toolID: "emoji-picker") { preferences in
        EmojiToolWorkspaceModel(preferences: preferences)
    }

    @Published var query = ""
    @Published var category = EmojiCatalog.groups.first?.name ?? ""
    @Published var toneIndex: Int {
        didSet { preferences.set(toneIndex, for: TextDevelopmentToolPreferenceKeys.emojiToneIndex) }
    }
    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        toneIndex = preferences.value(for: TextDevelopmentToolPreferenceKeys.emojiToneIndex)
    }

    func clearSearch() {
        query = ""
    }
}

struct IndexEmojiPage: View {
    var body: some View {
        ToolWorkspaceHost(key: EmojiToolWorkspaceModel.key) { workspace, _ in
            IndexEmojiWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexEmojiWorkspaceContent: View {
    @ObservedObject var workspace: EmojiToolWorkspaceModel
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmedQuery: String {
        workspace.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Upper bound on rendered cells. A broad query (e.g. "a") matches hundreds
    /// of entries; capping keeps the ForEach diff and grid layout cheap on every
    /// keystroke. A category never exceeds this, so it only ever clips search.
    private static let displayLimit = 200
    private static let skinToneItems = EmojiCatalog.skinTones.enumerated().map { (String($0.offset), $0.element.label) }

    /// One body-pass projection so the capped Core search runs once even though
    /// the header, grid, skin-tone control, and empty state share its result.
    private struct DisplayState {
        let panelTitle: String
        let entries: [EmojiEntry]
        let isSearching: Bool
        let isTruncated: Bool
        let selectedGroup: EmojiGroup?

        var showsSkinToneControl: Bool {
            entries.contains(where: \.skinToneCapable)
        }
    }

    private var displayState: DisplayState {
        let query = trimmedQuery
        if !query.isEmpty {
            let result = EmojiCatalog.search(matching: query, limit: Self.displayLimit)
            return DisplayState(
                panelTitle: "搜索结果",
                entries: result.entries,
                isSearching: true,
                isTruncated: result.isTruncated,
                selectedGroup: nil
            )
        }

        let selectedGroup = EmojiCatalog.groups.first { $0.name == workspace.category }
        return DisplayState(
            panelTitle: workspace.category,
            entries: selectedGroup?.entries ?? [],
            isSearching: false,
            isTruncated: false,
            selectedGroup: selectedGroup
        )
    }

    private var tone: Unicode.Scalar? {
        EmojiCatalog.skinTones[safe: workspace.toneIndex]?.scalar
    }

    private var skinToneControl: some View {
        IndexSegmentedControl(
            items: Self.skinToneItems,
            selection: Binding(
                get: { String(workspace.toneIndex) },
                set: { workspace.toneIndex = Int($0) ?? 0 }
            ),
            density: .compact
        )
        .accessibilityLabel("Emoji 肤色")
        .help("选择默认肤色")
    }

    var body: some View {
        let display = displayState

        IndexPage(
            "Emoji 与符号",
            subtitle: "\(EmojiCatalog.totalProducible) 个 Emoji（含肤色变体） · \(EmojiCatalog.specialSymbolCount) 个特殊符号。搜索关键词或选择分类，点击即复制。",
            workspaceSemantic: .queryListWorkspace
        ) {
            IndexActionBar {
                IndexSearchInput(
                    placeholder: "搜索 Emoji 或符号（如 right / 右 / 播放）…",
                    text: $workspace.query,
                    clearTitle: "清空 Emoji 搜索",
                    onClear: workspace.clearSearch
                )
                .frame(maxWidth: 360)
            }

            if !display.isSearching {
                IndexEmojiCategoryBar(selection: $workspace.category)
            }

            // SPEC §P6：emoji 网格在面板内部滚动，整页不滚。
            IndexPanel(display.panelTitle) {
                if !display.isSearching,
                   display.selectedGroup?.name == EmojiCatalog.specialSymbolGroupName,
                   let selectedGroup = display.selectedGroup {
                    specialSymbolSections(selectedGroup.sections)
                } else {
                    emojiGrid(display.entries)
                }
            } accessory: {
                panelAccessory(for: display)
            }
            .verticallyFilling()
        }
    }

    @ViewBuilder
    private func panelAccessory(for display: DisplayState) -> some View {
        HStack(spacing: 10) {
            if display.isTruncated {
                Text("仅展示前 200 个结果")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if display.showsSkinToneControl {
                skinToneControl
            }
        }
    }

    @ViewBuilder
    private func emojiGrid(_ entries: [EmojiEntry]) -> some View {
        if entries.isEmpty {
            IndexEmptyState(
                title: "无匹配结果",
                systemImage: "magnifyingglass",
                message: "没有匹配的 Emoji 或符号"
            )
            .frame(maxWidth: .infinity, minHeight: 90)
        } else {
            IndexEmojiCollectionView(
                snapshot: .flat(entries: entries, tone: tone),
                scrollResetIdentity: workspace.category,
                reduceMotion: reduceMotion,
                onCopy: copyGlyph
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func specialSymbolSections(_ sections: [EmojiSection]) -> some View {
        IndexEmojiCollectionView(
            snapshot: .sectioned(sections: sections, tone: tone),
            scrollResetIdentity: workspace.category,
            reduceMotion: reduceMotion,
            onCopy: copyGlyph
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func copyGlyph(_ glyph: String) {
        NSPasteboard.general.clearContents()
        // setString 返回写入是否成功；忽略它会在剪贴板不可写时误报“已复制”。
        guard NSPasteboard.general.setString(glyph, forType: .string) else {
            toastCenter?.show("剪贴板写入失败。", tone: .error)
            return
        }
        toastCenter?.show(ToolFeedbackCopy.copied(glyph: glyph), tone: .success)
    }
}

struct IndexEmojiCategoryBar: View {
    @Binding var selection: String

    var body: some View {
        IndexFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(EmojiCatalog.groups) { group in
                let active = group.name == selection
                IndexBadge(group.name, isSelected: active) {
                    selection = group.name
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
