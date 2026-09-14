import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct JPEGQuantizationTables: Equatable, Sendable {
    let valuesByTableID: [UInt8: [UInt16]]

    init?(data: Data) {
        let parsed = data.withUnsafeBytes { rawBuffer -> [UInt8: [UInt16]]? in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  rawBuffer.count >= 4,
                  baseAddress[0] == 0xFF,
                  baseAddress[1] == 0xD8 else {
                return nil
            }

            func byte(at index: Int) -> UInt8 {
                baseAddress[index]
            }

            func segmentLength(at index: Int) -> Int? {
                guard index + 1 < rawBuffer.count else { return nil }
                return Int(byte(at: index)) << 8 | Int(byte(at: index + 1))
            }

            var tables: [UInt8: [UInt16]] = [:]
            var offset = 2

            while offset < rawBuffer.count {
                guard byte(at: offset) == 0xFF else {
                    offset += 1
                    continue
                }

                while offset < rawBuffer.count, byte(at: offset) == 0xFF {
                    offset += 1
                }
                guard offset < rawBuffer.count else { return nil }

                let marker = byte(at: offset)
                offset += 1

                switch marker {
                case 0xD9, 0xDA:
                    return tables.isEmpty ? nil : tables
                case 0xD8, 0x01, 0xD0...0xD7:
                    continue
                default:
                    guard let length = segmentLength(at: offset), length >= 2 else {
                        return nil
                    }
                    let payloadStart = offset + 2
                    let segmentEnd = offset + length
                    guard payloadStart <= segmentEnd, segmentEnd <= rawBuffer.count else {
                        return nil
                    }

                    if marker == 0xDB {
                        var tableOffset = payloadStart
                        while tableOffset < segmentEnd {
                            let descriptor = byte(at: tableOffset)
                            tableOffset += 1
                            let precision = descriptor >> 4
                            let tableID = descriptor & 0x0F
                            guard precision <= 1, tableID <= 3 else { return nil }

                            let bytesPerValue = precision == 0 ? 1 : 2
                            let tableByteCount = 64 * bytesPerValue
                            guard tableOffset + tableByteCount <= segmentEnd else {
                                return nil
                            }

                            var values: [UInt16] = []
                            values.reserveCapacity(64)
                            for _ in 0..<64 {
                                if bytesPerValue == 1 {
                                    values.append(UInt16(byte(at: tableOffset)))
                                    tableOffset += 1
                                } else {
                                    let value = UInt16(byte(at: tableOffset)) << 8
                                        | UInt16(byte(at: tableOffset + 1))
                                    values.append(value)
                                    tableOffset += 2
                                }
                            }
                            tables[tableID] = values
                        }
                        guard tableOffset == segmentEnd else { return nil }
                    }

                    offset = segmentEnd
                }
            }

            return tables.isEmpty ? nil : tables
        }

        guard let parsed else { return nil }
        valuesByTableID = parsed
    }
}

enum JPEGSourceEncodingQuality {
    private struct Candidate: Sendable {
        let quality: Double
        let tables: JPEGQuantizationTables
    }

    private static let candidates: [Candidate] = makeCandidates()

    static func matchedImageIOQuality(for data: Data) -> Double? {
        guard let sourceTables = JPEGQuantizationTables(data: data),
              !candidates.isEmpty else {
            return nil
        }

        if let exact = candidates.last(where: { $0.tables == sourceTables }) {
            return exact.quality
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = distance(from: sourceTables, to: lhs.tables)
            let rhsDistance = distance(from: sourceTables, to: rhs.tables)
            if lhsDistance == rhsDistance {
                return lhs.quality > rhs.quality
            }
            return lhsDistance < rhsDistance
        }?.quality
    }

    private static func makeCandidates() -> [Candidate] {
        guard let image = makeCalibrationImage() else { return [] }
        var result: [Candidate] = []

        for percentage in 5...100 {
            let quality = Double(percentage) / 100
            guard let data = encodeCalibrationImage(image, quality: quality),
                  let tables = JPEGQuantizationTables(data: data) else {
                continue
            }

            if let existingIndex = result.firstIndex(where: { $0.tables == tables }) {
                result[existingIndex] = Candidate(quality: quality, tables: tables)
            } else {
                result.append(Candidate(quality: quality, tables: tables))
            }
        }

        return result.sorted { $0.quality < $1.quality }
    }

    private static func makeCalibrationImage() -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return context.makeImage()
    }

    private static func encodeCalibrationImage(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func distance(
        from source: JPEGQuantizationTables,
        to candidate: JPEGQuantizationTables
    ) -> Double {
        var total = 0.0
        var comparedValueCount = 0

        for (tableID, sourceValues) in source.valuesByTableID {
            guard let candidateValues = candidate.valuesByTableID[tableID],
                  candidateValues.count == sourceValues.count else {
                total += 64
                continue
            }

            for (sourceValue, candidateValue) in zip(sourceValues, candidateValues) {
                let sourceScale = Double(sourceValue) + 1
                let candidateScale = Double(candidateValue) + 1
                total += abs(log(sourceScale / candidateScale))
                comparedValueCount += 1
            }
        }

        guard comparedValueCount > 0 else { return .infinity }
        return total / Double(comparedValueCount)
    }
}
