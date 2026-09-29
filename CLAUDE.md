# CLAUDE.md

The HotCodePush Capacitor SDK: `@hotcodepush/capacitor-live-updates`, the plugin that delivers live updates to Capacitor apps on iOS and Android.
Stack: TypeScript for the plugin surface, Swift for the iOS core, Kotlin for the Android core, Capacitor 7 and 8.

The plan is the private `handbook` repo, checked out beside this one: `../handbook/docs/`.
`sdk-api.md` is the SDK's specification — the methods, the configuration, the state keys, the wire shapes and the reason catalog; `architecture.md`'s _The device protocol_ and _Packs_ are the behaviour behind them.
When code and plan disagree, stop and surface it; never improvise.

## Layout

```
src/                        definitions.ts (the plugin interface), index.ts, web.ts (the no-op)
ios/Sources/HotCodePushCore     the core: no Capacitor import, tested on the host with XCTest
ios/Sources/HotCodePushPlugin   the Capacitor plugin and the bundle loader
ios/Tests/HotCodePushCoreTests  the core's tests
android/src/main/java/com/hotcodepush/core       the core: no Capacitor import, tested on the JVM with JUnit
android/src/main/java/com/hotcodepush/capacitor  the Capacitor plugin and the bundle loader
android/src/test                                 the core's tests
```

The native core lives here until the React Native SDK becomes its second consumer, when it moves to `protocol-ios` and `protocol-android`.
Both cores implement the same functions with the same names, `sdk-api.md`'s _The state and the functions_: a change to one is a change to the other.

## Commands

| Command                                | Does                               |
| -------------------------------------- | ---------------------------------- |
| `npm run lint`                         | ESLint, Prettier and SwiftLint     |
| `npm run build`                        | the TypeScript into `dist/`        |
| `npm run test:ios`                     | the Swift core's tests on the host |
| `npm run test:android`                 | the Kotlin core's tests on the JVM |
| `npm run verify:ios`, `verify:android` | the tests plus the platform build  |

Run `npm run fmt` before every commit.

## Dependencies during the build phase

Consumers pin the preview builds pkg.pr.new publishes from `ci.yml` on every push and pull request, never npm: `npm install https://pkg.pr.new/hotcodepush-team/capacitor-live-updates/@hotcodepush/capacitor-live-updates@<sha>`, `@main` for the newest.
The shared types come from `@hotcodepush/protocol` the same way, `https://pkg.pr.new/hotcodepush-team/protocol-js/@hotcodepush/protocol@<sha>`; until its first build exists `src/definitions.ts` carries the placeholder marked `TODO(protocol-js#2)`.

## Rules

- The SDK never sees an API DTO: its contract is the channel index, the bundle manifest and the events endpoint, additive only.
- Safety is on by default and cannot be switched off: the readiness gate, the local blocklist, the automatic rollback.
- Nothing a device does not need to decide lives here: rollout, conditions, revocation and the cap are evaluated from the index, never configured.
- Every key in the store is `hotcodepush.<name>`; three identity keys survive everything, the rest is a cache dropped on an unknown `stateVersion`.
- Statuses and reasons are `SCREAMING_SNAKE_CASE` from the one catalog; a method throws a plain error only for a programming mistake.
- Results are one shape per method and never throw for an outcome an app should handle.
- The Capacitor constraint on iOS: a served bundle is laid out under `Library/NoCloud/ionic_built_snapshots/<bundleId>`, the only place Capacitor resolves its persisted base path.

## Agent workspace

- `.mcp.json` registers the Capacitor server; the HotCodePush server joins when it exists.
- `.claude/skills/` holds the developer skills copied from `hotcodepush-team/.github`, pinned in `skills-lock.json`.
- Commits are conventional commits; `main` is trunk, CI is the gate, and a commit that lands an issue says `Closes #<n>`.
