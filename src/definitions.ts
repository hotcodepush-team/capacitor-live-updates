import type { PluginListenerHandle } from '@capacitor/core';

// TODO(protocol-js#2): these types are the shared definitions of sdk-api.md and move to
// `@hotcodepush/protocol` the moment its pkg.pr.new build exists.

export interface Release {
  id: string;
  number: number;
  bundleId: string;
  bundleVersion: string;
  isMandatory: boolean;
}

export type InstallStrategy =
  'next-start' | 'immediate' | 'on-resume' | 'manual';

export type SyncTrigger = 'start' | 'resume' | 'interval' | 'call';

export type ConditionType =
  'binary' | 'runtime' | 'fingerprint' | 'os' | 'attribute' | 'device';

export type SkippedReason =
  | 'INCOMPATIBLE'
  | 'NOT_TARGETED'
  | 'NOT_IN_ROLLOUT'
  | 'UNSUPPORTED_CONDITION'
  | 'OLDER_THAN_BINARY'
  | 'CHANNEL_PAUSED'
  | 'SPENDING_CAP_REACHED'
  | 'RELEASE_REVOKED'
  | 'FAILED_BEFORE'
  | 'DEBUG_BUILD'
  | 'METERED_CONNECTION';

export type FailedReason =
  | 'OFFLINE'
  | 'UNKNOWN_CHANNEL'
  | 'INVALID_INDEX'
  | 'INVALID_SIGNATURE'
  | 'DOWNLOAD_FAILED'
  | 'VERIFICATION_FAILED';

export type RollbackReason = 'READY_TIMEOUT' | 'CRASHED' | 'REPORTED_BY_APP';

export type SyncResult =
  | { status: 'UP_TO_DATE'; release: Release | null }
  | {
      status: 'UPDATED';
      release: Release;
      notes: string | null;
      installAt: 'now' | 'next-start' | 'on-resume' | 'manual';
    }
  | {
      status: 'SKIPPED';
      release: Release | null;
      reason: SkippedReason;
      condition?: ConditionType;
    }
  | {
      status: 'FAILED';
      release: Release | null;
      reason: FailedReason;
      message: string;
    };

export type CheckResult =
  | { status: 'UP_TO_DATE'; release: Release | null }
  | {
      status: 'AVAILABLE';
      release: Release;
      notes: string | null;
      downloadBytes: number | null;
    }
  | {
      status: 'SKIPPED';
      release: Release | null;
      reason: SkippedReason;
      condition?: ConditionType;
    }
  | {
      status: 'FAILED';
      release: Release | null;
      reason: FailedReason;
      message: string;
    };

export interface ReadyResult {
  currentRelease: Release | null;
  previousRelease: Release | null;
  isRolledBack: boolean;
  rollbackReason?: RollbackReason;
}

export interface GetStatusResult {
  currentRelease: Release | null;
  nextRelease: Release | null;
  fallbackRelease: Release | null;
  embeddedBundleId: string | null;
  lastCheck: {
    at: string;
    trigger: SyncTrigger;
    result: SyncResult | CheckResult;
  } | null;
  index: { sequence: number; fetchedAt: string } | null;
  failedBundleIds: string[];
  lastReportAt: string | null;
}

export interface GetChannelResult {
  id: string;
  name: string | null;
  source: 'runtime' | 'config';
}

export type SetChannelOptions = { name: string } | { id: string } | null;

export interface GetDeviceResult {
  id: string;
  platform: 'ios' | 'android' | 'web';
  binaryVersion: string;
  binaryBuild: string;
  osVersion: string;
  sdkVersion: string;
  fingerprint: string | null;
  channel: GetChannelResult;
  attributes: Record<string, string>;
}

export type SetAttributesOptions = Record<string, string | null>;

export interface RollbackOptions {
  reason?: string;
}

export type NetworkPolicy = 'any' | 'unmetered';

export interface SyncOptions {
  installStrategy?: InstallStrategy;
  network?: NetworkPolicy;
}

export interface SetRestartAllowedOptions {
  allowed: boolean;
}

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
