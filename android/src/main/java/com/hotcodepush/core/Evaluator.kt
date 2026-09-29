package com.hotcodepush.core

/** The facts a device evaluates an index against. */
data class DeviceInfo(
    val deviceId: String,
    val binaryVersion: String,
    val binaryBuild: String,
    val osVersion: String,
    val fingerprint: String?,
    val attributes: Map<String, String>,
    val builtAt: Long,
    val reportedAt: Long?,
    val failedBundleIds: List<String>,
    val currentRelease: Release?,
)

data class Skip(val reason: SkippedReason, val condition: ConditionType? = null)

/** What the device should do with an index. */
sealed class Evaluation {
    /** Nothing newer than what runs. */
    object UpToDate : Evaluation()

    /** Take this release: newer and eligible, or the eligible release below a revoked one. */
    data class Update(val release: IndexRelease) : Evaluation()

    /** Return to the embedded bundle: the running release is revoked or the directive says so. */
    data class Revert(val reason: SkippedReason) : Evaluation()

    /** A newer release exists and this device will not take it now. */
    data class Skipped(val newest: IndexRelease, val skip: Skip) : Evaluation()

    /** The whole index is off for this device: paused or beyond the cap. */
    data class Unavailable(val reason: SkippedReason) : Evaluation()
}

/** The shared evaluator: the same rules in TypeScript, Swift and Kotlin, proven equal by the fixture suite. */
object Evaluator {
    fun evaluate(index: ChannelIndex, device: DeviceInfo): Evaluation {
        if (index.isPaused) return Evaluation.Unavailable(SkippedReason.CHANNEL_PAUSED)
        val cappedAt = index.cappedAt
        if (cappedAt != null && (device.reportedAt == null || device.reportedAt > cappedAt)) return Evaluation.Unavailable(SkippedReason.SPENDING_CAP_REACHED)
        val current = device.currentRelease
        val directive = index.rollBackToEmbedded
        if (current != null && directive != null && current.number <= directive.aboveNumber) return Evaluation.Revert(SkippedReason.RELEASE_REVOKED)
        val releases = index.releases.sortedByDescending { it.number }
        if (current != null && current.id in index.revokedReleaseIds) {
            val older = releases.filter { it.number < current.number }
            older.firstOrNull { eligibility(it, index, device) == null }?.let { return Evaluation.Update(it) }
            return Evaluation.Revert(SkippedReason.RELEASE_REVOKED)
        }
        val newer = releases.filter { current == null || it.number > current.number }
        var firstSkip: Pair<IndexRelease, Skip>? = null
        for (candidate in newer) {
            val skip = eligibility(candidate, index, device)
            if (skip == null) return Evaluation.Update(candidate)
            if (firstSkip == null) firstSkip = candidate to skip
        }
        firstSkip?.let { (newest, skip) -> return Evaluation.Skipped(newest, skip) }
        return Evaluation.UpToDate
    }

    /** `null` when the device may take the release, else why not. */
    fun eligibility(release: IndexRelease, index: ChannelIndex, device: DeviceInfo): Skip? {
        if (release.id in index.revokedReleaseIds) return Skip(SkippedReason.RELEASE_REVOKED)
        if (release.createdAt < device.builtAt) return Skip(SkippedReason.OLDER_THAN_BINARY)
        if (release.bundleId in device.failedBundleIds) return Skip(SkippedReason.FAILED_BEFORE)
        for (condition in release.conditions) {
            evaluate(condition, device)?.let { return it }
        }
        if (Hashing.rolloutBucket(device.deviceId, release.id) >= release.rollout) return Skip(SkippedReason.NOT_IN_ROLLOUT)
        return null
    }

    internal fun evaluate(condition: Condition, device: DeviceInfo): Skip? = when (condition) {
        is Condition.Binary -> if (VersionRange.parse(condition.range)?.contains(device.binaryVersion) == true) null else Skip(SkippedReason.INCOMPATIBLE, ConditionType.BINARY)
        is Condition.Os -> if (VersionRange.parse(condition.range)?.contains(device.osVersion) == true) null else Skip(SkippedReason.INCOMPATIBLE, ConditionType.OS)
        is Condition.Runtime -> Skip(SkippedReason.INCOMPATIBLE, ConditionType.RUNTIME)
        is Condition.Fingerprint -> if (device.fingerprint == condition.hash) null else Skip(SkippedReason.INCOMPATIBLE, ConditionType.FINGERPRINT)
        is Condition.Device -> if (Hashing.sha256Hex(device.deviceId) in condition.hashedIds) null else Skip(SkippedReason.NOT_TARGETED, ConditionType.DEVICE)
        is Condition.Attribute -> {
            val value = device.attributes[condition.key]
            if (value != null && Hashing.attributeHash(condition.key, value) == condition.valueSha256) null else Skip(SkippedReason.NOT_TARGETED, ConditionType.ATTRIBUTE)
        }
        is Condition.Unknown -> Skip(SkippedReason.UNSUPPORTED_CONDITION)
    }
}
