import Foundation

/// RFC 4503（Rabbit 流密码，eSTREAM）实现，结构与命名对齐同目录 RIPEMD160。
/// 仅用于 TextEncryptionService 的传统兼容格式：现有历史密文依赖该算法输出，
/// 因此本实现与被移除的 CryptoSwift 版本逐字节等价，并受 RFC 4503 官方向量与
/// 迁移期固化的金标双重保护。
/// 流密码加解密同为密钥流异或，encrypt/decrypt 共用同一路径。
public struct RabbitCipher {
    public enum Error: Swift.Error {
        case invalidKeyOrIV
    }

    /// 与 TextEncryptionService 传统派生路径（EVP_BytesToKey）的固定长度一致：
    /// Rabbit 恒为 16 字节 key + 8 字节 IV。
    public static let keySize = 16
    public static let ivSize = 8
    /// 密钥流以 128 位（16 字节）块产出。
    private static let blockSize = 16

    // RFC 4503 的递增常量 a_j（j=0..7）。
    private static let a: [UInt32] = [
        0x4D34D34D, 0xD34D34D3, 0x34D34D34, 0x4D34D34D,
        0xD34D34D3, 0x34D34D34, 0x4D34D34D, 0xD34D34D3,
    ]

    private var x: [UInt32]
    private var c: [UInt32]
    /// 计数器进位位须跨迭代保留（RFC 4503 计数器系统）。
    private var carryBit: UInt32

    /// key setup（RFC 4503 2.1）+ IV setup（RFC 4503 2.4）。
    public init(key: [UInt8], iv: [UInt8]) throws {
        guard key.count == Self.keySize, iv.count == Self.ivSize else {
            throw Error.invalidKeyOrIV
        }

        // 子密钥 k_j = key[14-2j]<<8 | key[15-2j]（k[127..0] 按 16 位小端切分）。
        var k = [UInt32](repeating: 0, count: 8)
        for j in 0..<8 {
            k[j] = UInt32(key[15 - 2 * j]) | (UInt32(key[14 - 2 * j]) << 8)
        }

        // 初始化状态与计数器：奇偶下标使用不同的子密钥拼装公式。
        var x = [UInt32](repeating: 0, count: 8)
        var c = [UInt32](repeating: 0, count: 8)
        for j in 0..<8 {
            if j % 2 == 0 {
                x[j] = (k[(j + 1) % 8] << 16) | k[j]
                c[j] = (k[(j + 4) % 8] << 16) | k[(j + 5) % 8]
            } else {
                x[j] = (k[(j + 5) % 8] << 16) | k[(j + 4) % 8]
                c[j] = (k[j] << 16) | k[(j + 1) % 8]
            }
        }
        var carry: UInt32 = 0

        // key setup 迭代系统四次，再用 x[j+4] 重置计数器。
        for _ in 0..<4 {
            Self.nextState(x: &x, c: &c, carry: &carry)
        }
        for j in 0..<8 {
            c[j] ^= x[(j + 4) % 8]
        }

        // IV 按位段交叉混入计数器（C0/C4←IV[31..0]，C1/C5←IV[63..48]||IV[31..16]，
        // C2/C6←IV[63..32]，C3/C7←IV[47..32]||IV[15..0]），再迭代四次。
        let iv0 = Self.bigEndian(iv[4], iv[5], iv[6], iv[7])
        let iv1 = Self.bigEndian(iv[0], iv[1], iv[4], iv[5])
        let iv2 = Self.bigEndian(iv[0], iv[1], iv[2], iv[3])
        let iv3 = Self.bigEndian(iv[2], iv[3], iv[6], iv[7])
        c[0] ^= iv0
        c[1] ^= iv1
        c[2] ^= iv2
        c[3] ^= iv3
        c[4] ^= iv0
        c[5] ^= iv1
        c[6] ^= iv2
        c[7] ^= iv3
        for _ in 0..<4 {
            Self.nextState(x: &x, c: &c, carry: &carry)
        }

        self.x = x
        self.c = c
        self.carryBit = carry
    }

    /// 加密：明文与密钥流逐字节异或。每次调用从块边界重新消费密钥流，
    /// 状态以值拷贝推进，同一实例重复加密总是得到相同结果。
    public func encrypt(_ bytes: [UInt8]) -> [UInt8] {
        var x = self.x
        var c = self.c
        var carry = self.carryBit

        var output = [UInt8]()
        output.reserveCapacity(bytes.count)

        var keystream = Self.nextBlock(x: &x, c: &c, carry: &carry)
        var keystreamIndex = 0
        for byte in bytes {
            if keystreamIndex == Self.blockSize {
                keystream = Self.nextBlock(x: &x, c: &c, carry: &carry)
                keystreamIndex = 0
            }
            output.append(byte ^ keystream[keystreamIndex])
            keystreamIndex += 1
        }
        return output
    }

    /// 解密与加密同构（异或自反）。
    public func decrypt(_ bytes: [UInt8]) -> [UInt8] {
        encrypt(bytes)
    }

    /// 计数器先递增（进位跨迭代保留），再按 g_j = (x_j + c_j)^2 折叠，
    /// 组合出下一状态（RFC 4503 2.3）。
    private static func nextState(x: inout [UInt32], c: inout [UInt32], carry: inout UInt32) {
        var carryBit = carry
        for j in 0..<8 {
            let previous = c[j]
            c[j] = previous &+ a[j] &+ carryBit
            carryBit = previous > c[j] ? 1 : 0
        }
        carry = carryBit

        var g = [UInt32](repeating: 0, count: 8)
        for j in 0..<8 {
            let sum = x[j] &+ c[j]
            let square = UInt64(sum) * UInt64(sum)
            g[j] = UInt32(truncatingIfNeeded: square ^ (square >> 32))
        }

        x = [
            g[0] &+ rotl(g[7], 16) &+ rotl(g[6], 16),
            g[1] &+ rotl(g[0], 8) &+ g[7],
            g[2] &+ rotl(g[1], 16) &+ rotl(g[0], 16),
            g[3] &+ rotl(g[2], 8) &+ g[1],
            g[4] &+ rotl(g[3], 16) &+ rotl(g[2], 16),
            g[5] &+ rotl(g[4], 8) &+ g[3],
            g[6] &+ rotl(g[5], 16) &+ rotl(g[4], 16),
            g[7] &+ rotl(g[6], 8) &+ g[5],
        ]
    }

    /// 推进一次系统迭代并抽取 16 字节密钥流块。
    private static func nextBlock(x: inout [UInt32], c: inout [UInt32], carry: inout UInt32) -> [UInt8] {
        nextState(x: &x, c: &c, carry: &carry)
        return extractBlock(x)
    }

    /// RFC 4503 的抽取式：S[15..0]=X0[15..0]^X5[31..16] 等，全部 8 个 16 位字
    /// 按大端写入字节流（即 S[127..112] 先出）。
    private static func extractBlock(_ x: [UInt32]) -> [UInt8] {
        let words: [UInt16] = [
            UInt16(truncatingIfNeeded: x[6] >> 16) ^ UInt16(truncatingIfNeeded: x[1]),
            UInt16(truncatingIfNeeded: x[6]) ^ UInt16(truncatingIfNeeded: x[3] >> 16),
            UInt16(truncatingIfNeeded: x[4] >> 16) ^ UInt16(truncatingIfNeeded: x[7]),
            UInt16(truncatingIfNeeded: x[4]) ^ UInt16(truncatingIfNeeded: x[1] >> 16),
            UInt16(truncatingIfNeeded: x[2] >> 16) ^ UInt16(truncatingIfNeeded: x[5]),
            UInt16(truncatingIfNeeded: x[2]) ^ UInt16(truncatingIfNeeded: x[7] >> 16),
            UInt16(truncatingIfNeeded: x[0] >> 16) ^ UInt16(truncatingIfNeeded: x[3]),
            UInt16(truncatingIfNeeded: x[0]) ^ UInt16(truncatingIfNeeded: x[5] >> 16),
        ]

        var block = [UInt8]()
        block.reserveCapacity(blockSize)
        for word in words {
            block.append(UInt8(truncatingIfNeeded: word >> 8))
            block.append(UInt8(truncatingIfNeeded: word))
        }
        return block
    }

    private static func bigEndian(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
        (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
    }

    private static func rotl(_ value: UInt32, _ count: Int) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
