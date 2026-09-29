#!/usr/bin/env node
// Copies the demo app into a scratch directory as one of the two variants the baseline compares:
// `with` installs the plugin tarball, `without` removes the plugin, its hook and its resource file
// and swaps the screen's script for the same screen with nothing behind it. Both log the first paint.
import { execFileSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';

const [source, target, variant, tarball] = process.argv.slice(2);
if (
  !source ||
  !target ||
  !['with', 'without'].includes(variant) ||
  (variant === 'with' && !tarball)
) {
  console.error(
    'usage: prepare-demo.mjs <demo> <target> with <plugin.tgz> | without',
  );
  process.exit(2);
}

const excluded = new Set([
  'node_modules',
  'dist',
  '.git',
  'build',
  '.gradle',
  'DerivedData',
]);
rmSync(target, { recursive: true, force: true });
cpSync(source, target, {
  recursive: true,
  filter: path => !excluded.has(path.split('/').pop()),
});

const firstPaintMarker =
  "requestAnimationFrame(() => console.log('[baseline] first paint'));";
const mainPath = join(target, 'src/main.ts');
if (variant === 'with') {
  writeFileSync(
    mainPath,
    readFileSync(mainPath, 'utf8').replace(
      'void showState();',
      `${firstPaintMarker}\nvoid showState();`,
    ),
  );
  run('npm', ['install', tarball, '--no-audit', '--no-fund']);
} else {
  run('npm', [
    'uninstall',
    '@hotcodepush/capacitor-live-updates',
    '--no-audit',
    '--no-fund',
  ]);
  const packagePath = join(target, 'package.json');
  const manifest = JSON.parse(readFileSync(packagePath, 'utf8'));
  delete manifest.scripts['capacitor:copy:after'];
  writeFileSync(packagePath, `${JSON.stringify(manifest, null, 2)}\n`);
  for (const resourceFile of [
    'android/app/src/main/assets/hotcodepush.json',
    'ios/App/App/hotcodepush.json',
  ]) {
    rmSync(join(target, resourceFile), { force: true });
  }
  // The demo's Xcode project bundles the resource file; without the file, the reference has to go too.
  const projectPath = join(target, 'ios/App/App.xcodeproj/project.pbxproj');
  writeFileSync(
    projectPath,
    readFileSync(projectPath, 'utf8')
      .split('\n')
      .filter(line => !line.includes('hotcodepush.json'))
      .join('\n'),
  );
  writeFileSync(
    mainPath,
    `// The demo without the plugin: the same screen, nothing behind it — the baseline's control.
const VERSION = 'v1';

const versionHeading = getElement('version');
const currentReleaseText = getElement('current-release');
const deviceIdText = getElement('device-id');
const lastSyncText = getElement('last-sync');
const syncButton = getElement<HTMLButtonElement>('sync-button');

versionHeading.textContent = VERSION;
syncButton.addEventListener('click', () => undefined);
${firstPaintMarker}
currentReleaseText.textContent = 'embedded';
deviceIdText.textContent = 'none';
lastSyncText.textContent = 'none yet';

function getElement<T extends HTMLElement = HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(\`Missing element #\${id}\`);
  return element as T;
}
`,
  );
}
run('npm', ['install', '--no-audit', '--no-fund']);
run('npm', ['run', 'build']);
run('npx', ['cap', 'sync']);
if (
  variant === 'with' &&
  !existsSync(join(target, 'android/app/src/main/assets/hotcodepush.json'))
) {
  throw new Error(
    "the resource file was not written; the demo's capacitor:copy:after hook did not run",
  );
}
console.log(`${variant}: ${target}`);

function run(command, args) {
  execFileSync(command, args, {
    cwd: target,
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}
