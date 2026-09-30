import XCTest
@testable import HotCodePushCore

final class CoreTests: XCTestCase {
    func testShouldRunTheEmbeddedBundleAndBeUpToDateOnAnEmptyChannel() async {
        let harness = Harness()
        harness.publish([], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .upToDate(nil))
        XCTAssertEqual(harness.listener.started, [.call])
        XCTAssertEqual(harness.listener.synced, [result])
    }

    func testShouldDownloadAReleaseAndApplyItAtTheNextStart() async throws {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .updated(v2.release.release, notes: "notes 1", installAt: .nextStart))
        XCTAssertEqual(harness.loader.persisted, .some("b2"))
        XCTAssertEqual(harness.loader.loaded, [])
        XCTAssertTrue(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v2</html>")))
        XCTAssertEqual(try Data(contentsOf: harness.loader.projectionDirectory(bundleId: "b2").appendingPathComponent("index.html")), Data("<html>v2</html>".utf8))
        let status = await harness.core.status()
        XCTAssertEqual(status.nextRelease, v2.release.release)
        XCTAssertNil(status.currentRelease)
        XCTAssertEqual(status.index?.sequence, 1)

        harness.loader.served = "b2"
        harness.restart()
        await harness.core.handleAppStart()
        let started = await harness.core.status()
        XCTAssertEqual(started.currentRelease, v2.release.release)
        XCTAssertNil(started.nextRelease)
        XCTAssertNil(started.fallbackRelease)
        XCTAssertEqual(harness.scheduler.tasks.count, 1)
        let ready = await harness.core.ready()
        XCTAssertEqual(ready, ReadyResult(currentRelease: v2.release.release, previousRelease: nil, isRolledBack: false, rollbackReason: nil))
        let confirmed = await harness.core.status()
        XCTAssertEqual(confirmed.fallbackRelease, v2.release.release)
        XCTAssertTrue(harness.scheduler.tasks[0].isCancelled)
    }

    func testShouldStartOnTheEmbeddedBundleWhenTheBinaryChanged() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        StateStore(store: harness.store).failedBundleIds = ["b0"]
        harness.loader.served = nil
        harness.restart(configuration: Fixture.configuration(builtAt: Fixture.builtAt.addingTimeInterval(86_400)))
        await harness.core.handleAppStart()
        let status = await harness.core.status()
        XCTAssertNil(status.currentRelease)
        XCTAssertNil(status.nextRelease)
        XCTAssertNil(status.fallbackRelease)
        XCTAssertEqual(status.failedBundleIds, [])
        XCTAssertEqual(harness.loader.persisted, .some(nil))
        XCTAssertEqual(harness.loader.loaded, ["b2"])
        XCTAssertEqual(harness.files.bundleIds(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.loader.projectionDirectory(bundleId: "b2").path))
    }

    func testShouldKeepTheCurrentReleaseWhenTheBinaryIsTheSame() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        harness.restart()
        await harness.core.handleAppStart()
        let status = await harness.core.status()
        XCTAssertEqual(status.currentRelease, v2.release.release)
        XCTAssertEqual(status.fallbackRelease, v2.release.release)
        XCTAssertEqual(harness.files.bundleIds(), ["b2"])
    }

    func testShouldRollBackAReleaseThatNeverRendersAndBlocklistIt() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result.installAt, .now)
        XCTAssertEqual(harness.loader.loaded, ["b2"])
        XCTAssertEqual(harness.scheduler.tasks.count, 1)
        harness.scheduler.fire()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let status = await harness.core.status()
        XCTAssertNil(status.currentRelease)
        XCTAssertEqual(status.failedBundleIds, ["b2"])
        XCTAssertEqual(harness.loader.loaded, ["b2", nil])
        let again = await harness.core.sync(trigger: .call)
        XCTAssertEqual(again, .skipped(v2.release.release, reason: .failedBefore))
        let ready = await harness.core.ready()
        XCTAssertEqual(ready.isRolledBack, true)
        XCTAssertEqual(ready.rollbackReason, .readyTimeout)
        XCTAssertEqual(ready.previousRelease, v2.release.release)
    }

    func testShouldTreatAStartOnAnUnconfirmedReleaseAsACrash() async {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        harness.loader.served = "b2"
        harness.restart()
        await harness.core.handleAppStart()
        harness.restart()
        await harness.core.handleAppStart()
        let status = await harness.core.status()
        XCTAssertNil(status.currentRelease)
        XCTAssertEqual(status.failedBundleIds, ["b2"])
        XCTAssertEqual(harness.listener.rolledBack.last?.reason, .crashed)
        XCTAssertEqual(harness.loader.loaded.last, .some(nil))
    }

    func testShouldFallBackToTheLastConfirmedReleaseNotTheEmbeddedBundle() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        let v3 = Fixture.release(number: 2, bundleId: "b3", content: Data("<html>v3</html>".utf8))
        harness.publish([v2, v3], sequence: 2, etag: "\"e2\"")
        _ = await harness.core.sync(trigger: .call)
        await harness.core.rollback(reason: "fatal")
        let status = await harness.core.status()
        XCTAssertEqual(status.currentRelease, v2.release.release)
        XCTAssertEqual(status.failedBundleIds, ["b3"])
        XCTAssertEqual(harness.loader.loaded.last, "b2")
        let events = StateStore(store: harness.store).unsentEvents
        XCTAssertEqual(events.last?.type, "rolledBack")
        XCTAssertEqual(events.last?.toReleaseId, "r1")
    }

    func testShouldKeepTheCachedIndexOfflineAndIgnoreAnOlderSequence() async {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 5)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        harness.http.isOffline = true
        let offline = await harness.core.sync(trigger: .call)
        XCTAssertEqual(offline.status, .updated)
        harness.http.isOffline = false
        harness.publish([], sequence: 4, etag: "\"e0\"")
        let stale = await harness.core.sync(trigger: .call)
        XCTAssertEqual(stale.status, .updated)
        let status = await harness.core.status()
        XCTAssertEqual(status.index?.sequence, 5)
    }

    func testShouldFailOfflineWithoutACachedIndex() async {
        let harness = Harness()
        harness.http.isOffline = true
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.reason, FailedReason.offline.rawValue)
    }

    func testShouldSendTheEtagAndAcceptANotModified() async {
        let harness = Harness()
        harness.publish([], sequence: 1, etag: "\"e1\"")
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        harness.http.stub(Fixture.indexUrl(), status: 304, body: Data())
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .upToDate(nil))
        XCTAssertEqual(harness.http.requests.last?.headers["If-None-Match"], "\"e1\"")
    }

    func testShouldCheckWithoutDownloading() async {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.check()
        XCTAssertEqual(result, .available(v2.release.release, notes: "notes 1", downloadBytes: 15))
        XCTAssertFalse(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v2</html>")))
        XCTAssertEqual(harness.listener.started, [])
    }

    func testShouldFailVerificationOnATamperedManifest() async {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        harness.http.stubJson(v2.release.manifestUrl, ManifestEnvelope(manifest: v2.envelope.manifest + " ", signature: nil))
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.reason, FailedReason.verificationFailed.rawValue)
    }

    func testShouldRefuseAnUnsignedManifestOnceAPublicKeyIsConfigured() async {
        let harness = Harness(configuration: Fixture.configuration(publicKeys: ["k1"]))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result.reason, FailedReason.invalidSignature.rawValue)
    }

    func testShouldAdoptAReleaseCarryingTheRunningBundleWithoutAReload() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        let rollback = Fixture.release(number: 2, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2, rollback], sequence: 2, etag: "\"e2\"")
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .updated(rollback.release.release, notes: "notes 2", installAt: .now))
        XCTAssertEqual(harness.loader.loaded, ["b2"])
        let status = await harness.core.status()
        XCTAssertEqual(status.currentRelease?.id, "r2")
        XCTAssertEqual(status.fallbackRelease?.id, "r2")
    }

    func testShouldRevertToTheEmbeddedBundleWhenTheRunningReleaseIsRevoked() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        harness.publish([v2], sequence: 2, revoked: ["r1"], etag: "\"e2\"")
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .skipped(nil, reason: .releaseRevoked))
        XCTAssertEqual(harness.loader.loaded.last, .some(nil))
        let status = await harness.core.status()
        XCTAssertNil(status.currentRelease)
    }

    func testShouldQueueARestartWhileRestartsAreNotAllowed() async {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        await harness.core.setRestartAllowed(false)
        _ = await harness.core.sync(trigger: .call)
        XCTAssertEqual(harness.loader.loaded, [])
        await harness.core.setRestartAllowed(true)
        XCTAssertEqual(harness.loader.loaded, ["b2"])
    }

    func testShouldSkipOnAMeteredConnectionUnderTheUnmeteredPolicy() async {
        let harness = Harness()
        harness.loader.isMetered = true
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        let result = await harness.core.sync(trigger: .call, network: .unmetered)
        XCTAssertEqual(result, .skipped(v2.release.release, reason: .meteredConnection))
    }

    func testShouldResolveAChannelNameThroughTheChannelsIndex() async {
        let harness = Harness()
        harness.http.stubJson("\(Fixture.filesBaseUrl)/apps/\(Fixture.appId)/channels/v1/index.json", ChannelsIndex(channels: [.init(id: "c-staging", name: "staging")]))
        harness.http.stubJson("\(Fixture.filesBaseUrl)/apps/\(Fixture.appId)/channels/c-staging/ios/v1/index.json", ChannelIndex(sequence: 1, appId: Fixture.appId, channelId: "c-staging", platform: "ios", releases: []))
        await harness.core.setChannel(.name("staging"))
        let result = await harness.core.sync(trigger: .call)
        XCTAssertEqual(result, .upToDate(nil))
        let channel = await harness.core.channel()
        XCTAssertEqual(channel, ChannelResult(id: "c-staging", name: "staging", source: .runtime))
        await harness.core.setChannel(.name("nowhere"))
        let unknown = await harness.core.sync(trigger: .call)
        XCTAssertEqual(unknown.reason, FailedReason.unknownChannel.rawValue)
    }

    func testShouldMergeAttributesAndRefuseInvalidOnes() async throws {
        let harness = Harness()
        try await harness.core.setAttributes(["plan": "beta", "userId": "42"])
        try await harness.core.setAttributes(["plan": nil])
        let device = await harness.core.deviceResult()
        XCTAssertEqual(device.attributes, ["userId": "42"])
        XCTAssertEqual(device.channel.source, .config)
        XCTAssertEqual(device.fingerprint, "fp1:abc")
        do {
            try await harness.core.setAttributes(["bad key": "x"])
            XCTFail("expected a plain error")
        } catch let error as PlainError {
            XCTAssertTrue(error.message.contains("identifier"))
        }
    }

    func testShouldReportChecksOncePerRelease() async {
        let harness = Harness()
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8), conditions: [.os(range: ">=99")])
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.sync(trigger: .call)
        let events = StateStore(store: harness.store).unsentEvents.filter { $0.type == "checked" }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].reason, SkippedReason.incompatible.rawValue)
        XCTAssertEqual(events[0].condition, .os)
    }

    func testShouldSyncOnStartAndResumeWhenAutoSyncIsOn() async throws {
        let harness = Harness(configuration: Fixture.configuration(autoSync: true))
        harness.publish([], sequence: 1)
        await harness.core.handleAppStart()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(harness.listener.started, [.start])
        await harness.core.handleAppResume()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(harness.listener.started, [.start])
        harness.clock.now = harness.clock.now.addingTimeInterval(1000)
        harness.restart(configuration: Fixture.configuration(autoSync: true))
        await harness.core.handleAppResume()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(harness.listener.started, [.start, .resume])
    }

    func testShouldDeleteTheServedTreesAndFilesOfBundlesNoKeptReleaseLists() async throws {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        let v3 = Fixture.release(number: 2, bundleId: "b3", content: Data("<html>v3</html>".utf8))
        let v4 = Fixture.release(number: 3, bundleId: "b4", content: Data("<html>v4</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        harness.publish([v2, v3], sequence: 2, etag: "\"e2\"")
        _ = await harness.core.sync(trigger: .call)
        _ = await harness.core.ready()
        harness.publish([v2, v3, v4], sequence: 3, etag: "\"e3\"")
        _ = await harness.core.sync(trigger: .call, installStrategy: .nextStart)
        for bundleId in ["b2", "b3", "b4"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: harness.loader.projectionDirectory(bundleId: bundleId).appendingPathComponent("index.html").path), bundleId)
        }
        harness.loader.served = "b4"
        harness.restart(configuration: Fixture.configuration(installStrategy: .immediate))
        await harness.core.handleAppStart()
        let status = await harness.core.status()
        XCTAssertEqual(status.currentRelease?.bundleId, "b4")
        XCTAssertEqual(status.fallbackRelease?.bundleId, "b3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.loader.projectionDirectory(bundleId: "b2").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.loader.projectionDirectory(bundleId: "b3").appendingPathComponent("index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.loader.projectionDirectory(bundleId: "b4").appendingPathComponent("index.html").path))
        XCTAssertEqual(harness.files.bundleIds(), ["b3", "b4"])
        XCTAssertFalse(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v2</html>")))
        XCTAssertFalse(harness.files.hasFile(sha256: Hashing.sha256Hex("js-b2")))
        XCTAssertTrue(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v3</html>")))
        XCTAssertTrue(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v4</html>")))
    }

    func testShouldResetToTheEmbeddedBundleAndKeepTheIdentity() async throws {
        let harness = Harness(configuration: Fixture.configuration(installStrategy: .immediate))
        try await harness.core.setAttributes(["plan": "beta"])
        let v2 = Fixture.release(number: 1, bundleId: "b2", content: Data("<html>v2</html>".utf8))
        harness.publish([v2], sequence: 1)
        await harness.core.handleAppStart()
        _ = await harness.core.sync(trigger: .call)
        await harness.core.reset()
        let status = await harness.core.status()
        XCTAssertNil(status.currentRelease)
        XCTAssertEqual(status.failedBundleIds, [])
        XCTAssertFalse(harness.files.hasFile(sha256: Hashing.sha256Hex("<html>v2</html>")))
        XCTAssertEqual(harness.loader.loaded.last, .some(nil))
        let device = await harness.core.deviceResult()
        XCTAssertEqual(device.attributes, ["plan": "beta"])
    }
}
