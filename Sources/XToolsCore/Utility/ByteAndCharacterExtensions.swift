import Foundation

extension UInt8 {
    var binaryByteString: String {
        String(unsafeUninitializedCapacity: 8) { buffer in
            for i in 0..<8 {
                buffer[i] = (self & (1 << (7 - i))) != 0 ? UInt8(ascii: "1") : UInt8(ascii: "0")
            }
            return 8
        }
    }
}

extension Character {
    @inlinable
    var isASCIIHexDigit: Bool {
        isHexDigit && isASCII
    }
}
