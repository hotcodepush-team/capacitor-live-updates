import { WebPlugin } from '@capacitor/core';

import type {
  ApplyResult,
  CheckResult,
  DownloadResult,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushPlugin,
  NotifyReadyResult,
  SyncResult,
} from './definitions';

/**
 * The web platform is a no-op: every method resolves with the embedded state.
 */
export class HotCodePushWeb extends WebPlugin implements HotCodePushPlugin {
  private static readonly embeddedChannel: GetChannelResult = {
    id: '',
    name: null,
    source: 'config',
  };

  async applyUpdate(): Promise<ApplyResult> {
    return { status: 'NOTHING_TO_APPLY', release: null };
  }

  async checkForUpdate(): Promise<CheckResult> {
    return { status: 'UP_TO_DATE', release: null };
  }

  async clearUpdates(): Promise<void> {}

  async downloadUpdate(): Promise<DownloadResult> {
    return { status: 'UP_TO_DATE', release: null };
  }

  async getChannel(): Promise<GetChannelResult> {
    return HotCodePushWeb.embeddedChannel;
  }

  async getDevice(): Promise<GetDeviceResult> {
    return {
      attributes: {},
      binaryBuild: '',
      binaryVersion: '',
      channel: HotCodePushWeb.embeddedChannel,
      fingerprint: null,
      id: '',
      osVersion: '',
      platform: 'web',
      sdkVersion: '',
    };
  }

  async getState(): Promise<GetStateResult> {
    return {
      currentRelease: null,
      embeddedBundleId: null,
      failedBundleIds: [],
      fallbackRelease: null,
      index: null,
      lastCheck: null,
      lastReportAt: null,
      nextRelease: null,
    };
  }

  async notifyReady(): Promise<NotifyReadyResult> {
    return { currentRelease: null, isRolledBack: false, previousRelease: null };
  }

  async notifyRendered(): Promise<void> {}

  async rollbackUpdate(): Promise<void> {}

  async setAttributes(): Promise<void> {}

  async setChannel(): Promise<void> {}

  async setRestartAllowed(): Promise<void> {}

  async showDebugScreen(): Promise<void> {}

  async sync(): Promise<SyncResult> {
    return { status: 'UP_TO_DATE', release: null };
  }
}
