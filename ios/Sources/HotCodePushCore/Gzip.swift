import Foundation
import zlib

/// Decodes the gzip bytes the bucket serves into the file's content.
public enum Gzip {
    public enum Failure: Error, Equatable {
        case corrupt(Int32)
        case tooLarge(maximumBytes: Int)
    }

    /// Gzip bytes carry the `1f 8b` magic; anything else is stored as it is.
    public static func isCompressed(_ data: Data) -> Bool {
        return data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    public static func decompressIfCompressed(_ data: Data, maximumBytes: Int) throws -> Data {
        return isCompressed(data) ? try decompress(data, maximumBytes: maximumBytes) : data
    }

    /// Inflates at most `maximumBytes`, the file's size: a few bytes that would inflate to gigabytes are refused on the way.
    public static func decompress(_ data: Data, maximumBytes: Int) throws -> Data {
        if data.isEmpty { return data }
        var stream = z_stream()
        var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw Failure.corrupt(status) }
        defer { inflateEnd(&stream) }
        var output = Data(capacity: min(data.count * 4, maximumBytes))
        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var input = [UInt8](data)
        return try input.withUnsafeMutableBufferPointer { inputPointer -> Data in
            stream.next_in = inputPointer.baseAddress
            stream.avail_in = UInt32(inputPointer.count)
            repeat {
                try chunk.withUnsafeMutableBufferPointer { chunkPointer in
                    stream.next_out = chunkPointer.baseAddress
                    stream.avail_out = UInt32(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { throw Failure.corrupt(status) }
                    let inflated = chunkSize - Int(stream.avail_out)
                    guard output.count + inflated <= maximumBytes else { throw Failure.tooLarge(maximumBytes: maximumBytes) }
                    output.append(chunkPointer.baseAddress!, count: inflated)
                }
            } while status != Z_STREAM_END && stream.avail_in > 0
            guard status == Z_STREAM_END else { throw Failure.corrupt(status) }
            return output
        }
    }

    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        var status = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw Failure.corrupt(status) }
        defer { deflateEnd(&stream) }
        var output = Data()
        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var input = [UInt8](data)
        return try input.withUnsafeMutableBufferPointer { inputPointer -> Data in
            stream.next_in = inputPointer.baseAddress
            stream.avail_in = UInt32(inputPointer.count)
            repeat {
                try chunk.withUnsafeMutableBufferPointer { chunkPointer in
                    stream.next_out = chunkPointer.baseAddress
                    stream.avail_out = UInt32(chunkSize)
                    status = deflate(&stream, Z_FINISH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { throw Failure.corrupt(status) }
                    output.append(chunkPointer.baseAddress!, count: chunkSize - Int(stream.avail_out))
                }
            } while status != Z_STREAM_END
            return output
        }
    }
}
