<div align="center">
  <img src="art/FrameNova-banner.png" width="100%" alt="FrameNova, a cross-platform video editor for iOS, Android and macOS">
  <h1>FrameNova</h1>
  <p><strong>One timeline. Room for every layer.</strong></p>
  <p>A multi-track video editor for Android, iPhone, iPad, and macOS.<br>Edit on your device, from the first cut to the final frame.</p>
  <p>
    <a href="#features">Features</a> ·
    <a href="#build-and-run">Build &amp; run</a> ·
    <a href="docs/IOS.md">iOS &amp; macOS guide</a> ·
    <a href="#development">Development</a> ·
    <a href="LICENSE">License</a>
  </p>
  <p><strong>Up to 4K</strong> &nbsp; / &nbsp; <strong>Multi-track editing</strong> &nbsp; / &nbsp; <strong>Local projects</strong></p>

[![License: PolyForm Strict](https://img.shields.io/badge/license-PolyForm%20Strict%201.0.0-blue)](LICENSE)
[![Android CI](https://img.shields.io/github/actions/workflow/status/daocha/FrameNova/android.yml?branch=main&label=Android%20CI&logo=githubactions&logoColor=white)](https://github.com/daocha/FrameNova/actions/workflows/android.yml)
[![Kotlin](https://img.shields.io/badge/Kotlin-Jetpack%20Compose-7F52FF?logo=kotlin&logoColor=white)](android)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)](ios)
[![Android](https://img.shields.io/badge/Android-10%2B-3DDC84?logo=android&logoColor=white)](android)
[![iOS](https://img.shields.io/badge/iOS-16%2B-000000?logo=apple&logoColor=white)](docs/IOS.md)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](docs/IOS.md)
[![Last commit](https://img.shields.io/github/last-commit/daocha/FrameNova/main)](https://github.com/daocha/FrameNova/commits/main)
[![Repo size](https://img.shields.io/github/repo-size/daocha/FrameNova)](https://github.com/daocha/FrameNova)

</div>

---

Arrange video, photos, text, and sound on a flexible timeline. Edit directly on the preview, build layered compositions,
and keep your projects and imported media on your device. Phone and tablet layouts adapt to portrait and landscape;
the Apple silicon desktop workspace adds a media browser, inspector, and keyboard controls.

FrameNova is source-available under the [PolyForm Strict License 1.0.0](LICENSE).

## Features

| | What you can do |
| :--- | :--- |
| **Timeline** | Combine a main track with video layers, text, and audio tracks. Split, trim, move, duplicate, replace, and freeze clips. Zoom and snap to the playhead or clip edges. |
| **Layers & layouts** | Move, scale, and rotate layers on the preview. Arrange clips side by side, in grids, or as picture-in-picture. Animate position, scale, rotation, and opacity with keyframes. |
| **Color & style** | Apply 16 filters with adjustable intensity. Tune brightness, contrast, saturation, warmth, tint, hue, sharpening, and vignette. Choose a solid or blurred canvas background. |
| **Transitions** | Connect clips with fades, dips to black or white, directional pushes and slides, and zooms. |
| **Text & subtitles** | Style titles with outlines, shadows, backgrounds, spacing, and in/out animations. Add emoji stickers or import subtitles and lyrics from SRT/LRC files. |
| **Sound & speed** | Add music, extract audio from video, record voiceovers, and save a clip's audio as `.m4a`. Adjust volume and see fades in the waveform. Change speed from 0.25–4× while preserving pitch. |
| **Media library** | Browse videos and photos by recent items or album, sort, and select multiple items in order. Import audio and other media through file selection. |
| **Export** | Choose 720p to 4K, 24–60 fps, H.264 or HEVC, and three quality levels. |

**Your timeline stays under your control.** Trimming or moving a clip leaves a gap instead of shifting everything else.
Delete a gap when you want to close it; inserting or extending a clip pushes later clips only as far as needed.

<details>
<summary><strong>Fonts and typography</strong></summary>

English and display fonts are bundled, with comic, neon, retro pixel, script, slab, western, and stencil styles.
Traditional Chinese fonts download once on demand and are cached locally. Font licenses and notices are included
in [`third_party/fonts/`](third_party/fonts/).

</details>

## Build and run

| Target | Requirements | Guide |
| :--- | :--- | :--- |
| Android | Android 10+ device; JDK 17 and Android SDK platform 36 / build-tools 36 to build | [Android source](android/) |
| iPhone & iPad | iOS / iPadOS 17+; full Xcode, XcodeGen, Python 3, and Swift 6+ to build | [Build and validation guide](docs/IOS.md) |
| macOS | Apple silicon, macOS 14+; the same Apple build tools | [Desktop workspace and shortcuts](docs/IOS.md#layout-and-controls) |

### Android

With `JAVA_HOME` and `ANDROID_HOME` pointing to your existing toolchain:

```bash
cd android
./gradlew --console=plain :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

The debug APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`.
The implementation uses Kotlin, Jetpack Compose, and AndroidX Media3.

### iPhone, iPad & macOS

```bash
scripts/build-ios-debug.sh --run        # Build and launch in a simulator
scripts/build-ios-debug.sh --mac --run  # Build and launch on Apple silicon
```

The build scripts install no tools. Set `DEVELOPER_DIR` if needed to select your existing full Xcode installation.
See the [iOS and desktop guide](docs/IOS.md) for setup, platform differences, and validation status;
full app builds and device validation remain pending on a machine with full Xcode.

**Export destinations:** Android exports go to `Movies/FrameNova` and can run in the background with a notification.
iOS and desktop exports can be shared or saved to the photo library; keep the app active for long exports.

## Development

### Checks

```bash
# Android unit tests, debug build, and lint
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
```

Run engine tests on a device or emulator after preview, composition, or export changes:

```bash
# From android/ — uninstalls the app afterwards, deleting its projects
./gradlew :app:connectedDebugAndroidTest
```

```bash
# From the repository root — Swift core tests
swift test --disable-xctest --package-path ios
```

Apple app and rendering tests run through the generated project's scheme or the debug build script.
See the [platform alignment matrix](docs/IOS_PARITY.md) for coverage and remaining checks.

<details>
<summary><strong>Update Android debug builds over your local network</strong></summary>

1. Copy [`.env.example`](.env.example) to `.env` at the repository root; `.env` is gitignored.
   Set `FRAMENOVA_DEV_UPDATE_HOST` to your computer's local network address. The optional
   `FRAMENOVA_DEV_UPDATE_PORT` defaults to `8767`.
2. Build the debug APK and install it once over USB. Builds with the host set also write an APK,
   `SHA256SUMS`, and `latest.json` to `android/dist/dev-update/`.
3. Run `scripts/serve-dev-update.sh`. It starts in the background and binds to the configured local address.
   A running server picks up new builds automatically. Use `--status`, `--stop`, or `--foreground` as needed.
4. After a new build, use **Update** on the home screen or **Settings → Check for updates**.
   Downloads are checked against the checksum and package; installation requires a matching signing key.

Files are served under a secret path embedded in the debug build. The secret is created once at
`~/.android/framenova-dev-update-secret` and persists across builds and clones. Keep it private;
if it is lost, install a new debug build manually once.

For a debug build installed before the secret existed, run `scripts/serve-dev-update.sh --migrate` once,
let the phone update, then run the plain command again. No reinstall is needed. The plain command also stops
older update servers for this repository that have no secret path.

</details>

<details>
<summary><strong>Release builds and signing</strong></summary>

| Script | Purpose |
| :--- | :--- |
| `scripts/generate-signing-key.sh` | Create the release key and print its SHA-256 fingerprint |
| `scripts/build-android-release.sh` | Build a signed, verified sideload APK and checksums in `dist/` |
| `scripts/build-android-play.sh` | Build a signed store bundle without self-update permission |
| `scripts/release-github.sh` | Tag and publish the Android APK; use `--dry-run` to build without publishing |
| `scripts/print-signing-fingerprint.sh` | Show the signing key fingerprint |
| `scripts/rotate-signing-key.sh` | Allow installations signed with an older key to update in place |
| `scripts/build-ios-app-store.sh` | Archive and export an Apple release build with environment-provided signing |

Android signing comes from `FRAMENOVA_KEYSTORE`, `FRAMENOVA_KEY_ALIAS`, `FRAMENOVA_KEYSTORE_PASSWORD`, and
`FRAMENOVA_KEY_PASSWORD`. Passwords are prompted for when unset; the default key location is
`~/.framenova-signing/framenova-upload.jks`. Never commit keys or credentials.

Sideload release APKs update from repository releases; store builds update through their store.
See the [iOS and desktop guide](docs/IOS.md) for Apple signing and archive instructions.

</details>

### Report a problem

Tap the version in **Settings** ten times to unlock the developer tools. **Developer logs** shows recent app logs,
media-library warnings and errors, and the last crash, with options to copy, share, or save. On Android, saved logs
are written to `Download/FrameNova/logs/`. Nothing leaves the device unless you share it.
The tools lock again after the next update or when you turn them off.

## License and acknowledgments

FrameNova is source-available under the [PolyForm Strict License 1.0.0](LICENSE).

- **Libraries:** AndroidX Media3, Jetpack Compose, and Kotlin libraries use Apache License 2.0.
- **Preview patches:** two modified Media3 files in [`androidx/media3/effect/`](android/app/src/main/java/androidx/media3/effect/)
  retain their Apache License 2.0 notices and document the changes.
- **Fonts:** SIL Open Font License 1.1; license texts are included in [`third_party/fonts/`](third_party/fonts/).
