import type { PluginListenerHandle } from '@capacitor/core';
import type {
  HotCodePushApi,
  HotCodePushEventName,
  HotCodePushEvents,
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
  HotCodePushApi,
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
 * The Capacitor plugin: the one SDK surface `@hotcodepush/protocol` defines, with
 * Capacitor's listener handle in place of the shared one — the same shape.
 */
export interface HotCodePushPlugin extends HotCodePushApi {
  addListener<EventName extends HotCodePushEventName>(
    eventName: EventName,
    listener: (event: HotCodePushEvents[EventName]) => void,
  ): Promise<PluginListenerHandle>;
}
