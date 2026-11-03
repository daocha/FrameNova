#!/usr/bin/env bash
# Build FrameNova for a simulator, a device, or an Apple silicon desktop.
# Usage: scripts/build-ios-debug.sh [--skip-tests] [--device | --mac] [--run]
# Device builds require DEVELOPMENT_TEAM. SIMULATOR_ID selects a simulator.
# Requires full Xcode, XcodeGen, and Python 3. Installs no tools.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tests=1; platform=simulator; run=0
fail() { printf '%s\n' "$*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --skip-tests) tests=0 ;;
    --device) [ "$platform" = simulator ] || fail 'Choose only one platform.'; platform=device ;;
    --mac) [ "$platform" = simulator ] || fail 'Choose only one platform.'; platform=mac ;;
    --run) run=1 ;;
    --help|-h) sed -n '2,5p' "$0"; exit 0 ;;
    *) fail "Unknown option: $arg" ;;
  esac
done
[ "$(uname)" = Darwin ] || fail 'This build requires macOS.'
command -v xcodegen >/dev/null || fail 'XcodeGen is required. Make xcodegen available on PATH; this script installs nothing.'
xcodebuild -version >/dev/null 2>&1 || fail 'Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.'
command -v python3 >/dev/null || fail 'Python 3 is required.'
[ "$platform" != device ] || [ "$run" = 0 ] || fail 'Install device builds using Xcode.'
if [ "$tests" = 1 ]; then swift test --disable-xctest --package-path "$root/ios" --scratch-path "$root/ios/build/core-tests"; fi
(cd "$root/ios" && xcodegen generate)
extra=()
case "$platform" in
  device)
    [ -n "${DEVELOPMENT_TEAM:-}" ] || fail 'Set DEVELOPMENT_TEAM for device signing.'
    destination='generic/platform=iOS'
    extra=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    product=Debug-iphoneos ;;
  mac)
    destination='platform=macOS,variant=Mac Catalyst,arch=arm64'
    extra=(CODE_SIGNING_ALLOWED=NO)
    product=Debug-maccatalyst ;;
  simulator)
    destination='generic/platform=iOS Simulator'
    if [ "$run" = 1 ] || [ "$tests" = 1 ]; then
      if [ -z "${SIMULATOR_ID:-}" ]; then
        SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable")]; ds.sort(key=lambda d:(d.get("state")!="Booted", "iPad" not in d["name"])); print(ds[0]["udid"] if ds else "")')"
      fi
      [ -n "$SIMULATOR_ID" ] || fail 'No simulator available. Add an iOS runtime in Xcode.'
      destination="platform=iOS Simulator,id=$SIMULATOR_ID"
    fi
    extra=(CODE_SIGNING_ALLOWED=NO)
    product=Debug-iphonesimulator ;;
esac
if [ "$tests" = 1 ] && [ "$platform" != device ]; then
  xcodebuild test -project "$root/ios/FrameNova.xcodeproj" -scheme FrameNova -configuration Debug \
    -destination "$destination" -derivedDataPath "$root/ios/build" "${extra[@]}"
fi
xcodebuild build -project "$root/ios/FrameNova.xcodeproj" -scheme FrameNova -configuration Debug \
  -destination "$destination" -derivedDataPath "$root/ios/build" "${extra[@]}"
app="$root/ios/build/Build/Products/$product/FrameNova.app"
[ -d "$app" ] || fail 'Build finished without the expected app.'
mkdir -p "$root/dist"
output="$root/dist/FrameNova-$platform-debug.app"
if [ -e "$output" ]; then mv "$output" "$output.previous.$(date +%s)"; fi
cp -R "$app" "$output"
if [ "$run" = 1 ]; then
  if [ "$platform" = mac ]; then
    codesign --force --deep --sign - "$output"
    open "$output"
  else
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    xcrun simctl bootstatus "$SIMULATOR_ID" -b
    xcrun simctl install "$SIMULATOR_ID" "$output"
    xcrun simctl launch "$SIMULATOR_ID" com.framenova.app.debug
  fi
fi
printf '\nDebug app: %s\n' "$output"
