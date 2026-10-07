import Foundation
import Yams

extension DockerComposeToRunService {
    static func scalarString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func stringList(_ value: Any?) -> [String]? {
        switch value {
        case let array as [Any]:
            let items = array.compactMap(scalarString)
            return items.isEmpty && !array.isEmpty ? nil : items
        case let string as String:
            return [string]
        default:
            return nil
        }
    }

    static func strictStringList(
        _ value: Any?,
        path: String,
        skipped: inout [String]
    ) -> [String]? {
        guard value != nil else { return nil }
        if let string = value as? String { return [string] }
        guard let array = value as? [Any] else {
            skipped.append("\(path)(结构无法映射)")
            return nil
        }
        let items = array.compactMap(scalarString)
        guard items.count == array.count else {
            skipped.append("\(path)(结构无法映射)")
            return nil
        }
        return items
    }

}
