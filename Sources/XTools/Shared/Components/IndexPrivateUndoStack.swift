import AppKit
import Foundation

/// ADR-0022: one editable surface → one private `UndoManager` that dies with it.
///
/// Window-shared undo is the source of the ⌘Z use-after-free: selector-based
/// undo actions do not retain their text targets, and SwiftUI frequently tears
/// those views down while the shared stack still holds the action. Vending a
/// per-surface manager keeps history co-located with the editor that owns it.
@MainActor
final class IndexPrivateUndoStack {
    let manager = UndoManager()

    /// `levels == nil` keeps the fresh-`UndoManager` default (`0` = unlimited).
    /// A concrete policy value is clamped to at least 1 so a zero-cap cannot
    /// silently disable undo.
    func configureLevels(_ levels: Int?) {
        manager.levelsOfUndo = levels.map { max(1, $0) } ?? 0
    }
}
