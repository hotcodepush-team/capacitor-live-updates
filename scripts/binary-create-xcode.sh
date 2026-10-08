#!/bin/sh
# The build step of the Xcode build, run by the "Create HotCodePush binary" phase `hotcodepush init` appends to the app
# target: the CLI writes hotcodepush.json into the app and, in a store build, creates the binary. The phase holds one
# line; what it runs lives here.
set -e

# The version managers and Homebrew, searched as React Native's find-node-for-xcode.sh searches them: each one present
# goes in front of PATH, so the last one found wins.
add_version_managers_to_path() {
  HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  if [ -d "$HOMEBREW_PREFIX/bin" ]; then
    PATH="$HOMEBREW_PREFIX/bin:$PATH"
  fi
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  for NVM_SCRIPT in "$NVM_DIR/nvm.sh" "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"; do
    if [ -s "$NVM_SCRIPT" ]; then
      export NVM_DIR
      . "$NVM_SCRIPT" --no-use
      nvm use >/dev/null 2>&1 || nvm use default >/dev/null 2>&1
      break
    fi
  done
  ASDF_SHIMS="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
  if [ -d "$ASDF_SHIMS" ]; then
    PATH="$ASDF_SHIMS:$PATH"
  fi
  VOLTA_BIN="${VOLTA_HOME:-$HOME/.volta}/bin"
  if [ -x "$VOLTA_BIN/node" ]; then
    PATH="$VOLTA_BIN:$PATH"
  fi
  for FNM in "$(command -v fnm || true)" "$HOME/.fnm/fnm" "$HOME/Library/Application Support/fnm/fnm"; do
    if [ -x "$FNM" ]; then
      eval "$("$FNM" env --shell bash)"
      break
    fi
  done
}

# The built app, where the target builds its product: an archive installs it apart from the configuration's directory, and
# a CONFIGURATION_BUILD_DIR given on the command line leaves this one pointing at the real product. The resource file
# lands beside the app's public directory, never inside the bundle it hashes.
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
# Capacitor's Xcode project sits in ios/App, two levels below the project's package.json and hotcodepush.json.
PROJECT_ROOT="${PROJECT_ROOT:-$PROJECT_DIR/../..}"

cd "$PROJECT_ROOT"

# Xcode's PATH has no Node when the build starts in Xcode. React Native's convention names it: NODE_BINARY in .xcode.env
# beside the Xcode project, overridden by .xcode.env.local; without either, the version managers and Homebrew are searched.
NODE_BINARY=$(command -v node || true)
for XCODE_ENV_PATH in "$PROJECT_DIR/.xcode.env" "$PROJECT_DIR/.xcode.env.local"; do
  if [ -f "$XCODE_ENV_PATH" ]; then
    . "$XCODE_ENV_PATH"
  fi
done
if [ -z "$NODE_BINARY" ]; then
  add_version_managers_to_path || true
  NODE_BINARY=$(command -v node || true)
fi
if [ -z "$NODE_BINARY" ]; then
  echo "error: HotCodePush found no Node to run its build step; name it in $PROJECT_DIR/.xcode.env: export NODE_BINARY=/path/to/node" >&2
  exit 1
fi
# npx sits beside Node.
PATH="$(dirname "$NODE_BINARY"):$PATH"
export PATH

# Only a store build creates the binary: an archive, the build Xcode's "Run script only when installing" means; every
# other build writes the resource file alone. The binary's identity is the one the device reports, from the built app's
# processed Info.plist: Capacitor's template expands MARKETING_VERSION and CURRENT_PROJECT_VERSION there, and an app that
# writes the version and build as literals keeps its own.
if [ "$DEPLOYMENT_POSTPROCESSING" = "YES" ]; then
  INFO_PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
  BINARY_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
  BINARY_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
  set -- binary create --binary-version "$BINARY_VERSION" --binary-build "$BINARY_BUILD"
else
  set -- resource-file write
fi

npx hotcodepush "$@" \
  --platform ios \
  --embedded-bundle-path "$DEST/public" \
  --resource-file-path "$DEST/hotcodepush.json"
