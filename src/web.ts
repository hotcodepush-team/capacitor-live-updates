import { WebPlugin } from '@capacitor/core';

import type {
  CheckResult,
  GetChannelResult,
  GetDeviceResult,
  GetStatusResult,
  HotCodePushPlugin,
  ReadyResult,
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

  async apply(): Promise<void> {}

  async check(): Promise<CheckResult> {
    return { status: 'UP_TO_DATE', release: null };
  }

  async getChannel(): Promise<GetChannelResult> {
    return HotCodePushWeb.embeddedChannel;
  }

  async getDevice(): Promise<GetDeviceResult> {
    // The shared `Platform` names the two native platforms; the web no-op reports the platform it is.
    return {
      attributes: {},
      binaryBuild: '',
      binaryVersion: '',
      channel: HotCodePushWeb.embeddedChannel,
      fingerprint: '',
      id: '',
      osVersion: '',
      platform: 'web' as GetDeviceResult['platform'],
      sdkVersion: '',
    };
  }

  async notifyRendered(): Promise<void> {}

  async getStatus(): Promise<GetStatusResult> {
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

  async ready(): Promise<ReadyResult> {
    return { currentRelease: null, isRolledBack: false, previousRelease: null };
  }

  async reset(): Promise<void> {}

  async rollback(): Promise<void> {}

  async setAttributes(): Promise<void> {}

  async setChannel(): Promise<void> {}

  async setRestartAllowed(): Promise<void> {}

  async sync(): Promise<SyncResult> {
    return { status: 'UP_TO_DATE', release: null };
  }
}
