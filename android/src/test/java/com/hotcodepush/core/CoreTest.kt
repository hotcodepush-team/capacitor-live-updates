package com.hotcodepush.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class CoreTest {
    private val v2Content = "<html>v2</html>".toByteArray()

    @Test
    fun shouldRunTheEmbeddedBundleAndBeUpToDateOnAnEmptyChannel() = runBlocking {
        val harness = Harness()
        harness.publish(emptyList(), 1)
        harness.core.handleAppStart()
        val result = harness.core.sync(SyncTrigger.CALL)
        assertEquals(SyncResult.upToDate(null), result)
        assertEquals(listOf(SyncTrigger.CALL), harness.listener.started)
        assertEquals(listOf(result), harness.listener.synced)
    }

    @Test
    fun shouldDownloadAReleaseAndApplyItAtTheNextStart() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        val result = harness.core.sync(SyncTrigger.CALL)
        assertEquals(SyncResult.updated(v2.release.release, "notes 1", InstallMoment.NEXT_START), result)
        assertEquals("b2", harness.loader.persisted)
        assertTrue(harness.loader.loaded.isEmpty())
        assertTrue(harness.files.hasFile(Hashing.sha256Hex(v2Content)))
        assertEquals("<html>v2</html>", File(harness.loader.projectionDirectory("b2"), "index.html").readText())
        val status = harness.core.status()
        assertEquals(v2.release.release, status.nextRelease)
        assertNull(status.currentRelease)
        assertEquals(1, status.indexSequence)

        harness.loader.served = "b2"
        harness.restart()
        harness.core.handleAppStart()
        val started = harness.core.status()
        assertEquals(v2.release.release, started.currentRelease)
        assertNull(started.nextRelease)
        assertNull(started.fallbackRelease)
        assertEquals(1, harness.scheduler.tasks.size)
        val ready = harness.core.ready()
        assertEquals(ReadyResult(v2.release.release, null, false, null), ready)
        assertEquals(v2.release.release, harness.core.status().fallbackRelease)
        assertTrue(harness.scheduler.tasks[0].isCancelled)
    }

    @Test
    fun shouldStartOnTheEmbeddedBundleWhenTheBinaryChanged() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        StateStore(harness.store).failedBundleIds = listOf("b0")
        harness.loader.served = null
        harness.restart(Fixture.configuration(builtAt = Fixture.BUILT_AT + 86_400_000))
        harness.core.handleAppStart()
        val status = harness.core.status()
        assertNull(status.currentRelease)
        assertNull(status.nextRelease)
        assertNull(status.fallbackRelease)
        assertTrue(status.failedBundleIds.isEmpty())
        assertTrue(harness.loader.hasPersisted && harness.loader.persisted == null)
        assertEquals(listOf("b2"), harness.loader.loaded)
        assertTrue(harness.files.bundleIds().isEmpty())
        assertTrue(!harness.loader.projectionDirectory("b2").exists())
    }

    @Test
    fun shouldKeepTheCurrentReleaseWhenTheBinaryIsTheSame() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        harness.restart()
        harness.core.handleAppStart()
        val status = harness.core.status()
        assertEquals(v2.release.release, status.currentRelease)
        assertEquals(v2.release.release, status.fallbackRelease)
        assertEquals(listOf("b2"), harness.files.bundleIds())
    }

    @Test
    fun shouldRollBackAReleaseThatNeverRendersAndBlocklistIt() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        val result = harness.core.sync(SyncTrigger.CALL)
        assertEquals(InstallMoment.NOW, result.installAt)
        assertEquals(listOf("b2"), harness.loader.loaded)
        assertEquals(1, harness.scheduler.tasks.size)
        harness.scheduler.fire()
        val status = harness.core.status()
        assertNull(status.currentRelease)
        assertEquals(listOf("b2"), status.failedBundleIds)
        assertEquals(listOf("b2", null), harness.loader.loaded)
        assertEquals(SyncResult.skipped(v2.release.release, SkippedReason.FAILED_BEFORE), harness.core.sync(SyncTrigger.CALL))
        val ready = harness.core.ready()
        assertTrue(ready.isRolledBack)
        assertEquals(RollbackReason.READY_TIMEOUT, ready.rollbackReason)
        assertEquals(v2.release.release, ready.previousRelease)
    }

    @Test
    fun shouldTreatAStartOnAnUnconfirmedReleaseAsACrash() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.loader.served = "b2"
        harness.restart()
        harness.core.handleAppStart()
        harness.restart()
        harness.core.handleAppStart()
        val status = harness.core.status()
        assertNull(status.currentRelease)
        assertEquals(listOf("b2"), status.failedBundleIds)
        assertEquals(RollbackReason.CRASHED, harness.listener.rolledBack.last().reason)
        assertNull(harness.loader.loaded.last())
    }

    @Test
    fun shouldFallBackToTheLastConfirmedReleaseNotTheEmbeddedBundle() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        val v3 = Fixture.release(2, "b3", "<html>v3</html>".toByteArray())
        harness.publish(listOf(v2, v3), 2, etag = "\"e2\"")
        harness.core.sync(SyncTrigger.CALL)
        harness.core.rollback("fatal")
        val status = harness.core.status()
        assertEquals(v2.release.release, status.currentRelease)
        assertEquals(listOf("b3"), status.failedBundleIds)
        assertEquals("b2", harness.loader.loaded.last())
        val events = StateStore(harness.store).unsentEvents
        assertEquals("rolledBack", events.last().type)
        assertEquals("r1", events.last().toReleaseId)
    }

    @Test
    fun shouldKeepTheCachedIndexOfflineAndIgnoreAnOlderSequence() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 5)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.http.isOffline = true
        assertEquals(SyncStatus.UPDATED, harness.core.sync(SyncTrigger.CALL).status)
        harness.http.isOffline = false
        harness.publish(emptyList(), 4, etag = "\"e0\"")
        assertEquals(SyncStatus.UPDATED, harness.core.sync(SyncTrigger.CALL).status)
        assertEquals(5, harness.core.status().indexSequence)
    }

    @Test
    fun shouldFailOfflineWithoutACachedIndex() = runBlocking {
        val harness = Harness()
        harness.http.isOffline = true
        harness.core.handleAppStart()
        val result = harness.core.sync(SyncTrigger.CALL)
        assertEquals(SyncStatus.FAILED, result.status)
        assertEquals(FailedReason.OFFLINE.name, result.reason)
    }

    @Test
    fun shouldSendTheEtagAndAcceptANotModified() = runBlocking {
        val harness = Harness()
        harness.publish(emptyList(), 1, etag = "\"e1\"")
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.http.stub(Fixture.indexUrl(), status = 304, body = ByteArray(0))
        assertEquals(SyncResult.upToDate(null), harness.core.sync(SyncTrigger.CALL))
        assertEquals("\"e1\"", harness.http.requests.last().second["If-None-Match"])
    }

    @Test
    fun shouldCheckWithoutDownloading() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        assertEquals(SyncResult.available(v2.release.release, "notes 1", 15), harness.core.check())
        assertTrue(!harness.files.hasFile(Hashing.sha256Hex(v2Content)))
        assertTrue(harness.listener.started.isEmpty())
    }

    @Test
    fun shouldFailVerificationOnATamperedManifest() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.http.stubJson(v2.release.manifestUrl, ManifestEnvelope(v2.envelope.manifest + " ", null).toJson())
        harness.core.handleAppStart()
        val result = harness.core.sync(SyncTrigger.CALL)
        assertEquals(SyncStatus.FAILED, result.status)
        assertEquals(FailedReason.VERIFICATION_FAILED.name, result.reason)
    }

    @Test
    fun shouldRefuseAnUnsignedManifestOnceAPublicKeyIsConfigured() = runBlocking {
        val harness = Harness(Fixture.configuration(publicKeys = listOf("k1")))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        assertEquals(FailedReason.INVALID_SIGNATURE.name, harness.core.sync(SyncTrigger.CALL).reason)
    }

    @Test
    fun shouldAdoptAReleaseCarryingTheRunningBundleWithoutAReload() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        val rollback = Fixture.release(2, "b2", v2Content)
        harness.publish(listOf(v2, rollback), 2, etag = "\"e2\"")
        assertEquals(SyncResult.updated(rollback.release.release, "notes 2", InstallMoment.NOW), harness.core.sync(SyncTrigger.CALL))
        assertEquals(listOf("b2"), harness.loader.loaded)
        assertEquals("r2", harness.core.status().currentRelease?.id)
        assertEquals("r2", harness.core.status().fallbackRelease?.id)
    }

    @Test
    fun shouldRevertToTheEmbeddedBundleWhenTheRunningReleaseIsRevoked() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        harness.publish(listOf(v2), 2, revoked = listOf("r1"), etag = "\"e2\"")
        assertEquals(SyncResult.skipped(null, SkippedReason.RELEASE_REVOKED), harness.core.sync(SyncTrigger.CALL))
        assertNull(harness.loader.loaded.last())
        assertNull(harness.core.status().currentRelease)
    }

    @Test
    fun shouldQueueARestartWhileRestartsAreNotAllowed() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.setRestartAllowed(false)
        harness.core.sync(SyncTrigger.CALL)
        assertTrue(harness.loader.loaded.isEmpty())
        harness.core.setRestartAllowed(true)
        assertEquals(listOf("b2"), harness.loader.loaded)
    }

    @Test
    fun shouldSkipOnAMeteredConnectionUnderTheUnmeteredPolicy() = runBlocking {
        val harness = Harness()
        harness.loader.isMetered = true
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        assertEquals(SyncResult.skipped(v2.release.release, SkippedReason.METERED_CONNECTION), harness.core.sync(SyncTrigger.CALL, network = NetworkPolicy.UNMETERED))
    }

    @Test
    fun shouldResolveAChannelNameThroughTheChannelsIndex() = runBlocking {
        val harness = Harness()
        harness.http.stubJson("${Fixture.FILES_BASE_URL}/apps/${Fixture.APP_ID}/channels/v1/index.json", org.json.JSONObject().put("schema", 1).put("channels", org.json.JSONArray().put(org.json.JSONObject().put("id", "c-staging").put("name", "staging"))))
        harness.http.stubJson("${Fixture.FILES_BASE_URL}/apps/${Fixture.APP_ID}/channels/c-staging/android/v1/index.json", ChannelIndex(1, 1, Fixture.APP_ID, "c-staging", "android", false, null, emptyList(), null, emptyList()).toJson())
        harness.core.setChannel(ChannelChoice.Name("staging"))
        assertEquals(SyncResult.upToDate(null), harness.core.sync(SyncTrigger.CALL))
        assertEquals(ChannelResult("c-staging", "staging", ChannelSource.RUNTIME), harness.core.channel())
        harness.core.setChannel(ChannelChoice.Name("nowhere"))
        assertEquals(FailedReason.UNKNOWN_CHANNEL.name, harness.core.sync(SyncTrigger.CALL).reason)
    }

    @Test
    fun shouldMergeAttributesAndRefuseInvalidOnes() = runBlocking {
        val harness = Harness()
        harness.core.setAttributes(mapOf("plan" to "beta", "userId" to "42"))
        harness.core.setAttributes(mapOf("plan" to null))
        val device = harness.core.deviceResult()
        assertEquals(mapOf("userId" to "42"), device.attributes)
        assertEquals(ChannelSource.CONFIG, device.channel.source)
        assertEquals("fp1:abc", device.fingerprint)
        val error = runCatching { harness.core.setAttributes(mapOf("bad key" to "x")) }.exceptionOrNull()
        assertTrue(error is PlainException && error.message!!.contains("identifier"))
    }

    @Test
    fun shouldReportChecksOncePerRelease() = runBlocking {
        val harness = Harness()
        val v2 = Fixture.release(1, "b2", v2Content, conditions = listOf(Condition.Os(">=99")))
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.sync(SyncTrigger.CALL)
        val events = StateStore(harness.store).unsentEvents.filter { it.type == "checked" }
        assertEquals(1, events.size)
        assertEquals(SkippedReason.INCOMPATIBLE.name, events[0].reason)
        assertEquals(ConditionType.OS, events[0].condition)
    }

    @Test
    fun shouldSyncOnStartAndResumeWhenAutoSyncIsOn() = runBlocking {
        val harness = Harness(Fixture.configuration(autoSync = true))
        harness.publish(emptyList(), 1)
        harness.core.handleAppStart()
        assertEquals(listOf(SyncTrigger.START), harness.listener.started)
        harness.core.handleAppResume()
        assertEquals(listOf(SyncTrigger.START), harness.listener.started)
        harness.clock.now += 1_000_000
        harness.restart(Fixture.configuration(autoSync = true))
        harness.core.handleAppResume()
        assertEquals(listOf(SyncTrigger.START, SyncTrigger.RESUME), harness.listener.started)
    }

    @Test
    fun shouldDeleteTheServedTreesAndFilesOfBundlesNoKeptReleaseLists() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        val v2 = Fixture.release(1, "b2", v2Content)
        val v3 = Fixture.release(2, "b3", "<html>v3</html>".toByteArray())
        val v4 = Fixture.release(3, "b4", "<html>v4</html>".toByteArray())
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        harness.publish(listOf(v2, v3), 2, etag = "\"e2\"")
        harness.core.sync(SyncTrigger.CALL)
        harness.core.ready()
        harness.publish(listOf(v2, v3, v4), 3, etag = "\"e3\"")
        harness.core.sync(SyncTrigger.CALL, installStrategy = InstallStrategy.NEXT_START)
        for (bundleId in listOf("b2", "b3", "b4")) assertTrue(bundleId, File(harness.loader.projectionDirectory(bundleId), "index.html").isFile)
        harness.loader.served = "b4"
        harness.restart(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        harness.core.handleAppStart()
        val status = harness.core.status()
        assertEquals("b4", status.currentRelease?.bundleId)
        assertEquals("b3", status.fallbackRelease?.bundleId)
        assertTrue(!harness.loader.projectionDirectory("b2").exists())
        assertTrue(File(harness.loader.projectionDirectory("b3"), "index.html").isFile)
        assertTrue(File(harness.loader.projectionDirectory("b4"), "index.html").isFile)
        assertEquals(listOf("b3", "b4"), harness.files.bundleIds())
        assertTrue(!harness.files.hasFile(Hashing.sha256Hex(v2Content)))
        assertTrue(!harness.files.hasFile(Hashing.sha256Hex("js-b2")))
        assertTrue(harness.files.hasFile(Hashing.sha256Hex("<html>v3</html>")))
        assertTrue(harness.files.hasFile(Hashing.sha256Hex("<html>v4</html>")))
    }

    @Test
    fun shouldResetToTheEmbeddedBundleAndKeepTheIdentity() = runBlocking {
        val harness = Harness(Fixture.configuration(installStrategy = InstallStrategy.IMMEDIATE))
        harness.core.setAttributes(mapOf("plan" to "beta"))
        val v2 = Fixture.release(1, "b2", v2Content)
        harness.publish(listOf(v2), 1)
        harness.core.handleAppStart()
        harness.core.sync(SyncTrigger.CALL)
        harness.core.reset()
        val status = harness.core.status()
        assertNull(status.currentRelease)
        assertTrue(status.failedBundleIds.isEmpty())
        assertTrue(!harness.files.hasFile(Hashing.sha256Hex(v2Content)))
        assertNull(harness.loader.loaded.last())
        assertEquals(mapOf("plan" to "beta"), harness.core.deviceResult().attributes)
    }
}
