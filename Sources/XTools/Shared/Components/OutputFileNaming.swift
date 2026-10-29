import Foundation

/// 输出文件默认命名：源文件名 + 本地时间戳。
///
/// 保存面板的默认名不再使用「compressed / converted」这类通用词：保留来源
/// 文件名便于对照原图，时间戳避免覆盖上一次的输出。Favicon 部署包是例外：
/// `favicon.ico`、`site.webmanifest` 等文件名是站点约定的固定名，不能加时间戳。
enum OutputFileNaming {
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// "1.jpeg" → "1-20261029-113000"；无源名时退回 fallback。
    static func timestampedBase(source: String?, fallback: String, date: Date = Date()) -> String {
        let stem = source
            .map { ($0 as NSString).deletingPathExtension }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let base = stem.isEmpty ? fallback : stem
        return "\(base)-\(timestamp(date))"
    }
}
