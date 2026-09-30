package com.hotcodepush.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

/** The state machine every framework shares: three named releases, a readiness gate and one sync cycle. */
class Core(
    val configuration: Configuration,
    private val device: DeviceFacts,
    store: KeyValueStore,
    private val files: FileStore,
    private val embedded: EmbeddedBundle,
    http: HttpClient,
    private val loader: BundleLoader,
    private val listener: CoreListener,
    private val scheduler: Scheduler,
    private val clock: Clock,
    private val scope: CoroutineScope,
    temporaryDirectory: File,
) {
    private val state = StateStore(store)
    private val downloader = Downloader(configuration, files, embedded, http, temporaryDirectory)
    private val httpClient = http
    private val lock = Mutex()

    private var readyTimer: ScheduledTask? = null
    private var intervalTimer: ScheduledTask? = null
    private var runningSync: Deferred<SyncResult>? = null
    private var isRestartAllowed = true
    private var queuedRestart: (() -> Unit)? = null
    private var isStartSyncPending = false
    private var backgroundedAt: Long? = null
    private var resolvedChannelName: Pair<String, String>? = null

    // Lifecycle

    /** The start of a run: the binary's floor, the previous run's verdict, the pending switch, the gate, then the cleanup. */
    suspend fun handleAppStart() = lock.withLock {
        state.lastRollback = null
        if (state.lastBuiltAt != configuration.builtAt) dropReleasesOfPreviousBinary()
        if (isCurrentReleaseUnconfirmed()) {
            rollbackCurrentRelease(RollbackReason.CRASHED)
            return
        }
        val next = state.nextRelease
        if (next != null && (configuration.installStrategy == InstallStrategy.NEXT_START || next.isMandatory || loader.servedBundleId() == next.bundleId)) switchToNextRelease()
        loadBundle()
        if (isCurrentReleaseUnconfirmed()) {
            startReadyTimer()
            isStartSyncPending = true
        } else if (configuration.autoSync) {
            scope.launch { sync(SyncTrigger.START) }
        }
        deleteUnusedFiles()
    }

    /** The first render, the readiness signal when `readySignal` is `render`. */
    suspend fun handleRendered() = lock.withLock {
        if (configuration.readySignal == ReadySignal.RENDER) confirmCurrentRelease()
    }

    suspend fun ready(): ReadyResult = lock.withLock {
        confirmCurrentRelease()
        val rollback = state.lastRollback
        state.lastRollback = null
        ReadyResult(state.currentRelease, rollback?.from, rollback != null, rollback?.reason)
    }

    /** The background: the interval timer stops, since interval syncs belong to the foreground, and the moment is kept for `on-resume`. */
    suspend fun handleAppPause() = lock.withLock {
        backgroundedAt = clock.now()
        intervalTimer?.cancel()
        intervalTimer = null
    }

    /** A resume installs an `on-resume` release after enough time in the background, else syncs when the interval has passed. */
    suspend fun handleAppResume() = lock.withLock {
        val backgroundDuration = backgroundedAt?.let { (clock.now() - it) / 1000.0 }
        backgroundedAt = null
        if (backgroundDuration != null && configuration.installStrategy == InstallStrategy.ON_RESUME && state.nextRelease != null && backgroundDuration >= configuration.minimumBackgroundDuration) {
            installNextRelease()
            return
        }
        if (!configuration.autoSync) return
        val elapsedSeconds = state.lastSyncAt?.let { (clock.now() - it) / 1000.0 }
        if (elapsedSeconds == null || elapsedSeconds >= configuration.syncInterval) {
            scope.launch { sync(SyncTrigger.RESUME) }
            return
        }
        scheduleIntervalSync(configuration.syncInterval - elapsedSeconds)
    }

    // Sync

    suspend fun sync(trigger: SyncTrigger, installStrategy: InstallStrategy? = null, network: NetworkPolicy? = null): SyncResult {
        val running = lock.withLock {
            runningSync ?: scope.async { performSync(trigger, installStrategy, network, isCheckOnly = false) }.also { runningSync = it }
        }
        val result = running.await()
        lock.withLock { if (runningSync === running) runningSync = null }
        return result
    }

    suspend fun check(): SyncResult {
        lock.withLock { runningSync }?.await()
        return performSync(SyncTrigger.CALL, null, null, isCheckOnly = true)
    }

    private suspend fun performSync(trigger: SyncTrigger, installStrategy: InstallStrategy?, network: NetworkPolicy?, isCheckOnly: Boolean): SyncResult {
        if (!isCheckOnly) listener.syncStarted(trigger)
        val result = resolveSync(installStrategy, network, isCheckOnly)
        lock.withLock {
            state.lastCheck = LastCheck(clock.now(), trigger, result)
            if (!isCheckOnly) {
                state.lastSyncAt = clock.now()
                scheduleIntervalSync(configuration.syncInterval)
            }
        }
        if (!isCheckOnly) listener.synced(result, trigger)
        return result
    }

    private suspend fun resolveSync(installStrategy: InstallStrategy?, network: NetworkPolicy?, isCheckOnly: Boolean): SyncResult {
        val current = state.currentRelease
        if (device.isDebugBuild && !configuration.enabledInDebugBuilds) return SyncResult.skipped(current, SkippedReason.DEBUG_BUILD)
        val channelId = resolveChannelId() ?: return SyncResult.failed(current, FailedReason.UNKNOWN_CHANNEL, "The channel set at runtime is not in the app's channels index")
        val index = when (val fetch = fetchChannelIndex(channelId)) {
            is IndexFetch.Index -> fetch.index
            IndexFetch.Offline -> return SyncResult.failed(current, FailedReason.OFFLINE, "The channel index could not be fetched and no cached copy exists")
            is IndexFetch.Invalid -> return SyncResult.failed(current, FailedReason.INVALID_INDEX, fetch.message)
            IndexFetch.Absent -> return SyncResult.upToDate(current)
        }
        return when (val evaluation = Evaluator.evaluate(index, deviceInfo())) {
            is Evaluation.UpToDate -> SyncResult.upToDate(current)
            is Evaluation.Available -> {
                lock.withLock { recordChecked(evaluation.release, index, SyncStatus.AVAILABLE, null) }
                if (isCheckOnly) SyncResult.available(evaluation.release.release, evaluation.release.notes, evaluation.release.sizeBytes)
                else install(evaluation.release, evaluation.isMandatory, installStrategy, network)
            }
            is Evaluation.Skipped -> when {
                evaluation.reason != SkippedReason.RELEASE_REVOKED -> {
                    evaluation.release?.let { release -> lock.withLock { recordChecked(release, index, SyncStatus.SKIPPED, Skip(evaluation.reason, evaluation.condition)) } }
                    SyncResult.skipped(evaluation.release?.release, evaluation.reason, evaluation.condition)
                }
                isCheckOnly -> SyncResult.skipped(evaluation.release?.release, SkippedReason.RELEASE_REVOKED)
                evaluation.release == null -> {
                    lock.withLock { revertToEmbedded() }
                    SyncResult.skipped(null, SkippedReason.RELEASE_REVOKED)
                }
                else -> {
                    val outcome = install(evaluation.release, true, null, network)
                    if (outcome.status == SyncStatus.FAILED) outcome else SyncResult.skipped(evaluation.release.release, SkippedReason.RELEASE_REVOKED)
                }
            }
        }
    }

    private suspend fun install(target: IndexRelease, isMandatory: Boolean, installStrategy: InstallStrategy?, network: NetworkPolicy?): SyncResult {
        val release = target.release
        val current = state.currentRelease
        if (current != null && current.bundleId == target.bundleId) {
            lock.withLock { adoptInPlace(release) }
            return SyncResult.updated(release, target.notes, InstallMoment.NOW)
        }
        val strategy = if (isMandatory) InstallStrategy.IMMEDIATE else installStrategy ?: configuration.installStrategy
        val next = state.nextRelease
        if (next != null && next.bundleId == target.bundleId) {
            val manifest = files.readManifest(next.bundleId)
            if (manifest != null && files.isComplete(manifest, embedded)) return lock.withLock { applyDownloaded(release, target.notes, strategy) }
        }
        if ((network ?: configuration.network) == NetworkPolicy.UNMETERED && loader.isConnectionMetered()) return SyncResult.skipped(release, SkippedReason.METERED_CONNECTION)
        try {
            val outcome = downloader.downloadRelease(target, current?.bundleId) { downloaded, total -> listener.downloadProgress(target.id, downloaded, total) }
            BundleProjection.project(outcome.manifest, files, embedded, loader.projectionDirectory(target.bundleId))
            lock.withLock { enqueueDeviceEvent(DeviceEvent.downloaded(target.id, target.bundleId, outcome.bytes, outcome.packKind)) }
        } catch (failure: DownloadFailure) {
            lock.withLock { enqueueDeviceEvent(DeviceEvent.failed(target.id, failure.reason.name)) }
            return SyncResult.failed(release, failure.reason, failure.message ?: "")
        } catch (exception: Exception) {
            lock.withLock { enqueueDeviceEvent(DeviceEvent.failed(target.id, FailedReason.DOWNLOAD_FAILED.name)) }
            return SyncResult.failed(release, FailedReason.DOWNLOAD_FAILED, exception.message ?: "")
        }
        return lock.withLock { applyDownloaded(release, target.notes, strategy) }
    }

    /** Choosing and applying are two acts: the strategy is a policy over the four functions. */
    private fun applyDownloaded(release: Release, notes: String?, strategy: InstallStrategy): SyncResult {
        setNextRelease(release)
        return when (strategy) {
            InstallStrategy.IMMEDIATE -> {
                installNextRelease()
                SyncResult.updated(release, notes, InstallMoment.NOW)
            }
            InstallStrategy.NEXT_START -> {
                loader.persistServedBundle(release.bundleId)
                SyncResult.updated(release, notes, InstallMoment.NEXT_START)
            }
            InstallStrategy.ON_RESUME -> SyncResult.updated(release, notes, InstallMoment.ON_RESUME)
            InstallStrategy.MANUAL -> SyncResult.updated(release, notes, InstallMoment.MANUAL)
        }
    }

    suspend fun apply() = lock.withLock {
        if (state.nextRelease == null) return
        switchToNextRelease()
        reloadApp()
    }

    suspend fun rollback(reason: String?) = lock.withLock {
        if (state.currentRelease != null) rollbackCurrentRelease(RollbackReason.REPORTED_BY_APP)
    }

    suspend fun reset() = lock.withLock {
        stopReadyTimer()
        state.currentRelease = null
        state.nextRelease = null
        state.fallbackRelease = null
        state.failedBundleIds = emptyList()
        state.lastRollback = null
        files.bundleIds().forEach(loader::deleteProjection)
        files.deleteEverything()
        loader.persistServedBundle(null)
        reloadApp()
    }

    suspend fun setRestartAllowed(allowed: Boolean) = lock.withLock {
        isRestartAllowed = allowed
        val restart = queuedRestart ?: return
        if (!allowed) return
        queuedRestart = null
        restart()
    }

    // State

    fun status(): StatusResult {
        val cached = state.cachedIndex
        return StatusResult(
            currentRelease = state.currentRelease,
            nextRelease = state.nextRelease,
            fallbackRelease = state.fallbackRelease,
            embeddedBundleId = configuration.embeddedBundleId,
            lastCheck = state.lastCheck,
            indexSequence = cached?.body?.sequence,
            indexFetchedAt = cached?.fetchedAt,
            failedBundleIds = state.failedBundleIds,
            lastReportAt = state.reportedAt,
        )
    }

    fun channel(): ChannelResult = when (val choice = state.channel) {
        is ChannelChoice.Id -> ChannelResult(choice.id, null, ChannelSource.RUNTIME)
        is ChannelChoice.Name -> ChannelResult(resolvedChannelName?.takeIf { it.first == choice.name }?.second ?: "", choice.name, ChannelSource.RUNTIME)
        null -> ChannelResult(configuration.channelId, null, ChannelSource.CONFIG)
    }

    suspend fun setChannel(choice: ChannelChoice?) = lock.withLock {
        state.channel = choice
        state.cachedIndex = null
    }

    fun deviceResult(): DeviceResult = DeviceResult(state.deviceId, device.platform, device.binaryVersion, device.binaryBuild, device.osVersion, device.sdkVersion, configuration.fingerprint, channel(), state.attributes)

    suspend fun setAttributes(changes: Map<String, String?>) = lock.withLock {
        val attributes = state.attributes.toMutableMap()
        for ((key, value) in changes) {
            if (value != null) {
                AttributeRules.validate(key, value)
                attributes[key] = value
            } else {
                attributes.remove(key)
            }
        }
        state.attributes = attributes
    }

    // The four functions and the gate

    /** A new binary carries a new floor: the releases downloaded under the previous one are forgotten and the embedded bundle runs. */
    private fun dropReleasesOfPreviousBinary() {
        state.currentRelease = null
        state.nextRelease = null
        state.fallbackRelease = null
        state.failedBundleIds = emptyList()
        state.lastBuiltAt = configuration.builtAt
        loader.persistServedBundle(null)
    }

    private fun setNextRelease(release: Release) {
        state.nextRelease = release
    }

    private fun switchToNextRelease() {
        val next = state.nextRelease ?: return
        state.currentRelease = next
        state.nextRelease = null
        loader.persistServedBundle(next.bundleId)
        enqueueDeviceEvent(DeviceEvent.applied(next.id))
    }

    private fun loadBundle() {
        val expected = state.currentRelease?.bundleId
        if (loader.servedBundleId() != expected) loader.loadServedBundle(expected)
    }

    private fun reloadApp() {
        loader.loadServedBundle(state.currentRelease?.bundleId)
        if (isCurrentReleaseUnconfirmed()) startReadyTimer()
    }

    /** The install the SDK performs on its own: the switch and the reload as one act behind the gate, so nothing changes until it runs. */
    private fun installNextRelease() = restartThroughGate {
        switchToNextRelease()
        reloadApp()
    }

    /** A restart the SDK performs on its own waits while the app holds restarts; the first one held runs when it lets go. */
    private fun restartThroughGate(restart: () -> Unit) {
        if (isRestartAllowed) restart() else if (queuedRestart == null) queuedRestart = restart
    }

    private fun adoptInPlace(release: Release) {
        val wasConfirmed = !isCurrentReleaseUnconfirmed()
        state.currentRelease = release
        if (wasConfirmed) state.fallbackRelease = release
        loader.persistServedBundle(release.bundleId)
    }

    private fun isCurrentReleaseUnconfirmed(): Boolean {
        val current = state.currentRelease ?: return false
        return current.bundleId != state.fallbackRelease?.bundleId
    }

    private fun confirmCurrentRelease() {
        stopReadyTimer()
        val current = state.currentRelease
        if (current != null && isCurrentReleaseUnconfirmed()) {
            state.fallbackRelease = current
            enqueueDeviceEvent(DeviceEvent.confirmed(current.id))
        }
        if (isStartSyncPending) {
            isStartSyncPending = false
            if (configuration.autoSync) scope.launch { sync(SyncTrigger.START) }
        }
    }

    private fun rollbackCurrentRelease(reason: RollbackReason) {
        val current = state.currentRelease ?: return
        stopReadyTimer()
        state.failedBundleIds = (state.failedBundleIds + current.bundleId).distinct().sorted()
        val fallback = resolveFallbackRelease()
        state.currentRelease = fallback
        state.nextRelease = null
        state.lastRollback = LastRollback(current, fallback, reason)
        enqueueDeviceEvent(DeviceEvent.failed(current.id, reason.name))
        enqueueDeviceEvent(DeviceEvent.rolledBack(current.id, fallback?.id))
        loader.persistServedBundle(fallback?.bundleId)
        listener.rolledBack(RolledBackEvent(current, fallback, reason))
        if (reason == RollbackReason.REPORTED_BY_APP) reloadApp() else restartThroughGate { reloadApp() }
    }

    /** The release to fall back to right now: the last confirmed one while it can still run, else the embedded bundle. */
    private fun resolveFallbackRelease(): Release? {
        val fallback = state.fallbackRelease ?: return null
        if (fallback.bundleId in state.failedBundleIds) return null
        if (state.cachedIndex?.body?.revokedReleaseIds?.contains(fallback.id) == true) return null
        val manifest = files.readManifest(fallback.bundleId) ?: return null
        return if (files.isComplete(manifest, embedded)) fallback else null
    }

    private fun revertToEmbedded() {
        stopReadyTimer()
        state.currentRelease = null
        state.nextRelease = null
        loader.persistServedBundle(null)
        restartThroughGate { reloadApp() }
    }

    private fun startReadyTimer() {
        stopReadyTimer()
        readyTimer = scheduler.schedule(configuration.readyTimeout) { scope.launch { handleReadyTimeout() } }
    }

    private fun stopReadyTimer() {
        readyTimer?.cancel()
        readyTimer = null
    }

    internal suspend fun handleReadyTimeout() = lock.withLock {
        if (isCurrentReleaseUnconfirmed()) rollbackCurrentRelease(RollbackReason.READY_TIMEOUT)
    }

    private fun scheduleIntervalSync(afterSeconds: Double) {
        intervalTimer?.cancel()
        if (!configuration.autoSync) return
        intervalTimer = scheduler.schedule(afterSeconds) { scope.launch { sync(SyncTrigger.INTERVAL) } }
    }

    /** Everything no kept release lists: the served tree of every other bundle first, since its links hold the bytes. */
    private fun deleteUnusedFiles() {
        val kept = listOfNotNull(state.currentRelease, state.nextRelease, state.fallbackRelease).map { it.bundleId }.toSet()
        files.bundleIds().filter { it !in kept }.forEach(loader::deleteProjection)
        files.deleteUnusedFiles(kept)
    }

    // The index

    private sealed class IndexFetch {
        data class Index(val index: ChannelIndex) : IndexFetch()
        object Offline : IndexFetch()
        data class Invalid(val message: String) : IndexFetch()
        object Absent : IndexFetch()
    }

    private suspend fun resolveChannelId(): String? = when (val choice = state.channel) {
        null -> configuration.channelId
        is ChannelChoice.Id -> choice.id
        is ChannelChoice.Name -> {
            val resolved = resolvedChannelName
            if (resolved != null && resolved.first == choice.name) {
                resolved.second
            } else {
                val url = "${configuration.filesBaseUrl}/apps/${configuration.appId}/channels/v1/index.json"
                val response = runCatching { httpClient.get(url, emptyMap()) }.getOrNull()
                val index = response?.takeIf { it.status == 200 }?.let { runCatching { ChannelsIndex.fromJson(org.json.JSONObject(String(it.body, Charsets.UTF_8))) }.getOrNull() }
                val entry = index?.channels?.firstOrNull { it.name == choice.name }
                entry?.also { resolvedChannelName = choice.name to it.id }?.id
            }
        }
    }

    private suspend fun fetchChannelIndex(channelId: String): IndexFetch {
        val url = "${configuration.filesBaseUrl}/apps/${configuration.appId}/channels/$channelId/${device.platform}/v1/index.json"
        val cached = state.cachedIndex?.takeIf { it.body.channelId == channelId }
        val headers = cached?.etag?.let { mapOf("If-None-Match" to it) } ?: emptyMap()
        val response = runCatching { httpClient.get(url, headers) }.getOrNull() ?: return cached?.let { IndexFetch.Index(it.body) } ?: IndexFetch.Offline
        return when (response.status) {
            304 -> {
                if (cached == null) return IndexFetch.Offline
                lock.withLock { state.cachedIndex = CachedIndex(cached.etag, clock.now(), cached.body) }
                IndexFetch.Index(cached.body)
            }
            200 -> {
                val index = runCatching { ChannelIndex.fromJson(org.json.JSONObject(String(response.body, Charsets.UTF_8))) }.getOrNull()
                    ?: return IndexFetch.Invalid("The channel index could not be parsed")
                if (index.schema != ChannelIndex.SCHEMA) return IndexFetch.Invalid("The channel index has schema ${index.schema}, this SDK reads ${ChannelIndex.SCHEMA}")
                if (cached != null && index.sequence < cached.body.sequence) return IndexFetch.Index(cached.body)
                lock.withLock { state.cachedIndex = CachedIndex(response.header("ETag"), clock.now(), index) }
                IndexFetch.Index(index)
            }
            404 -> {
                if (state.channel != null) {
                    lock.withLock { state.channel = null }
                    fetchChannelIndex(configuration.channelId)
                } else {
                    IndexFetch.Absent
                }
            }
            else -> cached?.let { IndexFetch.Index(it.body) } ?: IndexFetch.Offline
        }
    }

    private fun deviceInfo() = DeviceInfo(null, state.attributes, device.binaryBuild, device.binaryVersion, configuration.builtAt, state.currentRelease, state.deviceId, state.failedBundleIds, configuration.fingerprint, device.osVersion, state.reportedAt, null)

    // Events

    private fun recordChecked(release: IndexRelease, index: ChannelIndex, status: SyncStatus, skip: Skip?) {
        val checked = state.checkedReleaseIds.filter { id -> index.releases.any { it.id == id } }
        if (release.id in checked) {
            state.checkedReleaseIds = checked
            return
        }
        state.checkedReleaseIds = checked + release.id
        enqueueDeviceEvent(DeviceEvent.checked(release.id, status, skip?.reason, skip?.condition))
    }

    private fun enqueueDeviceEvent(event: DeviceEvent) {
        state.unsentEvents = (state.unsentEvents + event).takeLast(200)
    }
}
