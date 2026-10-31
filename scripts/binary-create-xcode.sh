#!/bin/sh
# The "Create HotCodePush binary" phase, which `hotcodepush init` appends to the app target, runs this script.
# The phase holds a single line, so the logic lives here.
set -e

# HOMEBREW_PREFIX overrides the default prefixes of Apple silicon and Intel Macs.
homebrew_paths() {
  for HOMEBREW in ${HOMEBREW_PREFIX:-/opt/homebrew /usr/local}; do
    echo "$HOMEBREW/$1"
  done
}

has_node() {
  command -v node >/dev/null 2>&1
}

use_node_directory() {
  [ -x "$1/node" ] || return 1
  PATH="$1:$PATH"
}

# Tries Homebrew, then nvm, fnm, Volta and asdf in turn, where a Mac's Node usually comes from, and stops at the first Node.
find_node() {
  for NODE_DIRECTORY in $(homebrew_paths bin); do
    if use_node_directory "$NODE_DIRECTORY"; then return; fi
  done
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  for NVM_SCRIPT in "$NVM_DIR/nvm.sh" $(homebrew_paths opt/nvm/nvm.sh); do
    if [ -s "$NVM_SCRIPT" ]; then
      export NVM_DIR
      . "$NVM_SCRIPT" --no-use
      nvm use >/dev/null 2>&1 || nvm use default >/dev/null 2>&1 || true
      if has_node; then return; fi
      break
    fi
  done
  for FNM in "$(command -v fnm || true)" "$HOME/.fnm/fnm" "$HOME/Library/Application Support/fnm/fnm" $(homebrew_paths bin/fnm); do
    if [ -x "$FNM" ]; then
      eval "$("$FNM" env --shell bash)"
      if has_node; then return; fi
      break
    fi
  done
  for NODE_DIRECTORY in "${VOLTA_HOME:-$HOME/.volta}/bin" "${ASDF_DATA_DIR:-$HOME/.asdf}/shims"; do
    if use_node_directory "$NODE_DIRECTORY"; then return; fi
  done
}

# TARGET_BUILD_DIR points at the real product, even for an archive or with CONFIGURATION_BUILD_DIR set on the command line.
# The resource file goes beside the public directory, never inside the bundle it hashes.
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
# The Capacitor Xcode project sits in ios/App, two levels below package.json and hotcodepush.json.
PROJECT_ROOT="${PROJECT_ROOT:-$PROJECT_DIR/../..}"

cd "$PROJECT_ROOT"

# A build started in Xcode has no Node on PATH, so .xcode.env can set NODE_BINARY and .xcode.env.local overrides it, as in React Native.
# Without either, the script searches Homebrew and the version managers.
NODE_BINARY=$(command -v node || true)
for XCODE_ENV_PATH in "$PROJECT_DIR/.xcode.env" "$PROJECT_DIR/.xcode.env.local"; do
  if [ -f "$XCODE_ENV_PATH" ]; then
    . "$XCODE_ENV_PATH"
  fi
done
if [ -z "$NODE_BINARY" ]; then
  find_node || true
  NODE_BINARY=$(command -v node || true)
fi
if [ -z "$NODE_BINARY" ]; then
  echo "error: HotCodePush found no Node to run its build step; name it in $PROJECT_DIR/.xcode.env: export NODE_BINARY=/path/to/node" >&2
  exit 1
fi
# npx sits beside Node.
PATH="$(dirname "$NODE_BINARY"):$PATH"
export PATH

# Only a store build creates the binary. A store build is an archive, the build that "Run script only when installing" means.
if [ "$DEPLOYMENT_POSTPROCESSING" = "YES" ]; then
  # The processed Info.plist holds the version and build that the device reports.
  # It has MARKETING_VERSION and CURRENT_PROJECT_VERSION expanded, and it keeps literal values as they are.
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
