import Foundation

/// One entry of a pack: the file's hash and its stored bytes, gzip as the bucket serves them.
public struct PackEntry {
    public let sha256: String
    public let body: Data
}

/// Reads the pack format: an uncompressed ustar archive whose entries are named by their content hash.
public enum PackReader {
    public enum Failure: Error, Equatable {
        case truncated
        case invalidHeader
    }

    private static let blockSize = 512

    public static func entries(in data: Data) throws -> [PackEntry] {
        var entries: [PackEntry] = []
        try forEachEntry(in: data) { entries.append($0) }
        return entries
    }

    public static func forEachEntry(in data: Data, _ body: (PackEntry) throws -> Void) throws {
        var offset = 0
        while offset + blockSize <= data.count {
            let header = data.subdata(in: offset..<(offset + blockSize))
            if header.allSatisfy({ $0 == 0 }) {
                return
            }
            guard header.count == blockSize else { throw Failure.invalidHeader }
            let name = string(in: header, from: 0, length: 100)
            guard let size = Int(string(in: header, from: 124, length: 12), radix: 8) else { throw Failure.invalidHeader }
            let start = offset + blockSize
            let end = start + size
            guard end <= data.count else { throw Failure.truncated }
            try body(PackEntry(sha256: name, body: data.subdata(in: start..<end)))
            offset = start + ((size + blockSize - 1) / blockSize) * blockSize
        }
    }

    private static func string(in header: Data, from start: Int, length: Int) -> String {
        let field = header.subdata(in: (header.startIndex + start)..<(header.startIndex + start + length))
        let bytes = field.prefix { $0 != 0 }
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
}

/// Writes the same format; the SDK only reads packs, the writer exists for the tests.
public enum PackWriter {
    public static func pack(_ entries: [PackEntry]) -> Data {
        var data = Data()
        for entry in entries {
            var header = Data(count: 512)
            header.replaceSubrange(0..<entry.sha256.utf8.count, with: Data(entry.sha256.utf8))
            let size = String(format: "%011o", entry.body.count)
            header.replaceSubrange(124..<(124 + 11), with: Data(size.utf8))
            header.replaceSubrange(148..<156, with: Data(repeating: 0x20, count: 8))
            header.replaceSubrange(257..<262, with: Data("ustar".utf8))
            header.replaceSubrange(263..<265, with: Data("00".utf8))
            let checksum = header.reduce(0) { $0 + Int($1) }
            header.replaceSubrange(148..<(148 + 7), with: Data((String(format: "%06o", checksum) + "\u{0}").utf8))
            data.append(header)
            data.append(entry.body)
            let padding = (512 - entry.body.count % 512) % 512
            data.append(Data(count: padding))
        }
        data.append(Data(count: 1024))
        return data
    }
}
