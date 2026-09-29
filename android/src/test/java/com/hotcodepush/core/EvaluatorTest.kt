package com.hotcodepush.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class EvaluatorTest {
    private val device = DeviceInfo("d1", "2.4.1", "57", "17.4", "fp1:abc", mapOf("plan" to "beta"), Fixture.BUILT_AT, null, emptyList(), null)

    private fun release(number: Int, conditions: List<Condition> = emptyList(), rollout: Int = 100, createdAt: Long = Fixture.BUILT_AT + 1000, bundleId: String? = null) =
        IndexRelease("r$number", number, createdAt, false, null, rollout, conditions, bundleId ?: "b$number", "1.0.$number", "https://files.test/m$number", "", 1)

    @Test
    fun shouldTakeTheNewestEligibleRelease() {
        val index = Fixture.index(1, listOf(release(1), release(3), release(2)))
        assertEquals(Evaluation.Update(release(3)), Evaluator.evaluate(index, device))
    }

    @Test
    fun shouldBeUpToDateWhenNothingIsNewerThanTheRunningRelease() {
        val index = Fixture.index(1, listOf(release(1), release(2)))
        assertEquals(Evaluation.UpToDate, Evaluator.evaluate(index, device.copy(currentRelease = release(2).release)))
    }

    @Test
    fun shouldSkipWhenTheChannelIsPaused() {
        assertEquals(Evaluation.Unavailable(SkippedReason.CHANNEL_PAUSED), Evaluator.evaluate(Fixture.index(1, listOf(release(1)), isPaused = true), device))
    }

    @Test
    fun shouldSkipBeyondTheSpendingCapWhenTheReportIsAfterTheCap() {
        val cappedAt = Fixture.BUILT_AT + 100_000
        val index = Fixture.index(1, listOf(release(1)), cappedAt = cappedAt)
        assertEquals(Evaluation.Update(release(1)), Evaluator.evaluate(index, device.copy(reportedAt = cappedAt - 1)))
        assertEquals(Evaluation.Unavailable(SkippedReason.SPENDING_CAP_REACHED), Evaluator.evaluate(index, device))
    }

    @Test
    fun shouldSkipAReleaseOlderThanTheBinary() {
        val old = release(1, createdAt = Fixture.BUILT_AT - 1)
        assertEquals(Evaluation.Skipped(old, Skip(SkippedReason.OLDER_THAN_BINARY)), Evaluator.evaluate(Fixture.index(1, listOf(old)), device))
    }

    @Test
    fun shouldSkipABundleThatFailedBefore() {
        assertEquals(Evaluation.Skipped(release(1), Skip(SkippedReason.FAILED_BEFORE)), Evaluator.evaluate(Fixture.index(1, listOf(release(1))), device.copy(failedBundleIds = listOf("b1"))))
    }

    @Test
    fun shouldEvaluateEveryConditionType() {
        assertNull(Evaluator.evaluate(Condition.Binary(">=2.3.0 <3.0.0"), device))
        assertEquals(Skip(SkippedReason.INCOMPATIBLE, ConditionType.BINARY), Evaluator.evaluate(Condition.Binary("<2.4.1 || >2.4.1"), device))
        assertNull(Evaluator.evaluate(Condition.Os("17.x"), device))
        assertEquals(Skip(SkippedReason.INCOMPATIBLE, ConditionType.OS), Evaluator.evaluate(Condition.Os(">=18"), device))
        assertNull(Evaluator.evaluate(Condition.Fingerprint("fp1:abc"), device))
        assertEquals(Skip(SkippedReason.INCOMPATIBLE, ConditionType.FINGERPRINT), Evaluator.evaluate(Condition.Fingerprint("fp1:other"), device))
        assertEquals(Skip(SkippedReason.INCOMPATIBLE, ConditionType.RUNTIME), Evaluator.evaluate(Condition.Runtime("1"), device))
        assertNull(Evaluator.evaluate(Condition.Device(listOf(Hashing.sha256Hex("d1"))), device))
        assertEquals(Skip(SkippedReason.NOT_TARGETED, ConditionType.DEVICE), Evaluator.evaluate(Condition.Device(listOf(Hashing.sha256Hex("d2"))), device))
        assertNull(Evaluator.evaluate(Condition.Attribute("plan", Hashing.attributeHash("plan", "beta")), device))
        assertEquals(Skip(SkippedReason.NOT_TARGETED, ConditionType.ATTRIBUTE), Evaluator.evaluate(Condition.Attribute("plan", Hashing.attributeHash("plan", "pro")), device))
        assertEquals(Skip(SkippedReason.UNSUPPORTED_CONDITION), Evaluator.evaluate(Condition.Unknown("geo"), device))
    }

    @Test
    fun shouldFailClosedOnAnUnknownConditionType() {
        assertEquals(Condition.Unknown("geo"), Condition.fromJson(JSONObject("""{"type":"geo","country":"DE"}""")))
    }

    @Test
    fun shouldPlaceADeviceInARolloutBucketStably() {
        val bucket = Hashing.rolloutBucket("d1", "r1")
        assertEquals(bucket, Hashing.rolloutBucket("d1", "r1"))
        assertTrue(bucket in 0..99)
        assertEquals(Evaluation.Skipped(release(1, rollout = bucket), Skip(SkippedReason.NOT_IN_ROLLOUT)), Evaluator.evaluate(Fixture.index(1, listOf(release(1, rollout = bucket))), device))
        assertEquals(Evaluation.Update(release(1, rollout = bucket + 1)), Evaluator.evaluate(Fixture.index(1, listOf(release(1, rollout = bucket + 1))), device))
    }

    @Test
    fun shouldFallToAnOlderEligibleReleaseWhenTheRunningOneIsRevoked() {
        val running = device.copy(currentRelease = release(3).release)
        assertEquals(Evaluation.Update(release(2)), Evaluator.evaluate(Fixture.index(2, listOf(release(1), release(2), release(3)), revoked = listOf("r3")), running))
        assertEquals(Evaluation.Revert(SkippedReason.RELEASE_REVOKED), Evaluator.evaluate(Fixture.index(3, listOf(release(1), release(2), release(3)), revoked = listOf("r1", "r2", "r3")), running))
    }

    @Test
    fun shouldResetToTheEmbeddedBundleOnTheDirective() {
        val running = device.copy(currentRelease = release(2).release)
        assertEquals(Evaluation.Revert(SkippedReason.RELEASE_REVOKED), Evaluator.evaluate(Fixture.index(2, listOf(release(2)), rollBackToEmbedded = RollBackToEmbedded(2, null)), running))
        assertEquals(Evaluation.UpToDate, Evaluator.evaluate(Fixture.index(2, listOf(release(2)), rollBackToEmbedded = RollBackToEmbedded(1, null)), running))
    }

    @Test
    fun shouldTakeAnOlderReleaseWhenTheNewestIsIncompatible() {
        assertEquals(Evaluation.Update(release(1)), Evaluator.evaluate(Fixture.index(1, listOf(release(1), release(2, conditions = listOf(Condition.Os(">=18"))))), device))
    }
}

class VersionRangeTest {
    @Test
    fun shouldParseComparatorsWildcardsAndAlternatives() {
        assertTrue(VersionRange.parse(">=2.3.0 <3.0.0")!!.contains("2.4.1"))
        assertTrue(!VersionRange.parse(">=2.3.0 <3.0.0")!!.contains("3.0.0"))
        assertTrue(VersionRange.parse("2.x")!!.contains("2.9.9"))
        assertTrue(!VersionRange.parse("2.x")!!.contains("3.0.0"))
        assertTrue(VersionRange.parse("2.4.x")!!.contains("2.4.7"))
        assertTrue(!VersionRange.parse("2.4.x")!!.contains("2.5.0"))
        assertTrue(VersionRange.parse("14")!!.contains("14.2"))
        assertTrue(VersionRange.parse("<2.4.1 || >2.4.1")!!.contains("2.4.0"))
        assertTrue(!VersionRange.parse("<2.4.1 || >2.4.1")!!.contains("2.4.1"))
        assertTrue(VersionRange.parse("2.4.1")!!.contains("2.4.1"))
        assertTrue(VersionRange.parse(">=1.0.0")!!.contains("1.0.0-beta.1"))
    }

    @Test
    fun shouldRejectWhatItCannotParse() {
        assertNull(VersionRange.parse("^2.0.0"))
        assertNull(VersionRange.parse("latest"))
        assertNull(Version.parse("a.b"))
        assertTrue(!VersionRange.parse(">=1")!!.contains("not a version"))
    }
}

class PackTest {
    @Test
    fun shouldRoundTripEntriesThroughTheUstarFormat() {
        val content = "hello".toByteArray()
        val entries = listOf(PackEntry(Hashing.sha256Hex(content), Gzip.compress(content)), PackEntry(Hashing.sha256Hex("x"), ByteArray(0)))
        val pack = PackWriter.pack(entries)
        assertEquals(0, pack.size % 512)
        val read = PackReader.entries(pack)
        assertEquals(entries.map { it.sha256 }, read.map { it.sha256 })
        assertEquals("hello", String(Gzip.decompress(read[0].body)))
        assertEquals("ustar", String(pack, 257, 5))
    }

    @Test(expected = PackFormatException::class)
    fun shouldRejectATruncatedPack() {
        PackReader.entries(PackWriter.pack(listOf(PackEntry("abc", ByteArray(700)))).copyOf(600))
    }
}

class StateStoreTest {
    @Test
    fun shouldKeepTheIdentityKeysAndDropTheCacheOnAnUnknownStateVersion() {
        val store = InMemoryStore()
        store.putString("hotcodepush.stateVersion", "9")
        store.putString("hotcodepush.currentRelease", Release("r1", 1, "b1", "1", false).toJson().toString())
        store.putString("hotcodepush.deviceId", "device-1")
        val state = StateStore(store)
        assertEquals("device-1", state.deviceId)
        assertNull(state.currentRelease)
        assertEquals("1", store.getString("hotcodepush.stateVersion"))
    }

    @Test
    fun shouldDropTheCacheWhenAValueDoesNotParse() {
        val store = InMemoryStore()
        val state = StateStore(store)
        state.nextRelease = Release("r1", 1, "b1", "1", false)
        store.putString("hotcodepush.currentRelease", "not json")
        assertNull(state.currentRelease)
        assertNull(state.nextRelease)
        assertEquals(36, StateStore(store).deviceId.length)
    }
}

class FileStoreTest {
    @Test(expected = HashMismatchException::class)
    fun shouldRefuseAFileWhoseHashDoesNotMatch() {
        FileStore(Files.createTempDirectory("fs").toFile()).writeFile("a".toByteArray(), "0")
    }

    @Test
    fun shouldCollectWhatNoKeptBundleLists() {
        val files = FileStore(Files.createTempDirectory("fs").toFile())
        val kept = BundleManifest("kept", "a", "1", 0, listOf(BundleManifest.File("a", Hashing.sha256Hex("a"), 1)), null, emptyList())
        val gone = BundleManifest("gone", "a", "1", 0, listOf(BundleManifest.File("b", Hashing.sha256Hex("b"), 1)), null, emptyList())
        files.writeManifest(kept)
        files.writeManifest(gone)
        files.writeFile("a".toByteArray(), Hashing.sha256Hex("a"))
        files.writeFile("b".toByteArray(), Hashing.sha256Hex("b"))
        files.deleteUnusedFiles(setOf("kept"))
        assertEquals(listOf("kept"), files.bundleIds())
        assertTrue(files.hasFile(Hashing.sha256Hex("a")))
        assertTrue(!files.hasFile(Hashing.sha256Hex("b")))
    }

    @Test
    fun shouldProjectABundleByPathFromTheStoreAndTheEmbeddedFiles() {
        val root = Files.createTempDirectory("fs").toFile()
        val files = FileStore(File(root, "store"))
        val embedded = InMemoryEmbeddedBundle().apply { this.files[Hashing.sha256Hex("embedded")] = "embedded".toByteArray() }
        files.writeFile("new".toByteArray(), Hashing.sha256Hex("new"))
        val manifest = BundleManifest("b", "a", "1", 0, listOf(BundleManifest.File("index.html", Hashing.sha256Hex("new"), 3), BundleManifest.File("assets/logo.svg", Hashing.sha256Hex("embedded"), 8)), null, emptyList())
        val www = File(root, "www")
        BundleProjection.project(manifest, files, embedded, www)
        assertEquals("new", File(www, "index.html").readText())
        assertEquals("embedded", File(www, "assets/logo.svg").readText())
    }
}
