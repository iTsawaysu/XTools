import Foundation

public enum StringObfuscator {
    public static func obfuscate(
        _ input: String,
        keepFirst: Int,
        keepLast: Int,
        keepSpaces: Bool,
        replacementCharacter: Character
    ) -> String {
        obfuscate(
            input,
            keepFirst: keepFirst,
            keepLast: keepLast,
            keepSpaces: keepSpaces,
            replacementCharacter: replacementCharacter,
            shouldCancel: { false }
        ) ?? ""
    }

    public static func obfuscate(
        _ input: String,
        keepFirst: Int,
        keepLast: Int,
        keepSpaces: Bool,
        replacementCharacter: Character,
        shouldCancel: @escaping @Sendable () -> Bool
    ) -> String? {
        guard !input.isEmpty else {
            return ""
        }

        var characters: [Character] = []
        characters.reserveCapacity(input.utf8.count)
        var iterator = input.makeIterator()
        while true {
            if shouldCancel() {
                return nil
            }

            var appendedCount = 0
            while appendedCount < cancellationCheckStride,
                  let character = iterator.next() {
                characters.append(character)
                appendedCount += 1
            }
            if appendedCount < cancellationCheckStride {
                break
            }
        }

        let length = characters.count
        let firstCount = max(0, min(keepFirst, length))
        let lastCount = max(0, min(keepLast, length - firstCount))
        let lastStart = length - lastCount

        var result = String()
        result.reserveCapacity(input.utf8.count)
        var index = 0
        while index < length {
            if shouldCancel() {
                return nil
            }

            let chunkEnd = min(index + cancellationCheckStride, length)
            var chunk: [Character] = []
            chunk.reserveCapacity(chunkEnd - index)
            while index < chunkEnd {
                let character = characters[index]
                if index < firstCount || index >= lastStart || (keepSpaces && character.isWhitespace) {
                    chunk.append(character)
                } else {
                    chunk.append(replacementCharacter)
                }
                index += 1
            }
            result.append(contentsOf: chunk)
        }

        return shouldCancel() ? nil : result
    }

    private static let cancellationCheckStride = 4_096
}
