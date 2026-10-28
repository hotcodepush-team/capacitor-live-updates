# Capacitor live updates by HotCodePush

`@hotcodepush/capacitor-live-updates` is the Capacitor plugin that delivers over-the-air (OTA) updates to your app: a live update reaches installed apps in seconds, without a store review.
Learn more at [hotcodepush.com/capacitor-live-updates](https://hotcodepush.com/capacitor-live-updates).

## Installation

`npx hotcodepush init` installs the plugin and wires the build step into both native projects.
By hand, until the package is on npm, install the preview build pkg.pr.new publishes for every commit on `main`, pinned to a commit:

```sh
npm install https://pkg.pr.new/hotcodepush-team/capacitor-live-updates/@hotcodepush/capacitor-live-updates@<sha>
npx cap sync
```

The plugin needs Capacitor 7 or 8 and iOS 15 or later; a Capacitor 7 app on CocoaPods raises its deployment target to 15.0 first.
The native cores, `HotCodePushCore` on iOS and `com.hotcodepush:core-android`, resolve on their own.

Every native build writes `hotcodepush.json` into the app; an Xcode archive or a Gradle release build also registers the store build in HotCodePush, so it needs `npx hotcodepush login` or `HOTCODEPUSH_TOKEN`.

## Usage

```ts
import { HotCodePush } from '@hotcodepush/capacitor-live-updates';

const result = await HotCodePush.sync();
if (result.status === 'downloaded') {
  console.log(
    `release #${result.release.number} applies at ${result.applyStrategy}`,
  );
}
```

Import the package in the app's entry file: the import tells the SDK the app rendered, and an app that never imports it rolls every update back.
With the default `checkStrategy` of `auto`, the SDK checks on start, on resume and in the foreground; `sync()` runs one cycle on demand.
Set `downloadStrategy` or `applyStrategy` to `manual` and call `downloadUpdate()` or `applyUpdate()` yourself to control when an update lands.

## Documentation

See [hotcodepush.com/docs/capacitor](https://hotcodepush.com/docs/capacitor) for the configuration, methods, events, types and reasons.

## Development

```sh
nvm use
npm ci
npm run build            # the TypeScript into dist/; run it before opening the native projects
npm run lint
npm test                 # the Xcode build step's script tests, macOS only
npm run verify:ios       # the iOS build
npm run verify:android   # the Android build and its unit tests
npm run fmt              # run before every commit
```

The cores and their tests live in [core-ios](https://github.com/hotcodepush-team/core-ios) and [core-android](https://github.com/hotcodepush-team/core-android).
`CLAUDE.md` holds the layout and the rules.

## License

See [LICENSE](./LICENSE).
An app that ships the plugin also ships the native cores' third-party code: FreeBSD's bspatch (BSD 2-clause) on both platforms and bzip2 1.0.8 on Android. Reproduce the notices from [core-ios](https://github.com/hotcodepush-team/core-ios/blob/main/THIRD-PARTY-NOTICES) and [core-android](https://github.com/hotcodepush-team/core-android/blob/main/THIRD-PARTY-NOTICES) in your app's distribution.
