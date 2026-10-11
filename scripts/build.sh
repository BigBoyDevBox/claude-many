#!/usr/bin/env bash
# Verify Claude Replicant and assemble the native app.
# Usage: scripts/build.sh [--clean] [--run] [--install]
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT="$REPOSITORY_ROOT/claude-many.xcodeproj"
readonly SCHEME="claude-many"
readonly APP_NAME="Claude Replicant.app"
readonly APP_EXECUTABLE="claude-replicant"
readonly BUILD_DIR="$REPOSITORY_ROOT/build"
readonly APP_PATH="$BUILD_DIR/$APP_NAME"
readonly INSTALL_PATH="/Applications/$APP_NAME"

clean_requested=0
run_requested=0
install_requested=0

for argument in "$@"; do
  case "$argument" in
    --clean) clean_requested=1 ;;
    --run) run_requested=1 ;;
    --install) install_requested=1 ;;
    -h|--help) sed -n '2,3s/^# //p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Claude Replicant builds and tests on macOS only." >&2
  exit 1
fi

cd "$REPOSITORY_ROOT"

if ((clean_requested)); then
  rm -rf -- "$BUILD_DIR"
fi

# Unit tests cover the store and manager with an injected fake launcher. The
# live smoke test only runs when /tmp/claude-many-smoke-run exists, so a normal
# build never spawns real Claude Desktop instances.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR/DerivedData" test

xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" build

rm -rf -- "$APP_PATH"
ditto "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME" "$APP_PATH"

# The project signs ad hoc at build time; re-sign and verify to be certain.
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --strict "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE"
echo "$APP_PATH"

if ((install_requested)); then
  rm -rf -- "$INSTALL_PATH"
  ditto "$APP_PATH" "$INSTALL_PATH"
  open -R "$INSTALL_PATH" >/dev/null 2>&1 || true
fi

if ((run_requested)); then
  if ((install_requested)); then
    open "$INSTALL_PATH"
  else
    open "$APP_PATH"
  fi
fi
