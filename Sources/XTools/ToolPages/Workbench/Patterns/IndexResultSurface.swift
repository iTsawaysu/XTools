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
}

struct IndexResultKVItem {
    let key: String
    let value: String
    var color: Color? = nil
}

struct IndexResultHeroItem {
    var value: String
    var caption: String? = nil
    var tone: IndexHeroStatTone = .accent
    var copyable = true
}

struct IndexResultSurface: View {
    let content: IndexResultContent
    var emptyText: String = IndexEmptyStateCopy.noResults
    var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel

    var body: some View {
        switch content {
        case let .list(items):
            IndexShortResultCardList(
                items: items,
                emptyText: emptyText,
                workspaceSemantic: workspaceSemantic
            )
        case let .kv(rows):
            IndexShortResultKV(
                rows: rows.map { ($0.key, $0.value, $0.color) },
                emptyText: emptyText,
                workspaceSemantic: workspaceSemantic
            )
        case let .hero(hero):
            IndexWorkspaceResultSurface(workspaceSemantic: workspaceSemantic) {
                IndexHeroStat(
                    caption: hero.caption,
                    value: hero.value,
                    tone: hero.tone,
                    copyable: hero.copyable
                )
            }
        }
    }
}
