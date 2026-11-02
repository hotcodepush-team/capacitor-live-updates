import type { PluginListenerHandle } from '@capacitor/core';
import type {
  DownloadProgressEvent,
  HotCodePushMethods,
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
 * The methods and their option, result and event types come from `@hotcodepush/protocol`.
 * Every `addListener` call resolves to a Capacitor listener handle.
 */
export interface HotCodePushPlugin extends HotCodePushMethods {
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
}
