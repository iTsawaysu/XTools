import Foundation

/// The compression rounds follow the published RIPEMD-160 specification and
/// are protected by standard vectors.
public enum RIPEMD160 {
    public static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var message = bytes
        let msgBitLen = UInt64(bytes.count) * 8

        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }
        for i in 0..<8 {
            message.append(UInt8((msgBitLen >> (i * 8)) & 0xFF))
        }

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                x[i] = UInt32(message[offset])
                    | (UInt32(message[offset + 1]) << 8)
                    | (UInt32(message[offset + 2]) << 16)
                    | (UInt32(message[offset + 3]) << 24)
            }

            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            for j in 0..<80 {
                let (f, k, r) = Self.leftParams(j)
                let t = Self.rotl(al &+ f(bl, cl, dl) &+ x[r] &+ k, Self.s_left[j]) &+ el
                al = el
                el = dl
                dl = Self.rotl(cl, 10)
                cl = bl
                bl = t
            }

            for j in 0..<80 {
                let (f, k, r) = Self.rightParams(j)
                let t = Self.rotl(ar &+ f(br, cr, dr) &+ x[r] &+ k, Self.s_right[j]) &+ er
                ar = er
                er = dr
                dr = Self.rotl(cr, 10)
                cr = br
                br = t
            }

            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }

        var result = [UInt8]()
        for h in [h0, h1, h2, h3, h4] {
            result.append(UInt8(h & 0xFF))
            result.append(UInt8((h >> 8) & 0xFF))
            result.append(UInt8((h >> 16) & 0xFF))
            result.append(UInt8((h >> 24) & 0xFF))
        }
        return result
    }

    private static func rotl(_ x: UInt32, _ n: Int) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    private static func leftParams(_ j: Int) -> ((UInt32, UInt32, UInt32) -> UInt32, UInt32, Int) {
        switch j {
        case 0..<16:
            return ({ $0 ^ $1 ^ $2 }, 0x00000000, r_left[j])
        case 16..<32:
            return ({ ($0 & $1) | (~$0 & $2) }, 0x5A827999, r_left[j])
        case 32..<48:
            return ({ ($0 | ~$1) ^ $2 }, 0x6ED9EBA1, r_left[j])
        case 48..<64:
            return ({ ($0 & $2) | ($1 & ~$2) }, 0x8F1BBCDC, r_left[j])
        default:
            return ({ $0 ^ ($1 | ~$2) }, 0xA953FD4E, r_left[j])
        }
    }

    private static func rightParams(_ j: Int) -> ((UInt32, UInt32, UInt32) -> UInt32, UInt32, Int) {
        switch j {
        case 0..<16:
            return ({ $0 ^ ($1 | ~$2) }, 0x50A28BE6, r_right[j])
        case 16..<32:
            return ({ ($0 & $2) | ($1 & ~$2) }, 0x5C4DD124, r_right[j])
        case 32..<48:
            return ({ ($0 | ~$1) ^ $2 }, 0x6D703EF3, r_right[j])
        case 48..<64:
            return ({ ($0 & $1) | (~$0 & $2) }, 0x7A6D76E9, r_right[j])
        default:
            return ({ $0 ^ $1 ^ $2 }, 0x00000000, r_right[j])
        }
    }

    private static let r_left = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
    ]

    private static let r_right = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
    ]

    private static let s_left = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
    ]

    private static let s_right = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
    ]
}
