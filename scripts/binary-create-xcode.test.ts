import { execFileSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const APP_NAME = 'App.app';

// The plist Xcode's Info.plist processing leaves in the app, converted to the binary format it writes; the values are invented.
const PROCESSED_INFO_PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>2.4.1</string>
  <key>CFBundleVersion</key>
  <string>57</string>
</dict>
</plist>
`;

// npx as the script finds it beside Node: it records the arguments, one per line, and its working directory instead of running the CLI.
const RECORDING_NPX =
  '#!/bin/sh\nprintf "%s\\n" "$@" > "$(dirname "$0")/arguments"\npwd > "$(dirname "$0")/directory"\n';

const SCRIPT_PATH = join(import.meta.dirname, 'binary-create-xcode.sh');

// The script runs inside Xcode, which runs on macOS alone, as does PlistBuddy.
describe.skipIf(process.platform !== 'darwin')('binary-create-xcode.sh', () => {
  let appPath: string;
  let homePath: string;
  let projectPath: string;
  let xcodeProjectPath: string;

  beforeEach(() => {
    projectPath = realpathSync(
      mkdtempSync(join(tmpdir(), 'binary-create-xcode-')),
    );
    xcodeProjectPath = join(projectPath, 'ios', 'App');
    mkdirSync(xcodeProjectPath, { recursive: true });
    appPath = join(projectPath, 'build', APP_NAME);
    mkdirSync(join(appPath, 'public'), { recursive: true });
    writeFileSync(join(appPath, 'Info.plist'), PROCESSED_INFO_PLIST);
    execFileSync('plutil', [
      '-convert',
      'binary1',
      join(appPath, 'Info.plist'),
    ]);
    writeFileSync(join(appPath, 'public', 'index.html'), '');
    homePath = join(projectPath, 'home');
    mkdirSync(homePath);
  });

  afterEach(() => {
    rmSync(projectPath, { force: true, recursive: true });
  });

  it('should create the binary with the version and build of the processed Info.plist, which the device reports, when the build archives', () => {
    const nodeDirectoryPath = installNode('bin');

    runScript({
      DEPLOYMENT_POSTPROCESSING: 'YES',
      PATH: `${nodeDirectoryPath}:/usr/bin:/bin`,
    });

    expect(readArguments(nodeDirectoryPath)).toEqual([
      'hotcodepush',
      'binary',
      'create',
      '--binary-version',
      '2.4.1',
      '--binary-build',
      '57',
      '--platform',
      'ios',
      '--embedded-bundle-path',
      join(appPath, 'public'),
      '--resource-file-path',
      join(appPath, 'hotcodepush.json'),
    ]);
  });

  it('should write the resource file alone when the build does not archive', () => {
    const nodeDirectoryPath = installNode('bin');

    runScript({
      DEPLOYMENT_POSTPROCESSING: 'NO',
      PATH: `${nodeDirectoryPath}:/usr/bin:/bin`,
    });

    expect(readArguments(nodeDirectoryPath)).toEqual([
      'hotcodepush',
      'resource-file',
      'write',
      '--platform',
      'ios',
      '--embedded-bundle-path',
      join(appPath, 'public'),
      '--resource-file-path',
      join(appPath, 'hotcodepush.json'),
    ]);
  });

  it("should run the CLI in the project's directory, two levels above the Xcode project", () => {
    const nodeDirectoryPath = installNode('bin');

    runScript({ PATH: `${nodeDirectoryPath}:/usr/bin:/bin` });

    expect(
      readFileSync(join(nodeDirectoryPath, 'directory'), 'utf8').trimEnd(),
    ).toBe(projectPath);
  });

  it("should take Node from .xcode.env when Xcode's PATH has none", () => {
    const nodeDirectoryPath = installNode('xcode-env-node');
    writeXcodeEnv('.xcode.env', nodeDirectoryPath);

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should take Node from .xcode.env.local over .xcode.env', () => {
    writeXcodeEnv('.xcode.env', installNode('xcode-env-node'));
    const nodeDirectoryPath = installNode('xcode-env-local-node');
    writeXcodeEnv('.xcode.env.local', nodeDirectoryPath);

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should find Node through nvm when no .xcode.env names it', () => {
    const nodeDirectoryPath = installNode('home/.nvm/versions/node/v24/bin');
    writeExecutable(
      join(homePath, '.nvm', 'nvm.sh'),
      `nvm() { PATH="${nodeDirectoryPath}:$PATH"; }\n`,
    );

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should find Node through asdf when no .xcode.env names it', () => {
    const nodeDirectoryPath = installNode('home/.asdf/shims');

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should find Node through Volta when no .xcode.env names it', () => {
    const nodeDirectoryPath = installNode('home/.volta/bin');

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should find Node through fnm when no .xcode.env names it', () => {
    const nodeDirectoryPath = installNode('home/.fnm/aliases/default/bin');
    writeExecutable(
      join(homePath, '.fnm', 'fnm'),
      `#!/bin/sh\necho 'export PATH="${nodeDirectoryPath}:$PATH"'\n`,
    );

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it("should find Node in Homebrew's bin when no .xcode.env names it", () => {
    const nodeDirectoryPath = installNode('homebrew/bin');

    runScript();

    expect(readArguments(nodeDirectoryPath)[0]).toBe('hotcodepush');
  });

  it('should fail naming .xcode.env when no Node is found', () => {
    expect(() => runScript()).toThrow(/\.xcode\.env/);
  });

  /**
   * A Node install at the path below the project's directory: a `node` that does nothing and the recording npx beside it.
   */
  function installNode(relativePath: string): string {
    const directoryPath = join(projectPath, relativePath);
    mkdirSync(directoryPath, { recursive: true });
    writeExecutable(join(directoryPath, 'node'), '#!/bin/sh\n');
    writeExecutable(join(directoryPath, 'npx'), RECORDING_NPX);
    return directoryPath;
  }

  function readArguments(nodeDirectoryPath: string): string[] {
    return readFileSync(join(nodeDirectoryPath, 'arguments'), 'utf8')
      .trimEnd()
      .split('\n');
  }

  /**
   * Runs the script with the build settings Xcode gives a phase of the app target and a PATH without Node, as Xcode's own;
   * HOME and Homebrew's prefix lie inside the project's directory, so no version manager of this machine answers.
   */
  function runScript(environment: Record<string, string> = {}): void {
    execFileSync('/bin/sh', [SCRIPT_PATH], {
      env: {
        CONFIGURATION_BUILD_DIR: join(projectPath, 'build'),
        DEPLOYMENT_POSTPROCESSING: 'NO',
        HOME: homePath,
        HOMEBREW_PREFIX: join(projectPath, 'homebrew'),
        INFOPLIST_PATH: join(APP_NAME, 'Info.plist'),
        PATH: '/usr/bin:/bin',
        PROJECT_DIR: xcodeProjectPath,
        TARGET_BUILD_DIR: join(projectPath, 'build'),
        UNLOCALIZED_RESOURCES_FOLDER_PATH: APP_NAME,
        ...environment,
      },
      stdio: 'pipe',
    });
  }

  function writeExecutable(filePath: string, content: string): void {
    writeFileSync(filePath, content, { mode: 0o755 });
  }

  function writeXcodeEnv(fileName: string, nodeDirectoryPath: string): void {
    writeFileSync(
      join(xcodeProjectPath, fileName),
      `export NODE_BINARY=${join(nodeDirectoryPath, 'node')}\n`,
    );
  }
});
