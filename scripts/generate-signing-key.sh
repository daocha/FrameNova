#!/usr/bin/env bash
# Create the release signing key (asks first) and print its SHA-256 fingerprint. Does nothing if the key exists,
# except checking that its alias opens with the password.
# Usage: scripts/generate-signing-key.sh
# Keystore, alias and passwords: see _signing-common.sh (defaults in release-settings.sh).
set +x
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/_signing-common.sh"
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; "") ;; *) die "Unknown option: $1" ;; esac
find_toolchain
existed=0; [ ! -f "$keystore" ] || existed=1
ensure_keystore
trap forget_passwords EXIT
fingerprint="$(key_cert_sha256 | tr 'a-f' 'A-F' | sed 's/../&:/g; s/:$//')"
if [ "$existed" = 1 ]; then printf 'Signing key already exists: %s (alias %s)\n' "$keystore" "$alias_name"
else printf 'Signing key ready: %s (alias %s)\n' "$keystore" "$alias_name"; fi
printf 'SHA-256: %s\n' "$fingerprint"
