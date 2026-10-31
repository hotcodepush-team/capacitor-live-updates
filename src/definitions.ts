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
 * The Capacitor plugin for HotCodePush live updates.
 *
 * The option, result and event types come from `@hotcodepush/protocol`.
 * Every `addListener` call resolves to a Capacitor listener handle.
 */
export interface HotCodePushPlugin {
  /**
   * Runs one update cycle under the configured strategies.
   *
   * The cycle fetches the index, evaluates it locally, downloads and verifies,
   * applies and reports. It stops at any step whose strategy is `manual` and
   * leaves that step to the app.
   * The SDK runs the same cycle on its own at start, at resume and on the interval.
   * A call made while a cycle runs joins that cycle.
   */
  sync(options?: SyncOptions): Promise<SyncResult>;
  /**
   * Checks for an update without downloading it.
   *
   * Same as `sync()` with `downloadStrategy` set to `manual`.
   */
  checkForUpdate(): Promise<CheckForUpdateResult>;
  /**
   * Downloads and verifies the available update.
   *
   * Same as `sync()` with `downloadStrategy` set to `auto`.
   * It re-checks the index with a conditional GET and applies the update as the apply strategies say.
   */
  downloadUpdate(
    options?: DownloadUpdateOptions,
  ): Promise<DownloadUpdateResult>;
  /**
   * Applies the downloaded update now and reloads the app.
   *
   * The apply strategy does not matter here.
   */
  applyUpdate(): Promise<ApplyUpdateResult>;
  /**
   * Ends the readiness gate when `readySignal` is `manual`.
   *
   * Safe to call at any time and with any `readySignal`.
   */
  notifyReady(): Promise<NotifyReadyResult>;
  /**
   * Rolls back the running release now and reloads the app.
   *
   * The bundle is marked as failed on this device and the rollback is reported with the reason `app_requested`.
   */
  rollbackUpdate(options?: RollbackUpdateOptions): Promise<void>;
  /**
   * Clears all downloaded updates and the list of failed bundles, then reloads the app.
   *
   * The channel and the attributes stay.
   */
  clearUpdates(): Promise<void>;
  /**
   * Allows or holds the restarts the SDK performs on its own.
   *
   * With `isAllowed: false`, the SDK holds its restart after an `immediate` apply, a `next_resume` apply or a mandatory release.
   * The held restart runs when `isAllowed: true` is set.
   * Restarts the app asks for with `applyUpdate()`, `rollbackUpdate()` or `clearUpdates()` are never held.
   * The setting is not persisted: every app start begins with restarts allowed.
   */
  setRestartAllowed(options: SetRestartAllowedOptions): Promise<void>;
  /** Returns a snapshot of the SDK state. */
  getState(): Promise<GetStateResult>;
  /** Returns the channel in effect and where it comes from. */
  getChannel(): Promise<GetChannelResult>;
  /**
   * Switches the device to a channel by name or by ID.
   *
   * `null` clears the channel set at runtime.
   */
  setChannel(options: SetChannelOptions): Promise<void>;
  /** Returns the device facts the SDK reports. */
  getDevice(): Promise<GetDeviceResult>;
  /**
   * Merges string attributes into the ones used by `attribute` conditions.
   *
   * A `null` value removes the key.
   */
  setAttributes(options: SetAttributesOptions): Promise<void>;
  /** Opens the native debug screen of the SDK. */
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
