#!/usr/bin/env node
// Copies the demo app into a scratch directory as one of the two variants the baseline compares: `with` installs the plugin tarball, `without` removes the plugin with its Xcode phase and Gradle line.
// Both variants keep the same screen, so only the plugin differs.
import { execFileSync } from 'node:child_process';
import { cpSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
  // The Xcode phase and the Gradle line run files of the plugin, so they go with it.
  const projectPath = join(target, 'ios/App/App.xcodeproj/project.pbxproj');
  writeFileSync(
    projectPath,
    readFileSync(projectPath, 'utf8')
      .replace(
        /\n\t\t\w+ \/\* Create HotCodePush binary \*\/ = \{[\s\S]*?\n\t\t\};/,
        '',
      )
      .split('\n')
      .filter(line => !line.includes('/* Create HotCodePush binary */'))
      .join('\n'),
  );
  const gradlePath = join(target, 'android/app/build.gradle');
  writeFileSync(
    gradlePath,
    readFileSync(gradlePath, 'utf8')
      .split('\n')
      .filter(line => !line.includes('@hotcodepush/capacitor-live-updates'))
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
console.log(`${variant}: ${target}`);

function run(command, args) {
  execFileSync(command, args, {
    cwd: target,
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}
