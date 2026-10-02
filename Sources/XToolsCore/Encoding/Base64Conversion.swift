import Foundation

/// Shared Base64 helpers for text, binary data, Data URLs, and Base64URL segments.
public enum Base64Conversion {
    public enum ConversionError: LocalizedError, Equatable {
        case invalidBase64
        case invalidDataURL
        case invalidUTF8

        public var errorDescription: String? {
            switch self {
            case .invalidBase64:
                return "输入不是有效的 Base64。"
            case .invalidDataURL:
                return "输入不是有效的 Base64 Data URL。"
            case .invalidUTF8:
                return "Base64 内容不是 UTF-8 文本。"
            }
        }
    }

    public struct DataURLPayload: Equatable, Sendable {
        public let mimeType: String
        public let base64Payload: String

        public init(mimeType: String, base64Payload: String) {
            self.mimeType = mimeType
            self.base64Payload = base64Payload
        }
    }

    public struct FileType: Equatable, Sendable {
        public let mimeType: String
        public let fileExtension: String

        public init(mimeType: String, fileExtension: String) {
            self.mimeType = mimeType
            self.fileExtension = fileExtension
        }
    }

    public struct FilePayload: Equatable, Sendable {
        public let data: Data
        public let mimeType: String
        public let fileExtension: String

        public init(data: Data, mimeType: String, fileExtension: String) {
            self.data = data
            self.mimeType = mimeType
            self.fileExtension = fileExtension
        }
    }

    public enum FileOutputMode: String, Equatable, Sendable {
        case base64
        case dataURL
    }

    public struct EncodedFileOutputPreview: Equatable, Sendable {
        public let mode: FileOutputMode
        public let mimeType: String
        public let sourceByteCount: Int
        public let characterCount: Int
        public let visibleText: String
        public let isTruncated: Bool
        public let prefixCharacterCount: Int
        public let suffixCharacterCount: Int

        public init(
            mode: FileOutputMode,
            mimeType: String,
            sourceByteCount: Int,
            characterCount: Int,
            visibleText: String,
            isTruncated: Bool,
            prefixCharacterCount: Int,
            suffixCharacterCount: Int
        ) {
            self.mode = mode
            self.mimeType = mimeType
            self.sourceByteCount = sourceByteCount
            self.characterCount = characterCount
            self.visibleText = visibleText
            self.isTruncated = isTruncated
            self.prefixCharacterCount = prefixCharacterCount
            self.suffixCharacterCount = suffixCharacterCount
        }
    }

    public static let defaultFileOutputInlineCharacterLimit = 64_000
    public static let defaultFileOutputFragmentCharacterLimit = 1_400

    public static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    public static func decode(_ value: String) throws -> String {
        let data = try decodeData(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConversionError.invalidUTF8
        }
        return text
    }

    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    public static func dataURL(for data: Data, mimeType: String = "application/octet-stream") -> String {
        "data:\(mimeType);base64,\(encode(data))"
    }

    public static func encodedOutput(
        for data: Data,
        mimeType: String = "application/octet-stream",
        mode: FileOutputMode
    ) -> String {
        switch mode {
        case .base64:
            return encode(data)
        case .dataURL:
            return dataURL(for: data, mimeType: normalizedMIMEType(mimeType))
        }
    }

    public static func encodedOutputCharacterCount(
        byteCount: Int,
        mimeType: String = "application/octet-stream",
        mode: FileOutputMode
    ) -> Int {
        let base64Length = ((max(0, byteCount) + 2) / 3) * 4

        switch mode {
        case .base64:
            return base64Length
        case .dataURL:
            return dataURLPrefix(mimeType: normalizedMIMEType(mimeType)).count + base64Length
        }
    }

    public static func decodedByteCountUpperBound(forBase64CharacterCount characterCount: Int) -> Int {
        ((max(0, characterCount) + 3) / 4) * 3
    }

    public static func decodedByteCountUpperBound(forBase64Payload payload: String) -> Int {
        let characterCount = payload.reduce(0) { count, character in
            character.isWhitespace ? count : count + 1
        }
        var paddingCount = 0
        for character in payload.reversed() {
            if character.isWhitespace {
                continue
            }
            guard character == "=", paddingCount < 2 else {
                break
            }
            paddingCount += 1
        }

        return max(0, decodedByteCountUpperBound(forBase64CharacterCount: characterCount) - min(paddingCount, 2))
    }

    public static func encodedOutputPreview(
        for data: Data,
        mimeType: String = "application/octet-stream",
        mode: FileOutputMode,
        inlineCharacterLimit: Int = defaultFileOutputInlineCharacterLimit,
        fragmentCharacterLimit: Int = defaultFileOutputFragmentCharacterLimit
    ) -> EncodedFileOutputPreview {
        let normalizedMimeType = normalizedMIMEType(mimeType)
        let characterCount = encodedOutputCharacterCount(
            byteCount: data.count,
            mimeType: normalizedMimeType,
            mode: mode
        )
        let inlineLimit = max(0, inlineCharacterLimit)
        let fragmentLimit = max(80, fragmentCharacterLimit)

        if characterCount <= inlineLimit {
            let fullOutput = encodedOutput(for: data, mimeType: normalizedMimeType, mode: mode)
            return EncodedFileOutputPreview(
                mode: mode,
                mimeType: normalizedMimeType,
                sourceByteCount: data.count,
                characterCount: characterCount,
                visibleText: fullOutput,
                isTruncated: false,
                prefixCharacterCount: fullOutput.count,
                suffixCharacterCount: 0
            )
        }

        let prefix = encodedOutputPrefixFragment(
            for: data,
            mimeType: normalizedMimeType,
            mode: mode,
            characterLimit: fragmentLimit
        )
        let suffix = encodedOutputSuffixFragment(
            for: data,
            mode: mode,
            characterLimit: fragmentLimit
        )
        let omittedCount = max(0, characterCount - prefix.count - suffix.count)
        let visibleText = """
        \(prefix)

        [预览已截断，中间省略 \(omittedCount) 字符。复制或保存可获得完整输出。]

        \(suffix)
        """

        return EncodedFileOutputPreview(
            mode: mode,
            mimeType: normalizedMimeType,
            sourceByteCount: data.count,
            characterCount: characterCount,
            visibleText: visibleText,
            isTruncated: true,
            prefixCharacterCount: prefix.count,
            suffixCharacterCount: suffix.count
        )
    }

    public static func parseDataURL(_ value: String) throws -> DataURLPayload {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let commaIndex = trimmed.firstIndex(of: ",") else {
            throw ConversionError.invalidDataURL
        }

        let metadata = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<commaIndex])
        let payload = String(trimmed[trimmed.index(after: commaIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadataParts = metadata
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let mediaTypeHead = metadataParts.first ?? ""
        var mediaTypeParameters: [String] = []
        var isBase64 = false

        for part in metadataParts.dropFirst() {
            if part == "base64" {
                isBase64 = true
            } else if !part.isEmpty {
                mediaTypeParameters.append(part)
            }
        }

        guard isBase64 else {
            throw ConversionError.invalidDataURL
        }

        let normalizedMimeType = if mediaTypeHead.isEmpty {
            mediaTypeParameters.isEmpty
                ? "text/plain;charset=us-ascii"
                : "text/plain;\(mediaTypeParameters.joined(separator: ";"))"
        } else {
            ([mediaTypeHead] + mediaTypeParameters).joined(separator: ";")
        }

        return DataURLPayload(
            mimeType: normalizedMimeType,
            base64Payload: payload
        )
    }

    public static func decodeFilePayload(_ value: String) throws -> FilePayload {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataURL = trimmed.lowercased().hasPrefix("data:") ? try parseDataURL(trimmed) : nil
        let data = try decodeData(dataURL?.base64Payload ?? trimmed)
        let resolvedType = dataURL.flatMap { fileType(forMIMEType: $0.mimeType) } ?? inferredFileType(for: data)
        let mimeType = dataURL?.mimeType ?? resolvedType?.mimeType ?? "application/octet-stream"
        let fileExtension = resolvedType?.fileExtension ?? "bin"

        return FilePayload(data: data, mimeType: mimeType, fileExtension: fileExtension)
    }

    public static func inferredFileType(for data: Data) -> FileType? {
        guard let match = BinarySignatures.match(in: data) else {
            return nil
        }

        switch match {
        case .png, .jpeg, .gif, .pdf:
            return FileType(
                mimeType: BinarySignatures.mimeType(for: match),
                fileExtension: BinarySignatures.fileExtension(for: match)
            )
        case .zip, .gzip:
            // Base64 file helper historically only sniffs image/PDF payloads.
            return nil
        }
    }

    public static func fileType(forMIMEType mimeType: String) -> FileType? {
        let normalizedType = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""

        switch normalizedType {
        case "image/png":
            return FileType(mimeType: "image/png", fileExtension: "png")
        case "image/jpeg", "image/jpg":
            return FileType(mimeType: "image/jpeg", fileExtension: "jpg")
        case "image/gif":
            return FileType(mimeType: "image/gif", fileExtension: "gif")
        case "application/pdf":
            return FileType(mimeType: "application/pdf", fileExtension: "pdf")
        case "text/plain":
            return FileType(mimeType: "text/plain", fileExtension: "txt")
        case "application/json":
            return FileType(mimeType: "application/json", fileExtension: "json")
        default:
            return nil
        }
    }

    public static func normalizedFileName(_ fileName: String, fileExtension: String) -> String {
        let fallbackName = "download"
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastPathComponent = URL(fileURLWithPath: trimmedName).lastPathComponent
        let safeName = trimmedName.isEmpty || lastPathComponent.isEmpty ? fallbackName : lastPathComponent
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))

        guard !ext.isEmpty else {
            return safeName
        }

        if !URL(fileURLWithPath: safeName).pathExtension.isEmpty {
            return safeName
        }

        return "\(safeName).\(ext)"
    }

    public static func decodeData(_ value: String) throws -> Data {
        // 宽容解码（对齐成熟工具的现实输入）：去空白 + base64url 字母表
        // 归一（-_ → +/）+ 尾部填充剥离后按长度规范补 `=`。
        // 真实世界的 Base64——API key、JWT、openssl 输出——普遍不带填充或
        // 使用 base64url 字母表；长度余 1（不可能的 Base64 长度）与字母表
        // 外字符、串中填充仍拒绝。纯字母表的英文句子现在会解出乱码而非
        // 报错（`not base64` 9 字符余 1 仍拒绝），取舍与语义由
        // Base64ConversionTests 锁定。
        guard let payload = normalizedBase64Payload(value) else {
            throw ConversionError.invalidBase64
        }
        if payload.isEmpty {
            return Data()
        }
        guard payload.count % 4 != 1,
              let data = Data(base64Encoded: paddedBase64(payload)) else {
            throw ConversionError.invalidBase64
        }
        return data
    }

    /// 归一：Unicode 级去空白（折行/缩进/全角空格），再单趟完成
    /// base64url 字母表映射、校验与尾部填充剥离。返回 nil 表示存在
    /// 字母表外字符或串中填充。
    static func normalizedBase64Payload(_ value: String) -> [UInt8]? {
        let stripped = value.filter { !$0.isWhitespace }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(stripped.utf8.count)
        for byte in stripped.utf8 {
            let mapped: UInt8
            switch byte {
            case UInt8(ascii: "-"):
                mapped = UInt8(ascii: "+")
            case UInt8(ascii: "_"):
                mapped = UInt8(ascii: "/")
            default:
                mapped = byte
            }
            guard isBase64Alphabet(mapped) || mapped == UInt8(ascii: "=") else {
                return nil
            }
            bytes.append(mapped)
        }
        // 剥离尾部填充；若剥离后仍有 '='（串中填充），视为非法。
        var endIndex = bytes.count
        while endIndex > 0, bytes[endIndex - 1] == UInt8(ascii: "=") {
            endIndex -= 1
        }
        guard !bytes[..<endIndex].contains(UInt8(ascii: "=")) else {
            return nil
        }
        bytes.removeSubrange(endIndex...)
        return bytes
    }

    /// 规范补齐填充（调用前保证 count % 4 != 1）。载荷是 ASCII 字母表
    /// 字节，UTF-8 解码无损。
    static func paddedBase64(_ payload: [UInt8]) -> String {
        let padding = (4 - payload.count % 4) % 4
        return String(decoding: payload, as: UTF8.self)
            + String(repeating: "=", count: padding)
    }

    public static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decodeBase64URLData(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        return try decodeData(base64)
    }

    private static func normalizedMIMEType(_ mimeType: String) -> String {
        let trimmed = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "application/octet-stream" : trimmed
    }

    private static func dataURLPrefix(mimeType: String) -> String {
        "data:\(mimeType);base64,"
    }

    private static func encodedOutputPrefixFragment(
        for data: Data,
        mimeType: String,
        mode: FileOutputMode,
        characterLimit: Int
    ) -> String {
        let prefix = mode == .dataURL ? dataURLPrefix(mimeType: mimeType) : ""
        let remainingCharacterLimit = max(4, characterLimit - prefix.count)
        let byteCount = base64ByteWindow(forCharacterLimit: remainingCharacterLimit)
        let alignedByteCount = min(data.count, byteCount - (byteCount % 3))
        let base64Prefix = alignedByteCount > 0
            ? Data(data.prefix(alignedByteCount)).base64EncodedString()
            : ""

        return String((prefix + base64Prefix).prefix(characterLimit))
    }

    private static func encodedOutputSuffixFragment(
        for data: Data,
        mode _: FileOutputMode,
        characterLimit: Int
    ) -> String {
        guard !data.isEmpty else { return "" }

        let byteWindow = min(data.count, base64ByteWindow(forCharacterLimit: characterLimit) + 3)
        let rawStartIndex = max(0, data.count - byteWindow)
        let alignedStartIndex = rawStartIndex - (rawStartIndex % 3)
        let suffixData = Data(data[alignedStartIndex..<data.count])
        return String(suffixData.base64EncodedString().suffix(characterLimit))
    }

    private static func base64ByteWindow(forCharacterLimit characterLimit: Int) -> Int {
        max(3, ((max(4, characterLimit) + 3) / 4) * 3)
    }

    private static func isBase64Alphabet(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "+"),
             UInt8(ascii: "/"):
            return true
        default:
            return false
        }
    }
}
