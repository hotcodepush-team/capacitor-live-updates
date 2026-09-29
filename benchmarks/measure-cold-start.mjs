#!/usr/bin/env node
// Cold-start milliseconds of a prepared demo variant: from the launch to the web view's first paint —
// the `[baseline] first paint` console line the demo logs on its first animation frame — median of N
// cold launches on the Pixel_9_Pro emulator and the iPhone simulator, both on debug builds so the web
// view's console reaches the host. Prints JSON with every run.
import { execFileSync, spawn } from 'node:child_process';
import { join } from 'node:path';

const args = process.argv.slice(2);
const target = args[0];
const option = name => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const runs = Number(option('--runs') ?? 5);
const androidSerial = option('--android');
const iosUdid = option('--ios');
if (!target || (!androidSerial && !iosUdid)) {
  console.error(
    'usage: measure-cold-start.mjs <prepared demo> [--android <serial>] [--ios <udid>] [--runs 5]',
  );
  process.exit(2);
}
const bundleId = 'com.hotcodepush.demo.capacitor';
const marker = '[baseline] first paint';

const result = {};
if (androidSerial) result.android = await measureAndroid();
if (iosUdid) result.ios = await measureIos();
console.log(JSON.stringify(result));

async function measureAndroid() {
  const apk = join(target, 'android/app/build/outputs/apk/debug/app-debug.apk');
  execFileSync('./gradlew', ['assembleDebug', '--console=plain', '-q'], {
    cwd: join(target, 'android'),
    stdio: ['ignore', 'ignore', 'inherit'],
  });
  adb('install', '-r', apk);
  const samples = [];
  for (let run = 0; run < runs; run++) {
    adb('shell', 'am', 'force-stop', bundleId);
    await waitFor(() => adb('shell', 'pidof', bundleId).trim() === '');
    adb('logcat', '-c');
    await sleep(1500);
    adb('shell', 'am', 'start', '-n', `${bundleId}/.MainActivity`);
    const lines = await waitForLog(
      () => adb('logcat', '-d', '-v', 'epoch'),
      marker,
    );
    const started = epochOf(
      lines.find(line =>
        /ActivityTaskManager: START u0 .*cmp=com\.hotcodepush\.demo\.capacitor/.test(
          line,
        ),
      ),
    );
    const painted = epochOf(lines.find(line => line.includes(marker)));
    samples.push(Math.round(painted - started));
  }
  return summarize(samples);
}

async function measureIos() {
  // A Debug build, since Capacitor forwards the web view's console to stdout only in debug builds; both variants alike.
  // The console arrives through a pseudo-terminal: a pipe would buffer the process's stdout until it exits.
  const derivedData = join(target, 'ios/App/build-debug');
  execFileSync(
    'xcodebuild',
    [
      '-project',
      join(target, 'ios/App/App.xcodeproj'),
      '-scheme',
      'App',
      '-configuration',
      'Debug',
      '-sdk',
      'iphonesimulator',
      '-destination',
      `id=${iosUdid}`,
      '-derivedDataPath',
      derivedData,
      'CODE_SIGNING_ALLOWED=NO',
      '-quiet',
      'build',
    ],
    { stdio: ['ignore', 'ignore', 'inherit'] },
  );
  simctl(
    'install',
    iosUdid,
    join(derivedData, 'Build/Products/Debug-iphonesimulator/App.app'),
  );
  const samples = [];
  for (let run = 0; run < runs; run++) {
    simctl('terminate', iosUdid, bundleId);
    await sleep(1500);
    const launchedAt = Date.now();
    const console = spawn('xcrun', [
      'simctl',
      'launch',
      '--console-pty',
      iosUdid,
      bundleId,
    ]);
    let output = '';
    let paintedAt = null;
    console.stdout.on('data', chunk => {
      output += chunk;
      if (paintedAt === null && output.includes(marker)) paintedAt = Date.now();
    });
    await waitFor(() => paintedAt !== null);
    console.kill();
    samples.push(paintedAt - launchedAt);
  }
  simctl('terminate', iosUdid, bundleId);
  return summarize(samples);
}

function summarize(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  return { medianMs: sorted[Math.floor(sorted.length / 2)], runsMs: samples };
}

function adb(...commandArgs) {
  try {
    return execFileSync('adb', ['-s', androidSerial, ...commandArgs], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'inherit'],
      timeout: 60_000,
    });
  } catch (error) {
    // `pidof` exits with 1 when no process runs, which is the answer the stop waits for.
    if (commandArgs[1] === 'pidof') return '';
    throw error;
  }
}

function simctl(...commandArgs) {
  try {
    return execFileSync('xcrun', ['simctl', ...commandArgs], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return '';
  }
}

function epochOf(line) {
  if (!line) throw new Error('the expected log line did not appear');
  return Number(line.trim().split(/\s+/)[0]) * 1000;
}

async function waitForLog(read, needle) {
  for (let attempt = 0; attempt < 80; attempt++) {
    const text = read();
    if (text.includes(needle)) return text.split('\n');
    await sleep(500);
  }
  throw new Error(`no "${needle}" within 40 seconds`);
}

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if (predicate()) return;
    await sleep(250);
  }
  throw new Error('the first paint did not appear within 30 seconds');
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
