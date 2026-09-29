package com.hotcodepush.core

import java.io.File

/** What the platform knows about the binary and the OS. */
data class DeviceFacts(
    val platform: String,
    val binaryVersion: String,
    val binaryBuild: String,
    val osVersion: String,
    val sdkVersion: String,
    val isDebugBuild: Boolean,
)

/** The framework's side of running a bundle: where a bundle is laid out and which one the WebView serves. */
interface BundleLoader {
    /** The directory a bundle is laid out in by path for the WebView. */
    fun projectionDirectory(bundleId: String): File

    /** Records which bundle the framework loads at the next start; `null` is the embedded bundle. */
    fun persistServedBundle(bundleId: String?)

    /** Points the WebView at the bundle now and reloads it; `null` is the embedded bundle. */
    fun loadServedBundle(bundleId: String?)

    /** The bundle the WebView runs right now, `null` for the embedded bundle. */
    fun servedBundleId(): String?

    /** Whether the connection is metered or constrained, for the `unmetered` network policy. */
    fun isConnectionMetered(): Boolean
}

interface CoreListener {
    fun syncStarted(trigger: SyncTrigger)
    fun synced(result: SyncResult, trigger: SyncTrigger)
    fun downloadProgress(releaseId: String, downloadedBytes: Long, totalBytes: Long)
    fun rolledBack(event: RolledBackEvent)
}

fun interface ScheduledTask {
    fun cancel()
}

fun interface Scheduler {
    fun schedule(afterSeconds: Double, block: () -> Unit): ScheduledTask
}

fun interface Clock {
    fun now(): Long
}

/** The two programming mistakes the SDK reports with a plain error: nothing an app handles. */
class PlainException(message: String) : Exception(message)

object AttributeRules {
    private val keyPattern = Regex("^[A-Za-z0-9_.-]{1,64}$")

    fun validate(key: String, value: String) {
        if (!keyPattern.matches(key)) throw PlainException("An attribute key is an identifier of letters, digits, '_', '-' and '.', at most 64 characters: $key")
        if (value.length > 256 || value.any { it.code < 0x20 || it.code == 0x7F }) throw PlainException("An attribute value is a printable string without control characters, at most 256 characters")
    }
}
