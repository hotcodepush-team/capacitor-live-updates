package com.hotcodepush.core

import org.json.JSONArray
import org.json.JSONObject

enum class SyncTrigger(val wire: String) { START("start"), RESUME("resume"), INTERVAL("interval"), CALL("call") }

enum class SyncStatus(val wire: String) { UP_TO_DATE("UP_TO_DATE"), AVAILABLE("AVAILABLE"), UPDATED("UPDATED"), SKIPPED("SKIPPED"), FAILED("FAILED") }

enum class SkippedReason {
    INCOMPATIBLE, NOT_TARGETED, NOT_IN_ROLLOUT, UNSUPPORTED_CONDITION, OLDER_THAN_BINARY, CHANNEL_PAUSED,
    SPENDING_CAP_REACHED, RELEASE_REVOKED, FAILED_BEFORE, DEBUG_BUILD, METERED_CONNECTION
}

enum class FailedReason { OFFLINE, UNKNOWN_CHANNEL, INVALID_INDEX, INVALID_SIGNATURE, DOWNLOAD_FAILED, VERIFICATION_FAILED }

enum class RollbackReason { READY_TIMEOUT, CRASHED, REPORTED_BY_APP }

enum class InstallMoment(val wire: String) { NOW("now"), NEXT_START("next-start"), ON_RESUME("on-resume"), MANUAL("manual") }

enum class PackKind(val wire: String) { FULL("full"), DELTA("delta"), STREAMED("streamed"), FILES("files") }

/** One shape for `SyncResult` and `CheckResult`: the status says which fields are set. */
data class SyncResult(
    val status: SyncStatus,
    val release: Release?,
    val reason: String? = null,
    val condition: ConditionType? = null,
    val notes: String? = null,
    val installAt: InstallMoment? = null,
    val downloadBytes: Long? = null,
    val message: String? = null,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("status", status.wire)
        .put("release", release?.toJson() ?: JSONObject.NULL)
        .putIfNotNull("reason", reason)
        .putIfNotNull("condition", condition?.wire)
        .putIfNotNull("notes", notes, nullWhenStatus = status == SyncStatus.UPDATED || status == SyncStatus.AVAILABLE)
        .putIfNotNull("installAt", installAt?.wire)
        .putIfNotNull("downloadBytes", downloadBytes, nullWhenStatus = status == SyncStatus.AVAILABLE)
        .putIfNotNull("message", message)

    companion object {
        fun upToDate(release: Release?) = SyncResult(SyncStatus.UP_TO_DATE, release)
        fun available(release: Release, notes: String?, downloadBytes: Long?) = SyncResult(SyncStatus.AVAILABLE, release, notes = notes, downloadBytes = downloadBytes)
        fun updated(release: Release, notes: String?, installAt: InstallMoment) = SyncResult(SyncStatus.UPDATED, release, notes = notes, installAt = installAt)
        fun skipped(release: Release?, reason: SkippedReason, condition: ConditionType? = null) = SyncResult(SyncStatus.SKIPPED, release, reason = reason.name, condition = condition)
        fun failed(release: Release?, reason: FailedReason, message: String) = SyncResult(SyncStatus.FAILED, release, reason = reason.name, message = message)

        fun fromJson(json: JSONObject) = SyncResult(
            status = SyncStatus.entries.first { it.wire == json.getString("status") },
            release = json.optJSONObject("release")?.let(Release::fromJson),
            reason = json.optNullableString("reason"),
            condition = json.optNullableString("condition")?.let { wire -> ConditionType.entries.firstOrNull { it.wire == wire } },
            notes = json.optNullableString("notes"),
            installAt = json.optNullableString("installAt")?.let { wire -> InstallMoment.entries.firstOrNull { it.wire == wire } },
            downloadBytes = if (json.isNull("downloadBytes")) null else json.optLong("downloadBytes"),
            message = json.optNullableString("message"),
        )
    }
}

data class ReadyResult(val currentRelease: Release?, val previousRelease: Release?, val isRolledBack: Boolean, val rollbackReason: RollbackReason?) {
    fun toJson(): JSONObject = JSONObject()
        .put("currentRelease", currentRelease?.toJson() ?: JSONObject.NULL)
        .put("previousRelease", previousRelease?.toJson() ?: JSONObject.NULL)
        .put("isRolledBack", isRolledBack)
        .putIfNotNull("rollbackReason", rollbackReason?.name)
}

data class LastCheck(val at: Long, val trigger: SyncTrigger, val result: SyncResult) {
    fun toJson(): JSONObject = JSONObject().put("at", Iso8601.format(at)).put("trigger", trigger.wire).put("result", result.toJson())

    companion object {
        fun fromJson(json: JSONObject) = LastCheck(Iso8601.parse(json.getString("at")), SyncTrigger.entries.first { it.wire == json.getString("trigger") }, SyncResult.fromJson(json.getJSONObject("result")))
    }
}

data class StatusResult(
    val currentRelease: Release?,
    val nextRelease: Release?,
    val fallbackRelease: Release?,
    val embeddedBundleId: String?,
    val lastCheck: LastCheck?,
    val indexSequence: Int?,
    val indexFetchedAt: Long?,
    val failedBundleIds: List<String>,
    val lastReportAt: Long?,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("currentRelease", currentRelease?.toJson() ?: JSONObject.NULL)
        .put("nextRelease", nextRelease?.toJson() ?: JSONObject.NULL)
        .put("fallbackRelease", fallbackRelease?.toJson() ?: JSONObject.NULL)
        .put("embeddedBundleId", embeddedBundleId ?: JSONObject.NULL)
        .put("lastCheck", lastCheck?.toJson() ?: JSONObject.NULL)
        .put("index", if (indexSequence != null && indexFetchedAt != null) JSONObject().put("sequence", indexSequence).put("fetchedAt", Iso8601.format(indexFetchedAt)) else JSONObject.NULL)
        .put("failedBundleIds", JSONArray(failedBundleIds))
        .put("lastReportAt", lastReportAt?.let(Iso8601::format) ?: JSONObject.NULL)
}

enum class ChannelSource(val wire: String) { RUNTIME("runtime"), CONFIG("config") }

data class ChannelResult(val id: String, val name: String?, val source: ChannelSource) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("name", name ?: JSONObject.NULL).put("source", source.wire)
}

data class DeviceResult(
    val id: String,
    val platform: String,
    val binaryVersion: String,
    val binaryBuild: String,
    val osVersion: String,
    val sdkVersion: String,
    val fingerprint: String?,
    val channel: ChannelResult,
    val attributes: Map<String, String>,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("platform", platform)
        .put("binaryVersion", binaryVersion)
        .put("binaryBuild", binaryBuild)
        .put("osVersion", osVersion)
        .put("sdkVersion", sdkVersion)
        .put("fingerprint", fingerprint ?: JSONObject.NULL)
        .put("channel", channel.toJson())
        .put("attributes", JSONObject(attributes))
}

data class RolledBackEvent(val from: Release, val to: Release?, val reason: RollbackReason) {
    fun toJson(): JSONObject = JSONObject().put("from", from.toJson()).put("to", to?.toJson() ?: JSONObject.NULL).put("reason", reason.name)
}

internal fun JSONObject.putIfNotNull(key: String, value: Any?, nullWhenStatus: Boolean = false): JSONObject {
    if (value != null) put(key, value) else if (nullWhenStatus) put(key, JSONObject.NULL)
    return this
}
