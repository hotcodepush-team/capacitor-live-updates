import type { PluginListenerHandle } from '@capacitor/core';
import type {
  HotCodePushApi,
  HotCodePushEventName,
  HotCodePushEvents,
} from '@hotcodepush/protocol';

export type {
  ApplyResult,
  CheckResult,
  ConditionType,
  DownloadProgressEvent,
  DownloadResult,
  DownloadStrategy,
  FailedReason,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushApi,
  HotCodePushEventName,
  HotCodePushEvents,
  InstallMoment,
  InstallStrategy,
  MandatoryInstallStrategy,
  NotifyReadyResult,
  ReadySignal,
  Release,
  RollbackReason,
  RollbackUpdateOptions,
  RolledBackEvent,
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
