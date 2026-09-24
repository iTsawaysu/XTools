import Foundation

enum BoundedFileReader {
    enum ReadError: Error {
        case tooLarge
    }

    static func read(from url: URL, maxBytes: Int) throws -> Data {
        try Task.checkCancellation()
        guard maxBytes >= 0 else { throw ReadError.tooLarge }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(maxBytes, 64 * 1024))

        while true {
            try Task.checkCancellation()
            let remaining = maxBytes - data.count
            let chunkSize = remaining < 64 * 1024 ? remaining + 1 : 64 * 1024
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                try Task.checkCancellation()
                return data
            }
            try Task.checkCancellation()
            guard chunk.count <= remaining else { throw ReadError.tooLarge }
            data.append(chunk)
        }
    }
}
