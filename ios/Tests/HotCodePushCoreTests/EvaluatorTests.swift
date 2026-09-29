import XCTest
@testable import HotCodePushCore

final class EvaluatorTests: XCTestCase {
    private let device = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: "fp1:abc", attributes: ["plan": "beta"], builtAt: Fixture.builtAt, reportedAt: nil, failedBundleIds: [], currentRelease: nil)

    private func release(_ number: Int, conditions: [Condition] = [], rollout: Int = 100, createdAt: Date = Fixture.builtAt.addingTimeInterval(1), bundleId: String? = nil) -> IndexRelease {
        return IndexRelease(id: "r\(number)", number: number, createdAt: createdAt, rollout: rollout, conditions: conditions, bundleId: bundleId ?? "b\(number)", bundleVersion: "1.0.\(number)", manifestUrl: "https://files.test/m\(number)", manifestSha256: "", sizeBytes: 1)
    }

    func testShouldTakeTheNewestEligibleRelease() {
        let index = Fixture.index(sequence: 1, releases: [release(1), release(3), release(2)])
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .update(release(3)))
    }

    func testShouldBeUpToDateWhenNothingIsNewerThanTheRunningRelease() {
        let index = Fixture.index(sequence: 1, releases: [release(1), release(2)])
        let running = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: nil, attributes: [:], builtAt: Fixture.builtAt, reportedAt: nil, failedBundleIds: [], currentRelease: release(2).release)
        XCTAssertEqual(Evaluator.evaluate(index, device: running), .upToDate)
    }

    func testShouldSkipWhenTheChannelIsPaused() {
        let index = Fixture.index(sequence: 1, releases: [release(1)], isPaused: true)
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .unavailable(reason: .channelPaused))
    }

    func testShouldSkipBeyondTheSpendingCapWhenTheReportIsAfterTheCap() {
        let cappedAt = Fixture.builtAt.addingTimeInterval(100)
        let index = Fixture.index(sequence: 1, releases: [release(1)], cappedAt: cappedAt)
        let counted = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: nil, attributes: [:], builtAt: Fixture.builtAt, reportedAt: cappedAt.addingTimeInterval(-1), failedBundleIds: [], currentRelease: nil)
        XCTAssertEqual(Evaluator.evaluate(index, device: counted), .update(release(1)))
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .unavailable(reason: .spendingCapReached))
    }

    func testShouldSkipAReleaseOlderThanTheBinary() {
        let index = Fixture.index(sequence: 1, releases: [release(1, createdAt: Fixture.builtAt.addingTimeInterval(-1))])
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .skipped(newest: release(1, createdAt: Fixture.builtAt.addingTimeInterval(-1)), skip: Skip(reason: .olderThanBinary)))
    }

    func testShouldSkipABundleThatFailedBefore() {
        let failed = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: nil, attributes: [:], builtAt: Fixture.builtAt, reportedAt: nil, failedBundleIds: ["b1"], currentRelease: nil)
        let index = Fixture.index(sequence: 1, releases: [release(1)])
        XCTAssertEqual(Evaluator.evaluate(index, device: failed), .skipped(newest: release(1), skip: Skip(reason: .failedBefore)))
    }

    func testShouldEvaluateEveryConditionType() {
        XCTAssertNil(Evaluator.evaluate(.binary(range: ">=2.3.0 <3.0.0"), device: device))
        XCTAssertEqual(Evaluator.evaluate(.binary(range: "<2.4.1 || >2.4.1"), device: device), Skip(reason: .incompatible, condition: .binary))
        XCTAssertNil(Evaluator.evaluate(.os(range: "17.x"), device: device))
        XCTAssertEqual(Evaluator.evaluate(.os(range: ">=18"), device: device), Skip(reason: .incompatible, condition: .os))
        XCTAssertNil(Evaluator.evaluate(.fingerprint(hash: "fp1:abc"), device: device))
        XCTAssertEqual(Evaluator.evaluate(.fingerprint(hash: "fp1:other"), device: device), Skip(reason: .incompatible, condition: .fingerprint))
        XCTAssertEqual(Evaluator.evaluate(.runtime(version: "1"), device: device), Skip(reason: .incompatible, condition: .runtime))
        XCTAssertNil(Evaluator.evaluate(.device(hashedIds: [Hashing.sha256Hex("d1")]), device: device))
        XCTAssertEqual(Evaluator.evaluate(.device(hashedIds: [Hashing.sha256Hex("d2")]), device: device), Skip(reason: .notTargeted, condition: .device))
        XCTAssertNil(Evaluator.evaluate(.attribute(key: "plan", valueSha256: Hashing.attributeHash(key: "plan", value: "beta")), device: device))
        XCTAssertEqual(Evaluator.evaluate(.attribute(key: "plan", valueSha256: Hashing.attributeHash(key: "plan", value: "pro")), device: device), Skip(reason: .notTargeted, condition: .attribute))
        XCTAssertEqual(Evaluator.evaluate(.unknown(type: "geo"), device: device), Skip(reason: .unsupportedCondition))
    }

    func testShouldFailClosedOnAnUnknownConditionType() throws {
        let json = #"{"type":"geo","country":"DE"}"#
        let condition = try Json.decoder.decode(Condition.self, from: Data(json.utf8))
        XCTAssertEqual(condition, .unknown(type: "geo"))
    }

    func testShouldPlaceADeviceInARolloutBucketStably() {
        let bucket = Hashing.rolloutBucket(deviceId: "d1", releaseId: "r1")
        XCTAssertEqual(bucket, Hashing.rolloutBucket(deviceId: "d1", releaseId: "r1"))
        XCTAssert((0..<100).contains(bucket))
        let index = Fixture.index(sequence: 1, releases: [release(1, rollout: bucket)])
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .skipped(newest: release(1, rollout: bucket), skip: Skip(reason: .notInRollout)))
        let wider = Fixture.index(sequence: 1, releases: [release(1, rollout: bucket + 1)])
        XCTAssertEqual(Evaluator.evaluate(wider, device: device), .update(release(1, rollout: bucket + 1)))
    }

    func testShouldFallToAnOlderEligibleReleaseWhenTheRunningOneIsRevoked() {
        let running = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: nil, attributes: [:], builtAt: Fixture.builtAt, reportedAt: nil, failedBundleIds: [], currentRelease: release(3).release)
        let index = Fixture.index(sequence: 2, releases: [release(1), release(2), release(3)], revoked: ["r3"])
        XCTAssertEqual(Evaluator.evaluate(index, device: running), .update(release(2)))
        let allRevoked = Fixture.index(sequence: 3, releases: [release(1), release(2), release(3)], revoked: ["r1", "r2", "r3"])
        XCTAssertEqual(Evaluator.evaluate(allRevoked, device: running), .revert(reason: .releaseRevoked))
    }

    func testShouldResetToTheEmbeddedBundleOnTheDirective() {
        let running = DeviceInfo(deviceId: "d1", binaryVersion: "2.4.1", binaryBuild: "57", osVersion: "17.4", fingerprint: nil, attributes: [:], builtAt: Fixture.builtAt, reportedAt: nil, failedBundleIds: [], currentRelease: release(2).release)
        let index = Fixture.index(sequence: 2, releases: [release(2)], rollBackToEmbedded: RollBackToEmbedded(aboveNumber: 2))
        XCTAssertEqual(Evaluator.evaluate(index, device: running), .revert(reason: .releaseRevoked))
        let below = Fixture.index(sequence: 2, releases: [release(2)], rollBackToEmbedded: RollBackToEmbedded(aboveNumber: 1))
        XCTAssertEqual(Evaluator.evaluate(below, device: running), .upToDate)
    }

    func testShouldReportTheNewestSkippedReleaseWhenAnOlderOneWouldQualify() {
        let index = Fixture.index(sequence: 1, releases: [release(1), release(2, conditions: [.os(range: ">=18")])])
        XCTAssertEqual(Evaluator.evaluate(index, device: device), .update(release(1)))
    }
}
