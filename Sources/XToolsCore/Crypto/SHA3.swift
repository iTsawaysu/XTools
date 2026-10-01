import Foundation

/// FIPS 202 SHA3-512（Keccak-f[1600]）。项目 target 为 macOS 13：
/// CryptoKit 的 SHA3 要 macOS 15+，CommonCrypto 无 SHA3，因此本地实现。
/// 产品在用的只有 SHA3-512 变体（rate 72 字节、域后缀 0x06、pad10*1），
/// 故不引入多变体参数面，API 对齐同目录 RIPEMD160。
public enum SHA3_512 {
    /// rate = 1600 - 2*512 = 576 位 = 72 字节；输出 64 字节。
    private static let rateBytes = 72
    private static let digestLength = 64

    public static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var state = [UInt64](repeating: 0, count: 25)

        var offset = 0
        while bytes.count - offset >= rateBytes {
            absorb(Array(bytes[offset..<(offset + rateBytes)]), into: &state)
            keccakF1600(&state)
            offset += rateBytes
        }

        // 最后一个不满块补 pad10*1：消息后跟 0x06，末字节再按位或 0x80。
        // 消息长度恰好对齐 rate 时剩余为空，得到独立的填充块。
        let remainder = bytes.count - offset
        var finalBlock = [UInt8](repeating: 0, count: rateBytes)
        finalBlock[0..<remainder] = bytes[offset...]
        finalBlock[remainder] = 0x06
        finalBlock[rateBytes - 1] |= 0x80
        absorb(finalBlock, into: &state)
        keccakF1600(&state)

        // 64 字节 ≤ rate，一次挤出即可；lane 按小端读出（FIPS 202 字节序）。
        var digest = [UInt8]()
        digest.reserveCapacity(digestLength)
        for laneIndex in 0..<(digestLength / 8) {
            var lane = state[laneIndex]
            for _ in 0..<8 {
                digest.append(UInt8(truncatingIfNeeded: lane))
                lane >>= 8
            }
        }
        return digest
    }

    /// rate 块与状态前 9 个 lane 逐位异或（little-endian 组 lane）。
    private static func absorb(_ block: [UInt8], into state: inout [UInt64]) {
        for laneIndex in 0..<(rateBytes / 8) {
            let offset = laneIndex * 8
            state[laneIndex] ^= UInt64(block[offset])
                | (UInt64(block[offset + 1]) << 8)
                | (UInt64(block[offset + 2]) << 16)
                | (UInt64(block[offset + 3]) << 24)
                | (UInt64(block[offset + 4]) << 32)
                | (UInt64(block[offset + 5]) << 40)
                | (UInt64(block[offset + 6]) << 48)
                | (UInt64(block[offset + 7]) << 56)
        }
    }

    /// Keccak-f[1600]：24 轮 θ/ρ/π/χ/ι。lane 下标约定为 x + 5y。
    private static func keccakF1600(_ a: inout [UInt64]) {
        for round in 0..<24 {
            // θ：列奇偶校验，再与相邻列旋转 1 位的结果异或。
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
                for y in 0..<5 {
                    a[x + 5 * y] ^= d
                }
            }

            // ρ + π：B[y][(2x+3y) mod 5] = rot(A[x][y], r[x][y])。
            var b = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[x + 5 * y], rotationOffsets[x + 5 * y])
                }
            }

            // χ：行内非线性组合。
            for x in 0..<5 {
                for y in 0..<5 {
                    a[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }

            // ι：轮常量只进 (0,0) lane。
            a[0] ^= roundConstants[round]
        }
    }

    /// ρ 旋转偏移，按 lane 下标 x + 5y 排列。
    private static let rotationOffsets: [Int] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    private static func rotl(_ value: UInt64, _ count: Int) -> UInt64 {
        count == 0 ? value : ((value << count) | (value >> (64 - count)))
    }
}
