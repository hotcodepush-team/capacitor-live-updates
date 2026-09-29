import type { PluginListenerHandle } from '@capacitor/core';
import type {
  CheckResult,
  GetChannelResult,
  GetDeviceResult,
  GetStatusResult,
  ReadyResult,
  Release,
  RollbackOptions,
  RollbackReason,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SyncOptions,
  SyncResult,
  SyncTrigger,
} from '@hotcodepush/protocol';

export type {
  CheckResult,
  ConditionType,
  FailedReason,
  GetChannelResult,
  GetDeviceResult,
  GetStatusResult,
  InstallStrategy,
  NetworkPolicy,
  ReadyResult,
  Release,
  RollbackOptions,
  RollbackReason,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SkippedReason,
  SyncOptions,
  SyncResult,
  SyncTrigger,
} from '@hotcodepush/protocol';

export interface SyncStartedEvent {
  trigger: SyncTrigger;
}

export interface SyncedEvent {
  result: SyncResult;
  trigger: SyncTrigger;
}

export interface DownloadProgressEvent {
  releaseId: string;
  downloadedBytes: number;
  totalBytes: number;
  progress: number;
}

export interface RolledBackEvent {
  from: Release;
  to: Release | null;
  reason: RollbackReason;
}

export interface HotCodePushPlugin {
  /**
   * One full cycle: fetch the index, evaluate it locally, download and verify the update
   * the device is eligible for, apply it per the install strategy, report.
   */
  sync(options?: SyncOptions): Promise<SyncResult>;
  /**
   * The first half of `sync()`: fetch and evaluate, download nothing.
   */
  check(): Promise<CheckResult>;
  /**
   * Applies the downloaded update now and reloads the app. Does nothing when nothing is downloaded.
   */
  apply(): Promise<void>;
  /**
   * Ends the readiness gate when `readySignal` is `call`; safe to call at any time on any setting.
   */
  ready(): Promise<ReadyResult>;
  /**
   * Rolls the running release back now: reverts to the confirmed bundle or the embedded one,
   * marks the bundle as failed on this device, reports `REPORTED_BY_APP`, reloads.
   */
  rollback(options?: RollbackOptions): Promise<void>;
  /**
   * Back to the embedded bundle: clears every downloaded release and the list of failed bundles,
   * keeps the channel and the attributes, reloads.
   */
  reset(): Promise<void>;
  /**
   * Restart gating: `allowed: false` queues every restart the SDK would perform until `allowed: true`.
   */
  setRestartAllowed(options: SetRestartAllowedOptions): Promise<void>;
  /**
   * The release state and everything the debug screen shows.
   */
  getStatus(): Promise<GetStatusResult>;
  /**
   * The channel in effect with its source.
   */
  getChannel(): Promise<GetChannelResult>;
  /**
   * Switches the device to a channel by name or by id; `null` clears the runtime choice.
   */
  setChannel(options: SetChannelOptions): Promise<void>;
  /**
   * The facts of the device report.
   */
  getDevice(): Promise<GetDeviceResult>;
  /**
   * Merges string attributes the app sets for `attribute` conditions; a `null` value removes a key.
   */
  setAttributes(options: SetAttributesOptions): Promise<void>;
  addListener(
    eventName: 'syncStarted',
    listener: (event: SyncStartedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'synced',
    listener: (event: SyncedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'downloadProgress',
    listener: (event: DownloadProgressEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'rolledBack',
    listener: (event: RolledBackEvent) => void,
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}
