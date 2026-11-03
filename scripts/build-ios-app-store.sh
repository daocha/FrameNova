#!/usr/bin/env bash
# Archive and export a signed release without uploading it.
# Usage: DEVELOPMENT_TEAM=<team> scripts/build-ios-app-store.sh [--skip-tests] [--mac]
# Requires full Xcode, Python 3, and an existing signing identity and provisioning profile.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tests=1; mac=0
fail() { printf '%s\n' "$*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --skip-tests) tests=0 ;;
    --mac) mac=1 ;;
    --help|-h) sed -n '2,4p' "$0"; exit 0 ;;
    *) fail "Unknown option: $arg" ;;
  esac
done
xcodebuild -version >/dev/null 2>&1 || fail 'Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.'
[[ "${DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]] || fail 'Set DEVELOPMENT_TEAM to the signing team ID.'
if [ "$tests" = 1 ]; then
  test_args=()
  if [ "$mac" = 1 ]; then test_args=(--mac); fi
  "$root/scripts/build-ios-debug.sh" "${test_args[@]}"
fi
python3 "$root/scripts/generate-ios-project.py"
platform=ios; destination='generic/platform=iOS'; method=app-store-connect
if [ "$mac" = 1 ]; then platform=mac; destination='generic/platform=macOS,variant=Mac Catalyst'; fi
output="$root/dist/FrameNova-$platform-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
xcodebuild archive -project "$root/ios/FrameNova.xcodeproj" -scheme FrameNova -configuration Release \
  -destination "$destination" -derivedDataPath "$root/ios/build/release-$platform" \
  -archivePath "$output/FrameNova.xcarchive" "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
python3 - "$output/ExportOptions.plist" "$DEVELOPMENT_TEAM" "$method" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(method=sys.argv[3], destination='export', teamID=sys.argv[2], signingStyle='automatic', manageAppVersionAndBuildNumber=False, uploadSymbols=True), f)
PY
xcodebuild -exportArchive -archivePath "$output/FrameNova.xcarchive" -exportOptionsPlist "$output/ExportOptions.plist" -exportPath "$output/export"
printf '\nRelease artifacts: %s\n' "$output"
