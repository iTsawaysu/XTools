import XToolsCore
import Foundation
import Testing

struct UUIDGeneratorTests {
    @Test func v4SetsVersionAndRFCVariantBits() throws {
        var generator = UUIDGenerator(byteSource: Self.repeatingSource(0))
        let bytes = try Self.bytes(of: generator.generate(.v4, quantity: 1)[0])

        #expect(bytes[6] >> 4 == 4)
        #expect(bytes[8] & 0xc0 == 0x80)
    }

    @Test func v7UsesBigEndianMillisecondsAndCorrectFields() throws {
        var generator = UUIDGenerator(
            clock: { 0x0102_0304_0506 },
            byteSource: Self.repeatingSource(0)
        )
        let bytes = try Self.bytes(of: generator.generate(.v7, quantity: 1)[0])
        let timestamp = bytes.prefix(6).reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }

        #expect(timestamp == 0x0102_0304_0506)
        #expect(bytes[6] >> 4 == 7)
        #expect(bytes[8] & 0xc0 == 0x80)
    }

    @Test func v7MatchesRFC9562AppendixVector() throws {
        var generator = UUIDGenerator(
            clock: { 1_645_557_742_000 },
            byteSource: { count in
                switch count {
                case 6:
                    return [0xcc, 0x36, 0x31, 0x37, 0x03, 0x00]
                case 4:
                    return [0x0c, 0x07, 0x39, 0x8f]
                default:
                    return [UInt8](repeating: 0, count: count)
                }
            }
        )

        #expect(try generator.generate(.v7, quantity: 1)
            == ["017f22e2-79b0-7cc3-98c4-dc0c0c07398f"])
    }

    @Test func v7BatchIsStrictlyIncreasingWithinOneMillisecond() throws {
        var generator = UUIDGenerator(
            clock: { 1_000 },
            byteSource: Self.repeatingSource(0)
        )
        let values = try generator.generate(.v7, quantity: 50)

        #expect(values.count == 50)
        #expect(Set(values).count == 50)
        #expect(values == values.sorted())
    }

    @Test func v7ClockRollbackKeepsLogicalOrder() throws {
        var now: Int64 = 1_000
        var generator = UUIDGenerator(
            clock: { now },
            byteSource: Self.repeatingSource(0)
        )
        let first = try generator.generate(.v7, quantity: 1)[0]
        now = 999
        let second = try generator.generate(.v7, quantity: 1)[0]

        #expect(first < second)
        #expect(Self.timestamp(of: first) == 1_000)
        #expect(Self.timestamp(of: second) == 1_000)
    }

    @Test func v7CounterRolloverAdvancesLogicalTimestamp() throws {
        var generator = UUIDGenerator(
            clock: { 1_000 },
            byteSource: { count in
                if count == 6 {
                    return [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
                }
                return [UInt8](repeating: 0, count: count)
            }
        )
        let first = try generator.generate(.v7, quantity: 1)[0]
        let second = try generator.generate(.v7, quantity: 1)[0]

        #expect(first < second)
        #expect(Self.timestamp(of: first) == 1_000)
        #expect(Self.timestamp(of: second) == 1_001)
    }

    @Test func v7UsesFreshRandomTailForEachValue() throws {
        var tail: UInt8 = 1
        var generator = UUIDGenerator(
            clock: { 1_000 },
            byteSource: { count in
                if count == 6 { return [UInt8](repeating: 0, count: count) }
                defer { tail += 1 }
                return [0, 0, 0, tail]
            }
        )
        let values = try generator.generate(.v7, quantity: 2)
        let first = try Self.bytes(of: values[0])
        let second = try Self.bytes(of: values[1])

        #expect(first.suffix(4) != second.suffix(4))
    }

    @Test func randomSourceFailureIsTyped() {
        var generator = UUIDGenerator(byteSource: { _ in
            throw SecureRandomBytes.GenerationError.randomSourceUnavailable
        })

        #expect(throws: UUIDGenerator.Failure.randomSourceUnavailable) {
            try generator.generate(.v7, quantity: 1)
        }
    }

    @Test func v7RejectsTimestampBeyondFortyEightBits() {
        var generator = UUIDGenerator(
            clock: { Int64(1) << 48 },
            byteSource: Self.repeatingSource(0)
        )

        #expect(throws: UUIDGenerator.Failure.timestampOutOfRange) {
            try generator.generate(.v7, quantity: 1)
        }
    }

    private static func repeatingSource(_ byte: UInt8) -> UUIDGenerator.ByteSource {
        { count in [UInt8](repeating: byte, count: count) }
    }

    private static func bytes(of value: String) throws -> [UInt8] {
        let uuid = try #require(UUID(uuidString: value))
        return withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    private static func timestamp(of value: String) -> UInt64 {
        let bytes = (try? bytes(of: value)) ?? []
        return bytes.prefix(6).reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
    }
}
