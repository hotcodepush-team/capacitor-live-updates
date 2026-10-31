#!/usr/bin/env node
// Prints the binary size of a prepared demo variant as JSON: the release APK and the Release simulator `.app`, in bytes.
import { execFileSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const [target] = process.argv.slice(2);
if (!target) {
  console.error('usage: measure-size.mjs <prepared demo>');
  process.exit(2);
}

// A benchmark build is never shipped. Offline, the build step writes the resource file without a channel and creates no binary,
// even when the machine holds a HotCodePush token.
const env = { ...process.env, HOTCODEPUSH_OFFLINE: '1' };

const sizes = {};
execFileSync('./gradlew', ['assembleRelease', '--console=plain', '-q'], {
  cwd: join(target, 'android'),
  env,
  stdio: ['ignore', 'ignore', 'inherit'],
});
sizes.android = {
  releaseApkBytes: statSync(
    join(target, 'android/app/build/outputs/apk/release/app-release.apk'),
  ).size,
};
const derivedData = join(target, 'ios/App/build');
execFileSync(
  'xcodebuild',
  [
    '-project',
    join(target, 'ios/App/App.xcodeproj'),
    '-scheme',
    'App',
    '-configuration',
    'Release',
    '-sdk',
    'iphonesimulator',
    '-destination',
    'generic/platform=iOS Simulator',
    '-derivedDataPath',
    derivedData,
    'CODE_SIGNING_ALLOWED=NO',
    '-quiet',
    'build',
  ],
  { env, stdio: ['ignore', 'ignore', 'inherit'] },
);
sizes.ios = {
  simulatorAppBytes: directorySize(
    join(derivedData, 'Build/Products/Release-iphonesimulator/App.app'),
  ),
};
console.log(JSON.stringify(sizes));

function directorySize(directory) {
  return readdirSync(directory, { withFileTypes: true }).reduce(
    (total, entry) => {
      const path = join(directory, entry.name);
      return (
        total +
        (entry.isDirectory() ? directorySize(path) : statSync(path).size)
      );
    },
    0,
  );
}
