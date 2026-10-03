import Foundation

extension Array {
    /// 越界下标返回 nil（emoji 网格分页等按位置取值的 UI 使用）。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
