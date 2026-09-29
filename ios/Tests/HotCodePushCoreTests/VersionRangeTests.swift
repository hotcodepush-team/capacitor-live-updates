import XCTest
@testable import HotCodePushCore

final class VersionRangeTests: XCTestCase {
    func testShouldParseComparatorsWildcardsAndAlternatives() {
        XCTAssertTrue(VersionRange(">=2.3.0 <3.0.0")!.contains("2.4.1"))
        XCTAssertFalse(VersionRange(">=2.3.0 <3.0.0")!.contains("3.0.0"))
        XCTAssertTrue(VersionRange("2.x")!.contains("2.9.9"))
        XCTAssertFalse(VersionRange("2.x")!.contains("3.0.0"))
        XCTAssertTrue(VersionRange("2.4.x")!.contains("2.4.7"))
        XCTAssertFalse(VersionRange("2.4.x")!.contains("2.5.0"))
        XCTAssertTrue(VersionRange("14")!.contains("14.2"))
        XCTAssertTrue(VersionRange("<2.4.1 || >2.4.1")!.contains("2.4.0"))
        XCTAssertFalse(VersionRange("<2.4.1 || >2.4.1")!.contains("2.4.1"))
        XCTAssertTrue(VersionRange("2.4.1")!.contains("2.4.1"))
        XCTAssertTrue(VersionRange(">=17.4")!.contains("17.4"))
        XCTAssertTrue(VersionRange(">=1.0.0")!.contains("1.0.0-beta.1"))
    }

    func testShouldRejectWhatItCannotParse() {
        XCTAssertNil(VersionRange("^2.0.0"))
        XCTAssertNil(VersionRange("latest"))
        XCTAssertNil(Version("a.b"))
        XCTAssertFalse(VersionRange(">=1")!.contains("not a version"))
    }
}
