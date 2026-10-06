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

The native cores are the Swift package `HotCodePushCore` and the Android library `com.hotcodepush:core-android`, each pinned to a commit until it is published. Swift Package Manager, Capacitor's default on iOS, resolves the pinned revision on its own. A CocoaPods app pins the commit `Package.swift` names in its Podfile:

```ruby
pod 'HotCodePushCore', :git => 'https://github.com/hotcodepush-team/core-ios.git', :commit => '<sha>'
```

An Android app adds JitPack, which builds the pinned commit, to the repositories in its `android/build.gradle`:

```groovy
allprojects {
  repositories {
    maven { url 'https://jitpack.io' }
  }
}
```

On Android the plugin keeps its store out of device backups and transfers: its manifest sets `android:fullBackupContent` and `android:dataExtractionRules` on `<application>`, merged into the app's manifest. An app that already sets either attribute hits a manifest-merger conflict. Add `tools:replace="android:fullBackupContent"` or `tools:replace="android:dataExtractionRules"` to your own `<application>`, and put `<exclude domain="file" path="hotcodepush/" />` into your own rules, inside both `<cloud-backup>` and `<device-transfer>` for the extraction rules; otherwise the store rides along in the backup again.

## Usage

```ts
import { HotCodePush } from '@hotcodepush/capacitor-live-updates';

const result = await HotCodePush.sync();
if (result.status === 'UPDATED') {
  console.log(`release #${result.release.number} installs ${result.installAt}`);
}
```

With `autoCheck` on, the default, the SDK checks on start, on resume and while the app stays in the foreground, and what follows a check is the download and install strategies' business; `sync()` is for the moment you want an update now. An app that asks before downloading sets `downloadStrategy` to `manual` and calls `downloadUpdate()` on `updateAvailable`; one that protects a flow sets `installStrategy` to `manual` and calls `applyUpdate()` when it is ready.

## Documentation

The SDK reference — configuration, methods, events, types and reasons — is at [hotcodepush.com/docs/capacitor](https://hotcodepush.com/docs/capacitor).

## Development

```sh
nvm use
npm ci
npm run lint
npm run build
npm run verify:ios       # the iOS build
npm run verify:android   # the Android build
```

The cores and their tests live in [core-ios](https://github.com/hotcodepush-team/core-ios) and [core-android](https://github.com/hotcodepush-team/core-android).

## License

See [LICENSE](./LICENSE). An app that ships the plugin ships the native cores' third-party code with it: FreeBSD's bspatch under the BSD 2-clause licence on both platforms and, on Android, the decompression of bzip2 1.0.8 under the bzip2 licence. The cores' `THIRD-PARTY-NOTICES`, in [core-ios](https://github.com/hotcodepush-team/core-ios/blob/main/THIRD-PARTY-NOTICES) and in [core-android](https://github.com/hotcodepush-team/core-android/blob/main/THIRD-PARTY-NOTICES), carry the notices, and an app's distribution reproduces them: the BSD 2-clause licence requires it of a binary, the bzip2 licence appreciates the acknowledgment.
