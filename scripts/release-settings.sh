# FrameNova's settings for the Android build/release scripts (sourced by _signing-common.sh).

app_name=FrameNova
app_id=com.framenova.app
# Environment variables are named <env_prefix>_KEYSTORE, <env_prefix>_KEY_ALIAS and so on (see _signing-common.sh).
env_prefix=FRAMENOVA
default_keystore="$HOME/.framenova-signing/framenova-upload.jks"
default_key_alias=upload
default_lineage="$HOME/.framenova-signing/lineage.bin"
# Directories whose untracked files could end up in a release build.
build_dirs=(android scripts)
# The Play build must not update itself (Play policy). It keeps INTERNET for downloadable fonts.
play_forbidden_permissions=(android.permission.REQUEST_INSTALL_PACKAGES)

# Checks the sources before a build (--release: before a signed build). Nothing to fetch or check.
check_sources() { :; }

# Release notes for GitHub when --notes-file is not given. Arguments: version, versionCode, source commit.
default_release_notes() {
  cat <<NOTES
FrameNova $1 ($2): Android sideload APK (Android 10+). Verify the download against the SHA256SUMS file.

Source-available under the PolyForm Strict License 1.0.0. Your projects and media stay on your device.

Source commit: $3
NOTES
}
