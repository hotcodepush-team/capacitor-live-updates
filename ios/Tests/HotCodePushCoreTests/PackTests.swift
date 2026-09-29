import XCTest
@testable import HotCodePushCore

final class PackTests: XCTestCase {
    func testShouldRoundTripEntriesThroughTheUstarFormat() throws {
        let content = Data("hello".utf8)
        let entries = [PackEntry(sha256: Hashing.sha256Hex(content), body: try Gzip.compress(content)), PackEntry(sha256: Hashing.sha256Hex("x"), body: Data())]
        let pack = PackWriter.pack(entries)
        XCTAssertEqual(pack.count % 512, 0)
        let read = try PackReader.entries(in: pack)
        XCTAssertEqual(read.map { $0.sha256 }, entries.map { $0.sha256 })
        XCTAssertEqual(try Gzip.decompress(read[0].body), content)
    }

    func testShouldRejectATruncatedPack() {
        let pack = PackWriter.pack([PackEntry(sha256: "abc", body: Data(count: 700))])
        XCTAssertThrowsError(try PackReader.entries(in: pack.prefix(600)))
    }

    func testShouldDecompressGzipAndRejectGarbage() throws {
        let content = Data((0..<10_000).map { UInt8($0 % 251) })
        XCTAssertEqual(try Gzip.decompress(try Gzip.compress(content)), content)
        XCTAssertThrowsError(try Gzip.decompress(Data("not gzip".utf8)))
    }
}
