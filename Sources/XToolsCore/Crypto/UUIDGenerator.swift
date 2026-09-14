import Foundation

public enum UUIDGenerationVersion: String, CaseIterable, Equatable, Sendable {
    case v4
    case v7
}

public struct UUIDGenerator {
    public typealias MillisecondClock = () -> Int64
    public typealias ByteSource = SecureRandomBytes.Source

    public enum Failure: LocalizedError, Equatable, Sendable {
        case randomSourceUnavailable
        case timestampOutOfRange

        public var errorDescription: String? {
            switch self {
            case .randomSourceUnavailable:
                return "无法访问系统随机数生成器。"
            case .timestampOutOfRange:
                return "当前时间超出 UUID v7 支持的时间范围。"
            }
        }
    }

    private static let maxTimestamp = (UInt64(1) << 48) - 1
    private static let maxCounter = (UInt64(1) << 42) - 1

    private let clock: MillisecondClock
    private let byteSource: ByteSource?
    private var lastV7Timestamp: UInt64?
    private var v7Counter: UInt64 = 0

    public init(
        clock: @escaping MillisecondClock = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        byteSource: ByteSource? = nil
    ) {
        self.clock = clock
        self.byteSource = byteSource
    }

    public mutating func generate(
        _ version: UUIDGenerationVersion,
        quantity: Int
    ) throws -> [String] {
        guard quantity > 0 else { return [] }

        var values: [String] = []
        values.reserveCapacity(quantity)

        for _ in 0..<quantity {
            switch version {
            case .v4:
                values.append(try generateV4())
            case .v7:
                values.append(try generateV7())
            }
        }

        return values
    }

    private mutating func generateV4() throws -> String {
        var bytes = try randomBytes(count: 16)
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return uuidString(bytes)
    }

    private mutating func generateV7() throws -> String {
        let wallClock = clock()
        guard wallClock >= 0 else { throw Failure.timestampOutOfRange }

        let currentTimestamp = UInt64(wallClock)
        guard currentTimestamp <= Self.maxTimestamp else {
            throw Failure.timestampOutOfRange
        }

        let timestamp: UInt64
        if let lastV7Timestamp {
            if currentTimestamp > lastV7Timestamp {
                timestamp = currentTimestamp
                v7Counter = try seedCounter()
            } else if v7Counter == Self.maxCounter {
                guard lastV7Timestamp < Self.maxTimestamp else {
                    throw Failure.timestampOutOfRange
                }
                timestamp = lastV7Timestamp + 1
                v7Counter = try seedCounter()
            } else {
                timestamp = lastV7Timestamp
                v7Counter += 1
            }
        } else {
            timestamp = currentTimestamp
            v7Counter = try seedCounter()
        }

        lastV7Timestamp = timestamp
        let randomTail = try randomBytes(count: 4)
        return uuidString(Self.v7Bytes(
            timestamp: timestamp,
            counter: v7Counter,
            randomTail: randomTail
        ))
    }

    private mutating func seedCounter() throws -> UInt64 {
        let seed = try randomBytes(count: 6)
        var value: UInt64 = 0
        for byte in seed {
            value = (value << 8) | UInt64(byte)
        }
        return value >> 6
    }

    private func randomBytes(count: Int) throws -> [UInt8] {
        do {
            return try SecureRandomBytes.generate(count: count, source: byteSource)
        } catch {
            throw Failure.randomSourceUnavailable
        }
    }

    private static func v7Bytes(
        timestamp: UInt64,
        counter: UInt64,
        randomTail: [UInt8]
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((timestamp >> 40) & 0xff)
        bytes[1] = UInt8((timestamp >> 32) & 0xff)
        bytes[2] = UInt8((timestamp >> 24) & 0xff)
        bytes[3] = UInt8((timestamp >> 16) & 0xff)
        bytes[4] = UInt8((timestamp >> 8) & 0xff)
        bytes[5] = UInt8(timestamp & 0xff)

        let counterHigh = UInt16(counter >> 30) & 0x0fff
        let counterLow = counter & 0x3fff_ffff
        bytes[6] = 0x70 | UInt8(counterHigh >> 8)
        bytes[7] = UInt8(counterHigh & 0xff)
        bytes[8] = 0x80 | UInt8((counterLow >> 24) & 0x3f)
        bytes[9] = UInt8((counterLow >> 16) & 0xff)
        bytes[10] = UInt8((counterLow >> 8) & 0xff)
        bytes[11] = UInt8(counterLow & 0xff)
        for (offset, byte) in randomTail.enumerated() {
            bytes[12 + offset] = byte
        }
        return bytes
    }

    private func uuidString(_ bytes: [UInt8]) -> String {
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString.lowercased()
    }
}
