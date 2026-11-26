import Darwin
import Foundation

enum BoundedFileReader {
    enum ReadError: Error {
        case tooLarge
        case notRegularFile
    }

    static func read(from url: URL, maxBytes: Int) throws -> Data {
        try Task.checkCancellation()
        guard maxBytes >= 0 else { throw ReadError.tooLarge }

        return try withRegularFile(at: url) { handle, _ in
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

    static func withRegularFile<Output>(at url: URL, read: (FileHandle, Int64) throws -> Output) throws -> Output {
        try Task.checkCancellation()
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        // Validate the opened item. A file chosen earlier may have been replaced since preflight.
        let descriptor = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw CocoaError(.fileReadInvalidFileName) }
            let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            return descriptor
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw ReadError.notRegularFile }
        return try read(handle, status.st_size)
    }
}
