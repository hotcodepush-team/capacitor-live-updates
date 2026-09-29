# Capacitor live updates by HotCodePush

`@hotcodepush/capacitor-live-updates` is the Capacitor plugin that delivers over-the-air updates to your app: a live update reaches installed apps in seconds, without a store review. Learn more at [hotcodepush.com/capacitor-live-updates](https://hotcodepush.com/capacitor-live-updates).

## Installation

Until the package is published, install the preview build pkg.pr.new publishes for every commit on `main`, pinned to a commit:

```sh
npm install https://pkg.pr.new/hotcodepush-team/capacitor-live-updates/@hotcodepush/capacitor-live-updates@<sha>
npx cap sync
```

A consumer pins a commit and bumps it deliberately; the preview comment on each commit names its `<sha>`.

The plugin reads `hotcodepush.json` from the app's resources, which `npx hotcodepush init` writes and the embed step carries into every native build.

## Usage

```ts
import { HotCodePush } from '@hotcodepush/capacitor-live-updates';

const result = await HotCodePush.sync();
if (result.status === 'UPDATED') {
  console.log(`release #${result.release.number} installs ${result.installAt}`);
}
```

With `autoSync` on, the default, the SDK syncs on start, on resume and while the app stays in the foreground; `sync()` is for the moment you want an update now.

## Documentation

The SDK reference — configuration, methods, events, types and reasons — is at [hotcodepush.com/docs/capacitor](https://hotcodepush.com/docs/capacitor).

## Development

```sh
nvm use
npm ci
npm run lint
npm run build
npm run test:ios       # the Swift core on the host
npm run test:android   # the Kotlin core on the JVM
```

`npm run verify:ios` and `npm run verify:android` add the platform builds. The iOS package builds with `xcodebuild -scheme HotcodepushCapacitorLiveUpdates -destination generic/platform=iOS`.

## License

See [LICENSE](./LICENSE).
