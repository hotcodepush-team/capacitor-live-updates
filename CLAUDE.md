# CLAUDE.md

The HotCodePush Capacitor SDK: `@hotcodepush/capacitor-live-updates`, the plugin that delivers live updates to Capacitor apps on iOS and Android.
Stack: TypeScript for the plugin surface, Swift for the iOS plugin layer, Kotlin for the Android plugin layer, Capacitor 7 and 8.

The plan is the private `handbook` repo, checked out beside this one: `../handbook/docs/`.
`sdk-api.md` is the SDK's specification — the methods, the configuration, the state keys, the wire shapes and the reason catalog; `architecture.md`'s _The device protocol_ and _Packs_ are the behaviour behind them.
When code and plan disagree, stop and surface it; never improvise.

## Layout

```
src/                                             definitions.ts (the plugin interface), index.ts, web.ts (the no-op)
ios/Sources/HotCodePushPlugin                    the Capacitor plugin and the bundle loader over HotCodePushCore
android/src/main/java/com/hotcodepush/capacitor  the Capacitor plugin, the bundle loader over com.hotcodepush:core-android and PageEvents, which holds the events of a reload for the page that follows it
android/src/test                                 the plugin's unit tests on Robolectric, which verify:android runs
android/hotcodepush.gradle                       the Gradle build step, a task per variant the app applies from its build.gradle
scripts/                                         the Xcode build step's script, with the Node lookup, and its tests
```

The native cores live in `core-ios` and `core-android`, consumed at pinned commits: `Package.swift` by `revision`, the pod through the consumer's Podfile by `:git` and `:commit`, the Android module from core-android's `maven` branch by full sha, which `android/build.gradle` adds to every project of the app's build; a core change lands there first and arrives here as a bump of the pin.
The plugin layer keeps the bundle loader, the readiness signal and the bridge, nothing of the protocol.

## Commands

| Command                                | Does                                             |
| -------------------------------------- | ------------------------------------------------ |
| `npm run lint`                         | ESLint, Prettier and SwiftLint                   |
| `npm run build`                        | the TypeScript into `dist/`                      |
| `npm run verify:ios`, `verify:android` | the platform builds, Android with its unit tests |
| `npm test`                             | the Xcode build step's script tests, macOS only  |

Run `npm run fmt` before every commit.

## Dependencies during the build phase

Consumers pin the preview builds pkg.pr.new publishes from `ci.yml` on every push and pull request, never npm: `npm install https://pkg.pr.new/hotcodepush-team/capacitor-live-updates/@hotcodepush/capacitor-live-updates@<sha>`.
A consumer pins a commit and bumps it deliberately — never `@main`, whose moving content breaks `npm ci` against the lockfile's integrity hash.
The shared types come from `@hotcodepush/protocol` the same way, pinned to a commit: `https://pkg.pr.new/hotcodepush-team/protocol/@hotcodepush/protocol@<sha>` in `package.json`; a protocol change is a bump of that sha.

## Rules

- The SDK never sees an API DTO: its contract is the channel index, the bundle manifest and the events endpoint, additive only.
- Safety is on by default and cannot be switched off: the readiness gate, the local blocklist, the automatic rollback.
- Nothing a device does not need to decide lives here: rollout, conditions, revocation and the cap are evaluated from the index, never configured.
- Every key in the store is `hotcodepush.<name>`; three identity keys survive everything, the rest is a cache dropped on an unknown `stateVersion`.
- Statuses and reasons are `SCREAMING_SNAKE_CASE` from the one catalog; a method throws a plain error only for a programming mistake.
- Results are one shape per method and never throw for an outcome an app should handle.
- The Capacitor constraint on iOS: a served bundle is laid out under `Library/NoCloud/ionic_built_snapshots/<bundleId>`, the only place Capacitor resolves its persisted base path.
- On Android, Capacitor loads a persisted `serverBasePath` twice at the start: `setServerBasePath()` posts a load and `loadWebView()` loads directly. Both page starts are the SDK's own, so the loader arms the page hold once more behind Capacitor's posted load when the start serves a downloaded bundle; a page start counted as the app's reload would apply a stored `next-start` release in the same launch. iOS reads the persisted path in `instanceDescriptor()` and loads once.

## Agent workspace

- `.mcp.json` registers the Capacitor server; the HotCodePush server joins when it exists.
- `.claude/skills/` holds the developer skills copied from `hotcodepush-team/.github`, pinned in `skills-lock.json`.
- Commits are conventional commits; `main` is trunk, CI is the gate, and a commit that lands an issue says `Closes #<n>`.
