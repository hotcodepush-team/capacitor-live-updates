# Capacitor live updates by HotCodePush

[![npm](https://img.shields.io/npm/v/@hotcodepush/capacitor-live-updates)](https://www.npmjs.com/package/@hotcodepush/capacitor-live-updates)
[![CI](https://github.com/hotcodepush-team/capacitor-live-updates/actions/workflows/ci.yml/badge.svg)](https://github.com/hotcodepush-team/capacitor-live-updates/actions/workflows/ci.yml)
[![License](https://img.shields.io/npm/l/@hotcodepush/capacitor-live-updates)](./LICENSE)

`@hotcodepush/capacitor-live-updates` is the Capacitor plugin that delivers over-the-air (OTA) updates to your app. Ship a web build fix with one command, reach every installed app within seconds, and roll it back from the console if something goes wrong. No store review, no new build.
Learn more at [hotcodepush.com/capacitor-live-updates](https://hotcodepush.com/capacitor-live-updates).

<a href="https://hotcodepush.com/">
  <img alt="Ship updates in seconds. Over-the-air updates for React Native, Expo, Capacitor and Cordova. Get started." src="https://hotcodepush.com/assets/banners/readme-banner-ember.png" width="100%" />
</a>

## Features

- ⚡️ **One command to release.** `npm run build && npx hotcodepush release create` uploads, signs and publishes your web build for both platforms.
- 📺 **Channels.** Staging, beta and production, each with its own release log, and promotion between them.
- 🚀 **Staged rollouts.** Start at 5 percent, widen in steps, and let the automatic pause stop a release that fails on devices.
- 🛟 **Rollback.** One command or one click sends every device back to the release before.
- 🔁 **Delta updates.** A device downloads what changed, built on the platform from the bundle it runs.
- 🔒 **Code signing.** The app runs only bundles signed with your key, which never leaves your machine or your CI.
- 🎯 **Conditions.** Target a release by binary version, OS version, device attributes or a list of devices.
- 🖥️ **Console, CLI and GitHub Action.** Watch devices arrive on a release in the console, release from the terminal, or from a workflow step.
- 🤖 **Built for agents.** An MCP server and agent skills let Claude Code or Cursor set up, release and debug for you.
- 🌐 **Open source.** The plugin, the CLI, the clients and the Action are MIT licensed.

## Compatibility

| Plugin | Capacitor | iOS          | Android                |
| ------ | --------- | ------------ | ---------------------- |
| 0.x    | 8 and 7   | 15 and later | 6.0 (API 23) and later |

## Demo

[capacitor-live-updates-demo](https://github.com/hotcodepush-team/capacitor-live-updates-demo) is a Capacitor app with the plugin wired in, built on both platforms and released through the GitHub Action on every merge.

## Guides

- [Quickstart](https://hotcodepush.com/docs/quickstart), the first release end to end
- [Migrate from Ionic Appflow](https://hotcodepush.com/docs/migrate/ionic-appflow), [from Capawesome Cloud](https://hotcodepush.com/docs/migrate/capawesome-cloud) or [from Capgo](https://hotcodepush.com/docs/migrate/capgo), with the mapping of every command and option
- [Release from CI](https://hotcodepush.com/docs/ci), GitHub Actions, GitLab, Bitrise, Codemagic and more

## Installation

### AI-assisted setup (recommended)

Paste this prompt into the agent or assistant you use:

```text
Set up HotCodePush OTA updates in this project, following https://hotcodepush.com/docs/quickstart.md. If you can run commands, install the agent skills with `npx skills add hotcodepush-team/skills`, then run hotcodepush-init and hotcodepush-release. If you cannot run commands, read that page and give me the steps to do it myself.
```

An agent that runs commands installs the plugin, creates the app and the channel, and ships the first update. An assistant without a shell reads the quickstart and hands you the steps. [Agent skills](https://hotcodepush.com/docs/ai/skills) explains what the agent does.

### Set up with the CLI

```sh
npx hotcodepush init
```

`init` signs you in, picks or creates the app, installs the plugin, writes `hotcodepush.json`, adds the import to your entry file, wires the build step into both native projects and offers a signing key. Build the app once in release, an Xcode archive or a Gradle release variant, so the store build registers itself. Then change something and ship it:

```sh
npm run build && npx hotcodepush release create
```

The installed app downloads the release at its next start and runs it from the start after that.

Prefer to wire it yourself? The [installation guide](https://hotcodepush.com/docs/sdks/capacitor/installation) has the steps by hand: the package and `npx cap sync`, `hotcodepush.json`, the import, the Xcode phase and the Gradle line, and the check with `doctor`.

## Usage

### Sync and read the result

With the default `checkStrategy` of `auto`, the SDK checks on start, on resume and in the foreground, and `sync()` runs one cycle on demand. Applying an update reloads the app's web view.

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

### Show your users what is happening

Five events follow a cycle, so a badge, a progress bar or a restart prompt is a listener each:

```ts
await HotCodePush.addListener('updateAvailable', ({ release }) =>
  showBadge(release.bundleVersion),
);
await HotCodePush.addListener('downloadProgress', ({ progress }) =>
  showProgress(progress),
);
await HotCodePush.addListener('updateDownloaded', () =>
  askToRestart(() => HotCodePush.applyUpdate()),
);
```

### Decide when an update lands

Set `downloadStrategy` and `applyStrategy` to `manual` in `hotcodepush.json`, then download and apply at the moments you choose, and hold the SDK's own restarts while a flow must not be interrupted:

```ts
await HotCodePush.setRestartAllowed({ isAllowed: false });
await HotCodePush.downloadUpdate();
await HotCodePush.setRestartAllowed({ isAllowed: true });
await HotCodePush.applyUpdate();
```

A release that never renders is rolled back on its own, and `rollbackUpdate()` does the same on your call, so nothing above is needed for safety.

### Target the right devices

A release with an `--attribute plan=enterprise` condition reaches the devices that carry the attribute, and a beta switch in your settings screen is one call. The channel sticks until the app clears it with `setChannel(null)`:

```ts
await HotCodePush.setAttributes({ plan: 'enterprise', userId: '42' });
await HotCodePush.setChannel({ name: 'beta' });
```

### See why a device did not update

The debug screen shows the device id, the channel, the binary and the result of the last check, the first stop for a device that did not update. `getState()` gives the same to your own diagnostics:

```ts
await HotCodePush.showDebugScreen();
const { currentRelease, lastCheck } = await HotCodePush.getState();
```

## Documentation

See [hotcodepush.com/docs/sdks/capacitor](https://hotcodepush.com/docs/sdks/capacitor) for the configuration, methods, events, types and reasons.

## Development

See [CLAUDE.md](./CLAUDE.md) for the layout and the commands, and [CONTRIBUTING.md](https://github.com/hotcodepush-team/.github/blob/main/CONTRIBUTING.md) for the rules of a change.
The native cores live in [core-ios](https://github.com/hotcodepush-team/core-ios) and [core-android](https://github.com/hotcodepush-team/core-android).

## License

See [LICENSE](./LICENSE).
An app that ships the plugin also ships the native cores' third-party code: FreeBSD's bspatch (BSD 2-clause) on both platforms and bzip2 1.0.8 on Android. Reproduce the notices from [core-ios](https://github.com/hotcodepush-team/core-ios/blob/main/THIRD-PARTY-NOTICES) and [core-android](https://github.com/hotcodepush-team/core-android/blob/main/THIRD-PARTY-NOTICES) in your app's distribution.
