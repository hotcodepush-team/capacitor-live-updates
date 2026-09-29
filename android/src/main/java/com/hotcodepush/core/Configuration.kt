package com.hotcodepush.core

import org.json.JSONObject

enum class InstallStrategy(val wire: String) {
    NEXT_START("next-start"), IMMEDIATE("immediate"), ON_RESUME("on-resume"), MANUAL("manual");

    companion object {
        fun fromWire(value: String?): InstallStrategy? = entries.firstOrNull { it.wire == value }
    }
}

enum class ReadySignal(val wire: String) {
    RENDER("render"), CALL("call");

    companion object {
        fun fromWire(value: String?): ReadySignal? = entries.firstOrNull { it.wire == value }
    }
}

enum class NetworkPolicy(val wire: String) {
    ANY("any"), UNMETERED("unmetered");

    companion object {
        fun fromWire(value: String?): NetworkPolicy? = entries.firstOrNull { it.wire == value }
    }
}

/** The resource file: the project's `hotcodepush.json` plus what only the embed step knows. */
data class Configuration(
    val appId: String,
    val channelId: String,
    val autoSync: Boolean,
    val syncInterval: Double,
    val installStrategy: InstallStrategy,
    val minimumBackgroundDuration: Double,
    val readySignal: ReadySignal,
    val readyTimeout: Double,
    val network: NetworkPolicy,
    val enabledInDebugBuilds: Boolean,
    val publicKeys: List<String>,
    val builtAt: Long,
    val fingerprint: String?,
    val embeddedBundleManifest: BundleManifest,
    val embeddedBundleId: String?,
    val filesBaseUrl: String,
    val updatesBaseUrl: String,
) {
    companion object {
        const val DEFAULT_FILES_BASE_URL = "https://files.hotcodepush.com"
        const val DEFAULT_UPDATES_BASE_URL = "https://updates.hotcodepush.com"

        fun decode(text: String): Configuration = fromJson(JSONObject(text))

        fun fromJson(json: JSONObject) = Configuration(
            appId = json.getString("appId"),
            channelId = json.getString("channelId"),
            autoSync = json.optBoolean("autoSync", true),
            syncInterval = json.optDouble("syncInterval", 900.0),
            installStrategy = InstallStrategy.fromWire(json.optNullableString("installStrategy")) ?: InstallStrategy.NEXT_START,
            minimumBackgroundDuration = json.optDouble("minimumBackgroundDuration", 300.0),
            readySignal = ReadySignal.fromWire(json.optNullableString("readySignal")) ?: ReadySignal.RENDER,
            readyTimeout = maxOf(1.0, json.optDouble("readyTimeout", 10.0)),
            network = NetworkPolicy.fromWire(json.optNullableString("network")) ?: NetworkPolicy.ANY,
            enabledInDebugBuilds = json.optBoolean("enabledInDebugBuilds", true),
            publicKeys = json.optJSONArray("publicKeys").toStringList(),
            builtAt = Iso8601.parse(json.getString("builtAt")),
            fingerprint = json.optNullableString("fingerprint"),
            embeddedBundleManifest = BundleManifest.fromJson(json.getJSONObject("embeddedBundleManifest")),
            embeddedBundleId = json.optNullableString("embeddedBundleId"),
            filesBaseUrl = json.optNullableString("filesBaseUrl") ?: DEFAULT_FILES_BASE_URL,
            updatesBaseUrl = json.optNullableString("updatesBaseUrl") ?: DEFAULT_UPDATES_BASE_URL,
        )
    }
}
