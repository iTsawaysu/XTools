import Foundation

/// Canonical user-facing feedback copy for success actions.
///
/// Every copy/save success toast and done-state label must pull from this
/// table so the same action never ships two phrasings. Failures do not live
/// here — they route through workspace diagnostics, not toasts.
enum ToolFeedbackCopy {
    /// Clipboard write succeeded (button done-state and toast).
    static let copied = "已复制"
    /// Clipboard write succeeded, identity variant for glyph-like payloads.
    static func copied(glyph: String) -> String {
        "已复制 \(glyph)"
    }
    /// Clipboard write succeeded for a whole generated batch (e.g. 全部复制).
    static func copiedAll(noun: String) -> String {
        "已复制全部 \(noun)"
    }
    /// A single file was saved with a known name.
    static func saved(fileName: String) -> String {
        "已保存 · \(fileName)"
    }
    /// Text-output save (workbench markdown, Base64 encoded text).
    static let savedOutput = "输出已保存"
    /// File save whose handler does not surface the chosen name.
    static let savedFile = "文件已保存"
    /// A batch of files was saved.
    static func saved(count: Int, noun: String = "文件") -> String {
        "已保存 \(count) 个\(noun)"
    }
}
