import type { PluginListenerHandle } from '@capacitor/core';
import type {
  ApplyUpdateResult,
  CheckForUpdateResult,
  DownloadProgressEvent,
  DownloadUpdateOptions,
  DownloadUpdateResult,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  NotifyReadyResult,
  RollbackUpdateOptions,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SyncOptions,
  SyncResult,
  UpdateAvailableEvent,
  UpdateDownloadedEvent,
  UpdateFailedEvent,
  UpdateRolledBackEvent,
} from '@hotcodepush/protocol';

export type {
  ApplyMoment,
  ApplyStrategy,
  ApplyUpdateResult,
  CheckForUpdateResult,
  CheckStrategy,
  ConditionType,
  DownloadProgressEvent,
  DownloadStrategy,
  DownloadUpdateOptions,
  DownloadUpdateResult,
  FailedReason,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushEventName,
  HotCodePushEvents,
  MandatoryApplyStrategy,
  NotifyReadyResult,
  ReadySignal,
  Release,
  RollbackReason,
  RollbackUpdateOptions,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SkippedReason,
  SyncOptions,
  SyncResult,
  SyncTrigger,
  UpdateAvailableEvent,
  UpdateDownloadedEvent,
  UpdateFailedEvent,
  UpdateRolledBackEvent,
} from '@hotcodepush/protocol';

/**
 * The Capacitor plugin over the option, result and event types of `@hotcodepush/protocol`; every listener is
 * answered with Capacitor's handle.
 */
export interface HotCodePushPlugin {
  /**
   * One cycle under the strategies, the same the SDK runs on its own at start,
   * resume and interval, stopping at a `manual` gate for the app: fetch the
   * index, evaluate it locally, download and verify, apply, report. A second
   * call while one runs joins the running one.
   */
  sync(options?: SyncOptions): Promise<SyncResult>;
  /** `sync()` with `downloadStrategy` pinned to `manual`: fetch and evaluate, download nothing. */
  checkForUpdate(): Promise<CheckForUpdateResult>;
  /** `sync()` with `downloadStrategy` pinned to `auto`: re-check the index, a conditional GET, download and verify, apply per the apply strategies. */
  downloadUpdate(
    options?: DownloadUpdateOptions,
  ): Promise<DownloadUpdateResult>;
  /** Applies the downloaded update now, whatever the strategy says, and reloads the app. */
  applyUpdate(): Promise<ApplyUpdateResult>;
  /** Ends the readiness gate when `readySignal` is `manual`; safe to call at any time on any setting. */
  notifyReady(): Promise<NotifyReadyResult>;
  /** Rolls the running release back now, marks its bundle as failed on this device, reports `APP_REQUESTED`, reloads. */
  rollbackUpdate(options?: RollbackUpdateOptions): Promise<void>;
  /** Clears every downloaded update and the list of failed bundles, keeps the channel and the attributes, reloads. */
  clearUpdates(): Promise<void>;
  /** Restart gating: `isAllowed: false` holds the one restart the SDK would perform on its own — after an `immediate` apply, a `next-resume` apply or a mandatory release alike — until `isAllowed: true` runs it. A restart the app asks for itself, `applyUpdate()`, `rollbackUpdate()` or `clearUpdates()`, is never held. Not persisted: every start begins allowed. */
  setRestartAllowed(options: SetRestartAllowedOptions): Promise<void>;
  /** The SDK's state, a snapshot. */
  getState(): Promise<GetStateResult>;
  /** The channel in effect with its source. */
  getChannel(): Promise<GetChannelResult>;
  /** Switches the device to a channel by name or by id; `null` clears the runtime choice. */
  setChannel(options: SetChannelOptions): Promise<void>;
  /** The facts of the device report. */
  getDevice(): Promise<GetDeviceResult>;
  /** Merges string attributes the app sets for `attribute` conditions; a `null` value removes a key. */
  setAttributes(options: SetAttributesOptions): Promise<void>;
  /** Opens the SDK's native debug screen. */
  showDebugScreen(): Promise<void>;
  addListener(
    eventName: 'downloadProgress',
    listener: (event: DownloadProgressEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'updateAvailable',
    listener: (event: UpdateAvailableEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'updateDownloaded',
    listener: (event: UpdateDownloadedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'updateFailed',
    listener: (event: UpdateFailedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'updateRolledBack',
    listener: (event: UpdateRolledBackEvent) => void,
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}
