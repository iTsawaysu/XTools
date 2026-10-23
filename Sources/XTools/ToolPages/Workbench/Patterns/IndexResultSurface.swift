import AppKit
import SwiftUI
import XToolsDesign

/// One result surface for every tool page.
///
/// The six historical presentations (hero, stats, KV, card list, scrollable
/// KV, hand-rolled) stay behind this facade while pages migrate one family at
/// a time. Callers choose a content shape; the surface owns the empty state,
/// natural-height measurement and result-presence motion.
enum IndexResultContent {
    case list([IndexResultCardItem])
    case kv([IndexResultKVItem])
    case hero(IndexResultHeroItem)
    case stats([IndexResultStatItem])
    case code(text: String, placeholder: String)
}

struct IndexResultKVItem {
    let key: String
    let value: String
    var color: Color? = nil
}

struct IndexResultStatItem {
    let label: String
    let value: String
}

struct IndexResultHeroItem {
    var value: String
    var caption: String? = nil
    var tone: IndexHeroStatTone = .accent
    var copyable = true
    var design: Font.Design = .monospaced
}

struct IndexResultSurface: View {
    let content: IndexResultContent
    var emptyText: String = IndexEmptyStateCopy.noResults
    var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel

    private var emptySurface: some View {
        IndexEmptyState(title: emptyText, density: .output)
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(ToolMetrics.Spacing.md)
    }

    var body: some View {
        switch content {
        case let .list(items):
            if items.isEmpty {
                emptySurface
            } else {
                IndexShortResultCardList(
                    items: items,
                    emptyText: emptyText,
                    workspaceSemantic: workspaceSemantic
                )
            }
        case let .kv(rows):
            if rows.isEmpty {
                emptySurface
            } else {
                IndexShortResultKV(
                    rows: rows.map { ($0.key, $0.value, $0.color) },
                    emptyText: emptyText,
                    workspaceSemantic: workspaceSemantic
                )
            }
        case let .code(text, placeholder):
            IndexOutputSurface(
                text: text,
                placeholder: placeholder,
                lineNumbers: false,
                syntax: nil,
                minHeight: 90,
                embedsFlat: true,
                workspaceSemantic: .naturalHeightShortResultPanel
            )
            .padding(ToolMetrics.Spacing.md)
        case let .stats(items):
            IndexStatGrid(stats: items.map { ($0.label, $0.value) }, valueMotion: .immediate)
                .padding(ToolMetrics.Spacing.sm)
        case let .hero(hero):
            if hero.value.isEmpty {
                emptySurface
            } else {
                IndexWorkspaceResultSurface(workspaceSemantic: workspaceSemantic) {
                    IndexHeroStat(
                        caption: hero.caption,
                        value: hero.value,
                        tone: hero.tone,
                        copyable: hero.copyable,
                        design: hero.design
                    )
                }
            }
        }
    }
}
