import { registerPlugin } from '@capacitor/core';

import type { HotCodePushPlugin } from './definitions';

interface HotCodePushInternalPlugin extends HotCodePushPlugin {
  notifyRendered(): Promise<void>;
}

const HotCodePush = registerPlugin<HotCodePushInternalPlugin>('HotCodePush', {
  web: () => import('./web').then(module => new module.HotCodePushWeb()),
});

/**
 * The readiness signal `render`: the first frame the app paints after the bundle loaded.
 */
function notifyRenderedOnFirstFrame(): void {
  if (
    typeof window === 'undefined' ||
    typeof requestAnimationFrame === 'undefined'
  ) {
    return;
  }
  const notify = () =>
    requestAnimationFrame(
      () => void HotCodePush.notifyRendered().catch(() => undefined),
    );
  if (document.readyState === 'complete') {
    notify();
  } else {
    window.addEventListener('load', notify, { once: true });
  }
}

notifyRenderedOnFirstFrame();

export * from './definitions';
export { HotCodePush };
