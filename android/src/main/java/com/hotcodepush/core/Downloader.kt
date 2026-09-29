package com.hotcodepush.core

import java.io.File

sealed class DownloadFailure(message: String) : Exception(message) {
    class InvalidSignature(message: String) : DownloadFailure(message)
    class VerificationFailed(message: String) : DownloadFailure(message)
    class DownloadFailed(message: String) : DownloadFailure(message)

    val reason: FailedReason
        get() = when (this) {
            is InvalidSignature -> FailedReason.INVALID_SIGNATURE
            is VerificationFailed -> FailedReason.VERIFICATION_FAILED
            is DownloadFailed -> FailedReason.DOWNLOAD_FAILED
        }
}

data class DownloadOutcome(val manifest: BundleManifest, val bytes: Long, val packKind: PackKind)

/** Manifest, signature, missing files, pack, verification, files to disk — each step one function. */
class Downloader(
    private val configuration: Configuration,
    private val files: FileStore,
    private val embedded: EmbeddedBundle,
    private val http: HttpClient,
    private val temporaryDirectory: File,
) {
    suspend fun downloadRelease(target: IndexRelease, currentBundleId: String?, progress: (Long, Long) -> Unit): DownloadOutcome {
        val manifest = fetchBundleManifest(target)
        val missing = resolveMissingFiles(manifest)
        var bytes = 0L
        var packKind = PackKind.FILES
        if (missing.isNotEmpty()) {
            resolvePack(manifest, currentBundleId, missing)?.let { (url, kind) ->
                bytes += downloadPack(url, manifest.bundleId, missing.map { it.sha256 }.toSet(), progress)
                packKind = kind
            }
        }
        for (file in resolveMissingFiles(manifest)) bytes += downloadFile(file)
        files.writeManifest(manifest)
        return DownloadOutcome(manifest, bytes, packKind)
    }

    internal suspend fun fetchBundleManifest(target: IndexRelease): BundleManifest {
        val response = try {
            http.get(target.manifestUrl, emptyMap())
        } catch (exception: Exception) {
            throw DownloadFailure.DownloadFailed("The manifest could not be fetched: ${exception.message}")
        }
        if (response.status != 200) throw DownloadFailure.DownloadFailed("HTTP ${response.status} for the manifest")
        val envelope = runCatching { ManifestEnvelope.fromJson(org.json.JSONObject(String(response.body, Charsets.UTF_8))) }.getOrNull()
        val manifest = envelope?.let { runCatching { it.decodeManifest() }.getOrNull() } ?: throw DownloadFailure.VerificationFailed("The manifest could not be parsed")
        verifyManifestSignature(envelope, target.manifestSha256)
        if (manifest.bundleId != target.bundleId) throw DownloadFailure.VerificationFailed("The manifest names another bundle")
        return manifest
    }

    internal fun verifyManifestSignature(envelope: ManifestEnvelope, expectedSha256: String) {
        if (Hashing.sha256Hex(envelope.manifest) != expectedSha256) throw DownloadFailure.VerificationFailed("The manifest's hash does not match the index")
        if (configuration.publicKeys.isNotEmpty()) {
            // TODO(milestone 3, code signing): verify the ed25519 signature over the manifest bytes against `publicKeys`.
            throw DownloadFailure.InvalidSignature("Signature verification is not available in this SDK version")
        }
    }

    internal fun resolveMissingFiles(manifest: BundleManifest): List<BundleManifest.File> = manifest.files.filter { !files.hasFile(it.sha256) && !embedded.has(it.sha256) }

    /** The delta pack against the running bundle where one exists, the full pack otherwise; nothing when the pack would cost more than the files. */
    internal fun resolvePack(manifest: BundleManifest, currentBundleId: String?, missing: List<BundleManifest.File>): Pair<String, PackKind>? {
        manifest.deltas.firstOrNull { it.baseBundleId == currentBundleId }?.let { return it.url to PackKind.DELTA }
        val pack = manifest.pack
        if (pack != null && missing.size > 1) return pack.url to PackKind.FULL
        return null
    }

    internal suspend fun downloadPack(url: String, bundleId: String, wanted: Set<String>, progress: (Long, Long) -> Unit): Long {
        val file = File(temporaryDirectory, "$bundleId-${Hashing.sha256Hex(url).take(16)}.pack")
        try {
            http.download(url, file, progress)
        } catch (failure: DownloadFailure) {
            throw failure
        } catch (exception: Exception) {
            throw DownloadFailure.DownloadFailed("The pack could not be downloaded: ${exception.message}")
        }
        try {
            file.inputStream().buffered().use { input ->
                PackReader.forEachEntry(input) { entry ->
                    if (entry.sha256 in wanted) files.writeFile(Gzip.decompress(entry.body), entry.sha256)
                }
            }
            return file.length()
        } catch (exception: Exception) {
            throw DownloadFailure.VerificationFailed("The pack did not verify: ${exception.message}")
        } finally {
            file.delete()
        }
    }

    internal suspend fun downloadFile(file: BundleManifest.File): Long {
        val url = "${configuration.filesBaseUrl}/apps/${configuration.appId}/files/${file.sha256}"
        val response = try {
            http.get(url, emptyMap())
        } catch (exception: Exception) {
            throw DownloadFailure.DownloadFailed("The file ${file.path} could not be downloaded: ${exception.message}")
        }
        if (response.status != 200) throw DownloadFailure.DownloadFailed("HTTP ${response.status} for ${file.path}")
        val content = runCatching { Gzip.decompress(response.body) }.getOrDefault(response.body)
        try {
            files.writeFile(content, file.sha256)
        } catch (exception: HashMismatchException) {
            throw DownloadFailure.VerificationFailed("The file ${file.path} did not match its hash")
        }
        return response.body.size.toLong()
    }
}
