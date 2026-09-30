import Foundation

/// The state machine every framework shares: three named releases, a readiness gate and one sync cycle.
public actor Core {
    public let configuration: Configuration
    private let device: DeviceFacts
    private let state: StateStore
    private let files: FileStore
    private let embedded: EmbeddedBundle
    private let downloader: Downloader
    private let http: HttpClient
    private let loader: BundleLoader
    private let listener: CoreListener
    private let scheduler: Scheduler
    private let clock: Clock

    private var readyTimer: ScheduledTask?
    private var intervalTimer: ScheduledTask?
    private var runningSync: Task<SyncResult, Never>?
    private var isRestartAllowed = true
    private var queuedRestart: (() -> Void)?
    private var isStartSyncPending = false
    private var resolvedChannelName: (name: String, id: String)?

    public init(configuration: Configuration, device: DeviceFacts, store: KeyValueStore, files: FileStore, embedded: EmbeddedBundle, http: HttpClient, loader: BundleLoader, listener: CoreListener, scheduler: Scheduler = DispatchScheduler(), clock: Clock = SystemClock(), temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.configuration = configuration
        self.device = device
        self.state = StateStore(store: store)
        self.files = files
        self.embedded = embedded
        self.downloader = Downloader(configuration: configuration, files: files, embedded: embedded, http: http, temporaryDirectory: temporaryDirectory)
        self.http = http
        self.loader = loader
        self.listener = listener
        self.scheduler = scheduler
        self.clock = clock
    }

    // MARK: Lifecycle

    /// The start of a run: the binary's floor, the previous run's verdict, the pending switch, the gate, then the cleanup.
    public func handleAppStart() {
        state.lastRollback = nil
        if state.lastBuiltAt != configuration.builtAt {
            dropReleasesOfPreviousBinary()
        }
        if isCurrentReleaseUnconfirmed() {
            rollbackCurrentRelease(reason: .crashed)
            return
        }
        if let next = state.nextRelease, configuration.installStrategy == .nextStart || next.isMandatory || loader.servedBundleId() == next.bundleId {
            switchToNextRelease()
        }
        loadBundle()
        if isCurrentReleaseUnconfirmed() {
            startReadyTimer()
            isStartSyncPending = true
        } else if configuration.autoSync {
            Task { await self.sync(trigger: .start) }
        }
        deleteUnusedFiles()
    }

    /// The first render, the readiness signal when `readySignal` is `render`.
    public func handleRendered() {
        guard configuration.readySignal == .render else { return }
        confirmCurrentRelease()
    }

    public func ready() -> ReadyResult {
        confirmCurrentRelease()
        let rollback = state.lastRollback
        state.lastRollback = nil
        return ReadyResult(currentRelease: state.currentRelease, previousRelease: rollback?.from, isRolledBack: rollback != nil, rollbackReason: rollback?.reason)
    }

    public func handleAppResume() {
        guard configuration.autoSync else { return }
        let lastSyncAt = state.lastSyncAt ?? .distantPast
        if clock.now.timeIntervalSince(lastSyncAt) >= configuration.syncInterval {
            Task { await self.sync(trigger: .resume) }
        }
    }

    // MARK: Sync

    public func sync(trigger: SyncTrigger, installStrategy: InstallStrategy? = nil, network: NetworkPolicy? = nil) async -> SyncResult {
        if let running = runningSync {
            return await running.value
        }
        let task = Task { await self.performSync(trigger: trigger, installStrategy: installStrategy, network: network, isCheckOnly: false) }
        runningSync = task
        let result = await task.value
        runningSync = nil
        return result
    }

    public func check() async -> SyncResult {
        if let running = runningSync {
            _ = await running.value
        }
        return await performSync(trigger: .call, installStrategy: nil, network: nil, isCheckOnly: true)
    }

    private func performSync(trigger: SyncTrigger, installStrategy: InstallStrategy?, network: NetworkPolicy?, isCheckOnly: Bool) async -> SyncResult {
        if !isCheckOnly {
            listener.syncStarted(trigger: trigger)
        }
        let result = await resolveSync(installStrategy: installStrategy, network: network, isCheckOnly: isCheckOnly)
        state.lastCheck = LastCheck(at: clock.now, trigger: trigger, result: result)
        if !isCheckOnly {
            state.lastSyncAt = clock.now
            listener.synced(result: result, trigger: trigger)
            scheduleIntervalSync()
        }
        return result
    }

    private func resolveSync(installStrategy: InstallStrategy?, network: NetworkPolicy?, isCheckOnly: Bool) async -> SyncResult {
        let current = state.currentRelease
        if device.isDebugBuild && !configuration.enabledInDebugBuilds {
            return .skipped(current, reason: .debugBuild)
        }
        guard let channelId = await resolveChannelId() else {
            return .failed(current, reason: .unknownChannel, message: "The channel set at runtime is not in the app's channels index")
        }
        let index: ChannelIndex
        switch await fetchChannelIndex(channelId: channelId) {
        case .index(let fetched): index = fetched
        case .offline: return .failed(current, reason: .offline, message: "The channel index could not be fetched and no cached copy exists")
        case .invalid(let message): return .failed(current, reason: .invalidIndex, message: message)
        case .absent: return .upToDate(current)
        }
        switch Evaluator.evaluate(index, device: deviceInfo()) {
        case .upToDate:
            return .upToDate(current)
        case .available(let target, let isMandatory):
            recordChecked(target, in: index, status: .available, skip: nil)
            if isCheckOnly {
                return .available(target.release, notes: target.notes, downloadBytes: target.sizeBytes)
            }
            return await install(target, isMandatory: isMandatory, installStrategy: installStrategy, network: network)
        case .skipped(let release, .releaseRevoked, _):
            if isCheckOnly {
                return .skipped(release?.release, reason: .releaseRevoked)
            }
            guard let target = release else {
                revertToEmbedded()
                return .skipped(nil, reason: .releaseRevoked)
            }
            let outcome = await install(target, isMandatory: true, installStrategy: nil, network: network)
            return outcome.status == .failed ? outcome : .skipped(target.release, reason: .releaseRevoked)
        case .skipped(let release, let reason, let condition):
            if let release = release {
                recordChecked(release, in: index, status: .skipped, skip: Skip(reason: reason, condition: condition))
            }
            return .skipped(release?.release, reason: reason, condition: condition)
        }
    }

    private func install(_ target: IndexRelease, isMandatory: Bool, installStrategy: InstallStrategy?, network: NetworkPolicy?) async -> SyncResult {
        let release = target.release
        if let current = state.currentRelease, current.bundleId == target.bundleId {
            adoptInPlace(release)
            return .updated(release, notes: target.notes, installAt: .now)
        }
        let strategy = isMandatory ? .immediate : (installStrategy ?? configuration.installStrategy)
        if let next = state.nextRelease, next.bundleId == target.bundleId, let manifest = files.readManifest(bundleId: next.bundleId), files.isComplete(manifest, embedded: embedded) {
            return applyDownloaded(release, notes: target.notes, strategy: strategy)
        }
        if (network ?? configuration.network) == .unmetered && loader.isConnectionMetered() {
            return .skipped(release, reason: .meteredConnection)
        }
        do {
            let outcome = try await downloader.downloadRelease(target, currentBundleId: state.currentRelease?.bundleId) { [listener] downloaded, total in
                listener.downloadProgress(releaseId: target.id, downloadedBytes: downloaded, totalBytes: total)
            }
            try BundleProjection.project(outcome.manifest, from: files, embedded: embedded, into: loader.projectionDirectory(bundleId: target.bundleId))
            enqueueDeviceEvent(.downloaded(releaseId: target.id, bundleId: target.bundleId, bytes: outcome.bytes, packKind: outcome.packKind))
        } catch let failure as DownloadFailure {
            enqueueDeviceEvent(.failed(releaseId: target.id, reason: failure.reason.rawValue))
            return .failed(release, reason: failure.reason, message: failure.message)
        } catch {
            enqueueDeviceEvent(.failed(releaseId: target.id, reason: FailedReason.downloadFailed.rawValue))
            return .failed(release, reason: .downloadFailed, message: error.localizedDescription)
        }
        return applyDownloaded(release, notes: target.notes, strategy: strategy)
    }

    /// Choosing and applying are two acts: the strategy is a policy over the four functions.
    private func applyDownloaded(_ release: Release, notes: String?, strategy: InstallStrategy) -> SyncResult {
        setNextRelease(release)
        switch strategy {
        case .immediate:
            installNextRelease()
            return .updated(release, notes: notes, installAt: .now)
        case .nextStart:
            loader.persistServedBundle(bundleId: release.bundleId)
            return .updated(release, notes: notes, installAt: .nextStart)
        case .onResume:
            return .updated(release, notes: notes, installAt: .onResume)
        case .manual:
            return .updated(release, notes: notes, installAt: .manual)
        }
    }

    public func apply() {
        guard state.nextRelease != nil else { return }
        switchToNextRelease()
        reloadApp()
    }

    public func rollback(reason: String?) {
        guard state.currentRelease != nil else { return }
        rollbackCurrentRelease(reason: .reportedByApp)
    }

    public func reset() {
        stopReadyTimer()
        state.currentRelease = nil
        state.nextRelease = nil
        state.fallbackRelease = nil
        state.failedBundleIds = []
        state.lastRollback = nil
        for bundleId in files.bundleIds() {
            loader.deleteProjection(bundleId: bundleId)
        }
        files.deleteEverything()
        loader.persistServedBundle(bundleId: nil)
        reloadApp()
    }

    public func setRestartAllowed(_ allowed: Bool) {
        isRestartAllowed = allowed
        guard allowed, let restart = queuedRestart else { return }
        queuedRestart = nil
        restart()
    }

    // MARK: State

    public func status() -> StatusResult {
        return StatusResult(
            currentRelease: state.currentRelease,
            nextRelease: state.nextRelease,
            fallbackRelease: state.fallbackRelease,
            embeddedBundleId: configuration.embeddedBundleId,
            lastCheck: state.lastCheck,
            index: state.cachedIndex.map { IndexState(sequence: $0.body.sequence, fetchedAt: $0.fetchedAt) },
            failedBundleIds: state.failedBundleIds,
            lastReportAt: state.reportedAt)
    }

    public func channel() -> ChannelResult {
        switch state.channel {
        case .id(let id): return ChannelResult(id: id, name: nil, source: .runtime)
        case .name(let name): return ChannelResult(id: resolvedChannelName?.name == name ? resolvedChannelName?.id ?? "" : "", name: name, source: .runtime)
        case nil: return ChannelResult(id: configuration.channelId, name: nil, source: .config)
        }
    }

    public func setChannel(_ choice: ChannelChoice?) {
        state.channel = choice
        state.cachedIndex = nil
    }

    public func deviceResult() -> DeviceResult {
        return DeviceResult(id: state.deviceId, platform: device.platform, binaryVersion: device.binaryVersion, binaryBuild: device.binaryBuild, osVersion: device.osVersion, sdkVersion: device.sdkVersion, fingerprint: configuration.fingerprint, channel: channel(), attributes: state.attributes)
    }

    public func setAttributes(_ changes: [String: String?]) throws {
        var attributes = state.attributes
        for (key, value) in changes {
            if let value = value {
                try AttributeRules.validate(key: key, value: value)
                attributes[key] = value
            } else {
                attributes.removeValue(forKey: key)
            }
        }
        state.attributes = attributes
    }

    // MARK: The four functions and the gate

    /// A new binary carries a new floor: the releases downloaded under the previous one are forgotten and the embedded bundle runs.
    private func dropReleasesOfPreviousBinary() {
        state.currentRelease = nil
        state.nextRelease = nil
        state.fallbackRelease = nil
        state.failedBundleIds = []
        state.lastBuiltAt = configuration.builtAt
        loader.persistServedBundle(bundleId: nil)
    }

    private func setNextRelease(_ release: Release) {
        state.nextRelease = release
    }

    private func switchToNextRelease() {
        guard let next = state.nextRelease else { return }
        state.currentRelease = next
        state.nextRelease = nil
        loader.persistServedBundle(bundleId: next.bundleId)
        enqueueDeviceEvent(.applied(releaseId: next.id))
    }

    private func loadBundle() {
        let expected = state.currentRelease?.bundleId
        if loader.servedBundleId() != expected {
            loader.loadServedBundle(bundleId: expected)
        }
    }

    private func reloadApp() {
        loader.loadServedBundle(bundleId: state.currentRelease?.bundleId)
        if isCurrentReleaseUnconfirmed() {
            startReadyTimer()
        }
    }

    /// The install the SDK performs on its own: the switch and the reload as one act behind the gate, so nothing changes until it runs.
    private func installNextRelease() {
        restartThroughGate { [self] in
            switchToNextRelease()
            reloadApp()
        }
    }

    /// A restart the SDK performs on its own waits while the app holds restarts; the first one held runs when it lets go.
    private func restartThroughGate(_ restart: @escaping () -> Void) {
        if isRestartAllowed {
            restart()
        } else if queuedRestart == nil {
            queuedRestart = restart
        }
    }

    private func adoptInPlace(_ release: Release) {
        let wasConfirmed = !isCurrentReleaseUnconfirmed()
        state.currentRelease = release
        if wasConfirmed {
            state.fallbackRelease = release
        }
        loader.persistServedBundle(bundleId: release.bundleId)
    }

    private func isCurrentReleaseUnconfirmed() -> Bool {
        guard let current = state.currentRelease else { return false }
        return current.bundleId != state.fallbackRelease?.bundleId
    }

    private func confirmCurrentRelease() {
        stopReadyTimer()
        if let current = state.currentRelease, isCurrentReleaseUnconfirmed() {
            state.fallbackRelease = current
            enqueueDeviceEvent(.confirmed(releaseId: current.id))
        }
        if isStartSyncPending {
            isStartSyncPending = false
            if configuration.autoSync {
                Task { await self.sync(trigger: .start) }
            }
        }
    }

    private func rollbackCurrentRelease(reason: RollbackReason) {
        guard let current = state.currentRelease else { return }
        stopReadyTimer()
        state.failedBundleIds = Array(Set(state.failedBundleIds + [current.bundleId])).sorted()
        let fallback = resolveFallbackRelease()
        state.currentRelease = fallback
        state.nextRelease = nil
        state.lastRollback = LastRollback(from: current, to: fallback, reason: reason)
        enqueueDeviceEvent(.failed(releaseId: current.id, reason: reason.rawValue))
        enqueueDeviceEvent(.rolledBack(fromReleaseId: current.id, toReleaseId: fallback?.id))
        loader.persistServedBundle(bundleId: fallback?.bundleId)
        listener.rolledBack(RolledBackEvent(from: current, to: fallback, reason: reason))
        if reason == .reportedByApp {
            reloadApp()
        } else {
            restartThroughGate { [self] in reloadApp() }
        }
    }

    /// The release to fall back to right now: the last confirmed one while it can still run, else the embedded bundle.
    private func resolveFallbackRelease() -> Release? {
        guard let fallback = state.fallbackRelease,
              !state.failedBundleIds.contains(fallback.bundleId),
              !(state.cachedIndex?.body.revokedReleaseIds.contains(fallback.id) ?? false),
              let manifest = files.readManifest(bundleId: fallback.bundleId),
              files.isComplete(manifest, embedded: embedded) else {
            return nil
        }
        return fallback
    }

    private func revertToEmbedded() {
        stopReadyTimer()
        state.currentRelease = nil
        state.nextRelease = nil
        loader.persistServedBundle(bundleId: nil)
        restartThroughGate { [self] in reloadApp() }
    }

    private func startReadyTimer() {
        stopReadyTimer()
        readyTimer = scheduler.schedule(after: configuration.readyTimeout) { [weak self] in
            guard let self = self else { return }
            Task { await self.handleReadyTimeout() }
        }
    }

    private func stopReadyTimer() {
        readyTimer?.cancel()
        readyTimer = nil
    }

    func handleReadyTimeout() {
        guard isCurrentReleaseUnconfirmed() else { return }
        rollbackCurrentRelease(reason: .readyTimeout)
    }

    private func scheduleIntervalSync() {
        intervalTimer?.cancel()
        guard configuration.autoSync else { return }
        intervalTimer = scheduler.schedule(after: configuration.syncInterval) { [weak self] in
            guard let self = self else { return }
            Task { await self.sync(trigger: .interval) }
        }
    }

    /// Everything no kept release lists: the served tree of every other bundle first, since its links hold the bytes.
    private func deleteUnusedFiles() {
        let kept = Set([state.currentRelease, state.nextRelease, state.fallbackRelease].compactMap { $0?.bundleId })
        for bundleId in files.bundleIds() where !kept.contains(bundleId) {
            loader.deleteProjection(bundleId: bundleId)
        }
        files.deleteUnusedFiles(keepingBundleIds: kept)
    }

    // MARK: The index

    enum IndexFetch {
        case index(ChannelIndex)
        case offline
        case invalid(String)
        case absent
    }

    private func resolveChannelId() async -> String? {
        switch state.channel {
        case nil: return configuration.channelId
        case .id(let id): return id
        case .name(let name):
            if let resolved = resolvedChannelName, resolved.name == name { return resolved.id }
            guard let url = URL(string: "\(configuration.filesBaseUrl)/apps/\(configuration.appId)/channels/v1/index.json"),
                  let response = try? await http.get(url, headers: [:]), response.status == 200,
                  let index = try? Json.decoder.decode(ChannelsIndex.self, from: response.body),
                  let entry = index.channels.first(where: { $0.name == name }) else { return nil }
            resolvedChannelName = (name, entry.id)
            return entry.id
        }
    }

    private func fetchChannelIndex(channelId: String) async -> IndexFetch {
        guard let url = URL(string: "\(configuration.filesBaseUrl)/apps/\(configuration.appId)/channels/\(channelId)/\(device.platform)/v1/index.json") else {
            return .invalid("Invalid index URL")
        }
        let cached = state.cachedIndex.flatMap { $0.body.channelId == channelId ? $0 : nil }
        var headers: [String: String] = [:]
        if let etag = cached?.etag {
            headers["If-None-Match"] = etag
        }
        guard let response = try? await http.get(url, headers: headers) else {
            return cached.map { .index($0.body) } ?? .offline
        }
        switch response.status {
        case 304:
            guard let cached = cached else { return .offline }
            state.cachedIndex = CachedIndex(etag: cached.etag, fetchedAt: clock.now, body: cached.body)
            return .index(cached.body)
        case 200:
            guard let index = try? Json.decoder.decode(ChannelIndex.self, from: response.body) else {
                return .invalid("The channel index could not be parsed")
            }
            guard index.schema == ChannelIndex.schema else {
                return .invalid("The channel index has schema \(index.schema), this SDK reads \(ChannelIndex.schema)")
            }
            if let cached = cached, index.sequence < cached.body.sequence {
                return .index(cached.body)
            }
            state.cachedIndex = CachedIndex(etag: response.header("ETag"), fetchedAt: clock.now, body: index)
            return .index(index)
        case 404:
            if case .some = state.channel {
                state.channel = nil
                return await fetchChannelIndex(channelId: configuration.channelId)
            }
            return .absent
        default:
            return cached.map { .index($0.body) } ?? .offline
        }
    }

    private func deviceInfo() -> DeviceInfo {
        return DeviceInfo(appliedIndexSequence: nil, attributes: state.attributes, binaryBuild: device.binaryBuild, binaryVersion: device.binaryVersion, builtAt: configuration.builtAt, currentRelease: state.currentRelease, deviceId: state.deviceId, failedBundleIds: state.failedBundleIds, fingerprint: configuration.fingerprint, osVersion: device.osVersion, reportedAt: state.reportedAt, runtimeVersion: nil)
    }

    // MARK: Events

    private func recordChecked(_ release: IndexRelease, in index: ChannelIndex, status: SyncStatus, skip: Skip?) {
        var checked = state.checkedReleaseIds.filter { id in index.releases.contains { $0.id == id } }
        guard !checked.contains(release.id) else {
            state.checkedReleaseIds = checked
            return
        }
        checked.append(release.id)
        state.checkedReleaseIds = checked
        enqueueDeviceEvent(.checked(releaseId: release.id, status: status, reason: skip?.reason, condition: skip?.condition))
    }

    private func enqueueDeviceEvent(_ event: DeviceEvent) {
        state.unsentEvents = Array((state.unsentEvents + [event]).suffix(200))
    }
}
