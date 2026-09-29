import Foundation
// Yams exposes only recursive composition publicly. Its existing CYaml module
// supplies the public libyaml event API needed to bound work before composition.
internal import CYaml

/// Uses the same libyaml event grammar as Yams, before Yams recursively composes
/// nodes. It neither guesses YAML structure from indentation nor expands aliases.
enum YAMLProcessingPreflight {
    static let maximumDepth = 64
    static let maximumKeyNodes = 1_000_000
    @TaskLocal static var maximumKeyBytes = StructuredTextExecution.maximumOutputBytes

    struct Summary {
        var hasAliases = false
        var outputUpperBound = 0
    }

    private struct Shape {
        var height = 0
        var nodes = 1
        var hashBytes = 0
    }

    private struct Frame {
        let anchor: String?
        let mapping: Bool
        var children = 0
        var shape = Shape(height: 1)
    }

    static func inspect(_ input: String, indent: Int = 2) throws -> Summary {
        try StructuredTextExecution.validateInput(input, format: "YAML")
        let data = Data(input.utf8)
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) != 0 else {
            throw StructuredTextResourceError(format: "YAML", reason: "解析资源不足")
        }
        defer { yaml_parser_delete(&parser) }
        var summary = Summary()
        var stack: [Frame] = []
        var anchors: [String: Shape] = [:]
        var mappingKeyNodes = 0
        var mappingKeyBytes = 0
        var expandedTagBytes = 0
        // Token contents, tags and directives are bounded by the source. Each
        // event adds structural punctuation/indent; scalars add escaped bytes.
        summary.outputUpperBound = data.count
        let reader = InputReader(data: data)
        defer { withExtendedLifetime(reader) {} }
        yaml_parser_set_input(&parser, { context, buffer, size, count in
            guard let context, let buffer, let count else { return 0 }
            return Unmanaged<InputReader>.fromOpaque(context).takeUnretainedValue()
                .read(into: buffer, capacity: size, count: count)
        }, Unmanaged.passUnretained(reader).toOpaque())
        while true {
                try StructuredTextExecution.checkCancellation()
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) != 0 else {
                    if let interruption = reader.interruption { throw interruption }
                    // Let Yams translate malformed syntax using the existing
                    // error/mark/context contract. No unsafe tree was built here.
                    return summary
                }
                defer { yaml_event_delete(&event) }
                var completed: Shape?
                var anchor: String?
                switch event.type {
                case YAML_DOCUMENT_START_EVENT:
                    anchors.removeAll(keepingCapacity: true)
                    summary.outputUpperBound += 16
                case YAML_MAPPING_START_EVENT, YAML_SEQUENCE_START_EVENT:
                    guard stack.count < maximumDepth else { throw depthError() }
                    anchor = string(event.type == YAML_MAPPING_START_EVENT
                        ? event.data.mapping_start.anchor : event.data.sequence_start.anchor)
                    let tag = event.type == YAML_MAPPING_START_EVENT
                        ? event.data.mapping_start.tag : event.data.sequence_start.tag
                    let tagBytes = hashTagBytes(tag)
                    expandedTagBytes += tagBytes
                    summary.outputUpperBound += tagBytes
                    stack.append(Frame(anchor: anchor, mapping: event.type == YAML_MAPPING_START_EVENT,
                        shape: Shape(height: 1, hashBytes: tagBytes)))
                case YAML_MAPPING_END_EVENT, YAML_SEQUENCE_END_EVENT:
                    guard let frame = stack.popLast() else { continue }
                    completed = frame.shape
                    anchor = frame.anchor
                case YAML_ALIAS_EVENT:
                    summary.hasAliases = true
                    completed = string(event.data.alias.anchor).flatMap { anchors[$0] } ?? Shape()
                case YAML_SCALAR_EVENT:
                    let tagBytes = hashTagBytes(event.data.scalar.tag)
                    expandedTagBytes += tagBytes
                    summary.outputUpperBound += tagBytes
                    completed = Shape(hashBytes: event.data.scalar.length + tagBytes)
                    anchor = string(event.data.scalar.anchor)
                    let value = String(decoding: UnsafeBufferPointer(
                        start: event.data.scalar.value, count: event.data.scalar.length
                    ), as: UTF8.self)
                    // libyaml's non-Unicode output escapes scalars with at most
                    // \\Uxxxxxxxx; line-wrapping indentation is charged per scalar
                    // byte, giving a conservative bound without output allocation.
                    for (offset, scalar) in value.unicodeScalars.enumerated() {
                        try StructuredTextExecution.checkpoint(offset)
                        switch scalar.value {
                        case 0x20...0x7E: summary.outputUpperBound += scalar == "\\" || scalar == "\"" ? 2 : 1
                        case 0x0A, 0x0D: summary.outputUpperBound += 2 + (stack.count + 1) * max(2, min(indent, 9))
                        case 0...0xFF: summary.outputUpperBound += 4
                        case 0...0xFFFF: summary.outputUpperBound += 6
                        default: summary.outputUpperBound += 10
                        }
                    }
                case YAML_STREAM_END_EVENT:
                    return summary
                default:
                    break
                }
                guard expandedTagBytes <= StructuredTextExecution.maximumOutputBytes else {
                    throw StructuredTextResourceError(format: "YAML", reason: "标签展开成本超过处理容量上限")
                }
                summary.outputUpperBound += 16 + (stack.count + 1) * max(2, min(indent, 9))
                if let completed {
                    guard completed.height + stack.count <= maximumDepth else { throw depthError() }
                    if let anchor { anchors[anchor] = completed }
                    if !stack.isEmpty {
                        let index = stack.count - 1
                        // Yams hashes mapping keys recursively for duplicate-key
                        // validation. Shared aliases in values are not expanded
                        // and must not be rejected merely for large reuse counts.
                        if stack[index].mapping, stack[index].children.isMultiple(of: 2) {
                            guard completed.nodes <= maximumKeyNodes - mappingKeyNodes,
                                  completed.hashBytes <= maximumKeyBytes - mappingKeyBytes else {
                                throw StructuredTextResourceError(format: "YAML", reason: "映射键累计解析成本超过处理容量上限")
                            }
                            mappingKeyNodes += completed.nodes
                            mappingKeyBytes += completed.hashBytes
                        }
                        stack[index].children += 1
                        stack[index].shape.height = max(stack[index].shape.height, completed.height + 1)
                        stack[index].shape.nodes = min(maximumKeyNodes + 1, stack[index].shape.nodes + completed.nodes)
                        stack[index].shape.hashBytes = min(maximumKeyBytes + 1,
                            stack[index].shape.hashBytes + completed.hashBytes)
                    }
                }
        }
    }

    private final class InputReader {
        let data: Data
        var offset = 0
        var interruption: Error?

        init(data: Data) { self.data = data }

        func read(into buffer: UnsafeMutablePointer<UInt8>, capacity: Int, count: UnsafeMutablePointer<Int>) -> Int32 {
            do {
                try StructuredTextExecution.checkCancellation()
                let amount = min(capacity, min(16_384, data.count - offset))
                data.copyBytes(to: UnsafeMutableBufferPointer(start: buffer, count: amount), from: offset..<(offset + amount))
                offset += amount
                count.pointee = amount
                return 1
            } catch {
                interruption = error
                count.pointee = 0
                return 0
            }
        }
    }

    private static func hashTagBytes(_ tag: UnsafePointer<UInt8>?) -> Int {
        guard let tag else { return 32 } // longest built-in resolved tag fits
        return max(32, Int(strlen(UnsafeRawPointer(tag).assumingMemoryBound(to: CChar.self))))
    }

    private static func string(_ value: UnsafePointer<UInt8>?) -> String? {
        value.map { String(cString: $0) }
    }

    private static func depthError() -> StructuredTextResourceError {
        StructuredTextResourceError(format: "YAML", reason: "嵌套或别名引用深度超过 64 层处理上限")
    }
}
