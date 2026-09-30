package com.hotcodepush.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DownloaderTest {
    @Test
    fun shouldRefuseAManifestUrlOffTheConfiguredHosts() {
        val harness = DownloaderHarness()
        val release = harness.publish(DownloaderHarness.manifest(mapOf("index.html" to "v2".toByteArray())), manifestUrl = "https://elsewhere.test/manifest.json")
        assertEquals(FailedReason.VERIFICATION_FAILED, harness.downloadFailure(release)?.reason)
        assertTrue(harness.http.requests.isEmpty())
    }

    @Test
    fun shouldRefuseAPackUrlOffTheConfiguredHosts() {
        val harness = DownloaderHarness()
        val manifest = DownloaderHarness.manifest(mapOf("index.html" to "v2".toByteArray(), "app.js" to "js".toByteArray()), packUrl = "https://elsewhere.test/pack")
        assertEquals(FailedReason.VERIFICATION_FAILED, harness.downloadFailure(harness.publish(manifest))?.reason)
        assertEquals(listOf(DownloaderHarness.MANIFEST_URL), harness.http.requests.map { it.first })
    }

    @Test
    fun shouldRefuseAManifestPathThatClimbsOutOfTheServedTree() {
        val harness = DownloaderHarness()
        val failure = harness.downloadFailure(harness.publish(DownloaderHarness.manifest(mapOf("../../escape.html" to "v2".toByteArray()))))
        assertEquals(FailedReason.VERIFICATION_FAILED, failure?.reason)
        assertTrue(harness.files.bundleIds().isEmpty())
        assertFalse(File(harness.root, "escape.html").exists())
    }
}

/** A downloader over fakes, in a fresh temporary directory. */
class DownloaderHarness {
    val root: File = Files.createTempDirectory("hotcodepush-tests").toFile()
    val http = FakeHttpClient()
    val files = FileStore(File(root, "store"))
    val downloader = Downloader(Fixture.configuration(), files, InMemoryEmbeddedBundle(), http, File(root, "tmp"))

    /** Serves the manifest where the index entry says it is and returns that entry. */
    fun publish(manifest: BundleManifest, manifestUrl: String = MANIFEST_URL): IndexRelease {
        val json = manifest.toJson().toString()
        http.stubJson(manifestUrl, ManifestEnvelope(json, null).toJson())
        return IndexRelease("r2", 2, manifest.createdAt, false, null, 100, emptyList(), manifest.bundleId, manifest.version, manifestUrl, Hashing.sha256Hex(json), 0)
    }

    fun downloadFailure(release: IndexRelease): DownloadFailure? = runBlocking {
        try {
            downloader.downloadRelease(release, null) { _, _ -> }
            null
        } catch (failure: DownloadFailure) {
            failure
        }
    }

    companion object {
        const val BUNDLE_ID = "b2"
        const val MANIFEST_URL = "${Fixture.FILES_BASE_URL}/apps/${Fixture.APP_ID}/bundles/$BUNDLE_ID/manifest.json"
        const val PACK_URL = "${Fixture.FILES_BASE_URL}/apps/${Fixture.APP_ID}/bundles/$BUNDLE_ID/pack"

        fun manifest(files: Map<String, ByteArray>, packUrl: String = PACK_URL, packSizeBytes: Long = 0): BundleManifest {
            val entries = files.toSortedMap().map { (path, content) -> BundleManifest.File(path, Hashing.sha256Hex(content), content.size.toLong()) }
            return BundleManifest(BUNDLE_ID, Fixture.APP_ID, "1.2.0", Fixture.BUILT_AT, entries, BundleManifest.Pack(packUrl, packSizeBytes), emptyList())
        }
    }
}
