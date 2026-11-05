# Working in this repository

FrameNova is a multi-track video editor for Android (`android/`), built with Kotlin, Jetpack Compose and AndroidX
Media3. It is source-available under the PolyForm Strict License 1.0.0 (`LICENSE`).

## Branches and pull requests

Never commit to `main` (the default branch). Make every change on a branch and open a pull request for it; leave
merging to the maintainer. Commit or push only when the user asks for it.

## Rules for content

- Do not mention other apps or products by name anywhere in this repository: code, comments, docs, commit messages
  and pull requests.
- Never write the LAN update address from `.env`, or the secret in `~/.android/framenova-dev-update-secret`, into a
  committed file, commit message or pull request.
- Logs the user shares from the developer tools go in `debug/` (gitignored); never commit them.

## Building and testing

- `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug` in `android/`; all three must pass.
- Engine tests run on a device or emulator: `./gradlew :app:connectedDebugAndroidTest`. Run them after any change
  to `engine/` (preview, composition, export). The task uninstalls the app afterwards, which deletes its projects.
- The preview works around several Media3 1.9 problems (`docs/PLAN.md`, "Preview player"), including two modified
  Media3 files in `android/app/src/main/java/androidx/media3/effect/`. Read that section before changing
  `PreviewEngine`, `CompositionFactory` or those files, and keep the Apache 2.0 notices in them.
- Icons are generated from `art/FrameNova-appicon.png` by `python3 scripts/make-icons.py` (needs Pillow and numpy).

## Building the debug APK on the maintainer's Mac

Do not use `scripts/` to build it (`build-android-debug.sh`, `setup-release-env.sh` and the like use Homebrew and
install software). Install nothing: no Homebrew, no system JDK, no Android Studio, nothing under `~/Library`. Run
Gradle directly with a portable toolchain kept in one folder under `/tmp`, shared with the maintainer's other
Android projects:

```bash
T=/private/tmp/aquarestore-tools
export JAVA_HOME=$(echo $T/jdk-17*/Contents/Home) ANDROID_HOME=$T/android-sdk GRADLE_USER_HOME=$T/gradle-home
cd android && ./gradlew --console=plain :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

`/tmp` is cleared on reboot. If `$T` is missing, recreate it there and nowhere else:
- JDK 17: the Temurin tarball from
  `https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse`, extracted into `$T`.
- Android SDK: the macOS "command line tools only" zip from developer.android.com/studio, extracted to
  `$ANDROID_HOME/cmdline-tools/latest`, then
  `yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses` and
  `sdkmanager --sdk_root=$ANDROID_HOME 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'`.
- Gradle: the wrapper downloads it into `$GRADLE_USER_HOME` by itself. A half-wiped Gradle cache fails with
  "Could not read workspace metadata": delete `$GRADLE_USER_HOME/caches` and build again.

For device tests and UI checks, use an emulator AVD of your own in `$T/avd` (this project uses `framenova` on port
5560); other sessions may be using other AVDs, so leave those alone.

Do not set `ANDROID_USER_HOME`: the APK must be signed with `~/.android/debug.keystore`, the key the phone's
installed debug build has. The debug package is `com.framenova.app.debug`.

After a successful build, copy the APK to `android/dist/FrameNova-debug.apk`. When the gitignored `.env` sets
`FRAMENOVA_DEV_UPDATE_HOST` (see `.env.example`), the build has already written `android/dist/dev-update/`. Run
`scripts/serve-dev-update.sh`: it starts the server in the background and returns, and does nothing if one is already
running, because a running server picks up the new build by itself.

## Releases

Releases come from `scripts/release-github.sh`, and Play bundles from `scripts/build-android-play.sh`. Release
signing comes only from the environment (`scripts/generate-signing-key.sh` creates the key); never commit a
keystore, password or signing config. Project-specific release settings live in `scripts/release-settings.sh`.
