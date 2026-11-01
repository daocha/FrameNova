# FrameNova

A multi-track video editor for Android, built for editing 4K phone footage on the phone itself, in portrait or landscape.
Projects and media stay on the device. Source-available under the [PolyForm Strict License 1.0.0](LICENSE).

## Features

- **Timeline:** main track, overlay (picture-in-picture) tracks, text tracks, audio tracks. Clips stay where you put
  them: trimming or moving a clip leaves a gap instead of shifting the others (tap a gap to delete it), and adding
  or extending a clip pushes later clips only as far as needed. Long-press to drag clips anywhere, also between
  tracks; drag the white handles to trim; pinch to zoom; snapping to the playhead and clip edges.
- **Media library:** a built-in picker for videos and photos (Recent or by album, sorting, multi-select in order by
  tapping or by holding and dragging) and for audio (Recent or by folder). Files outside the media library can be
  added with **Files**.
- **Several clips in one frame:** drag, pinch and twist a layer directly on the preview (with centre and right-angle
  snapping), or arrange the clips at the playhead with a layout: side by side, top/bottom, grids, picture-in-picture.
- **Edits:** split, duplicate, delete, replace, freeze frame, speed (0.25–4×, pitch kept), volume and fades, crop,
  flip, keyframes for position/scale/rotation/opacity.
- **Look:** 16 colour filters with intensity, adjustments (brightness, contrast, saturation, warmth, tint, hue,
  sharpen, vignette), canvas background colour or blur.
- **Transitions:** fade, dip to black/white, push and slide in four directions, zoom in/out.
- **Text:** styles (colour, outline, shadow, background box, spacing), in/out animations, emoji stickers, subtitles and
  lyrics from SRT/LRC files. English fonts are bundled; Traditional Chinese fonts (Noto Sans/Serif TC, Chiron Hei/Sung
  HK, LXGW WenKai TC, Iansui, Huninn) download once on demand.
- **Audio:** music and sound from files, audio extracted from video clips, voiceover recording, saving a clip's audio
  as an `.m4a` file.
- **Export:** 720p to 4K, 24–60 fps, HEVC or H.264, three quality levels, in the background with a notification.
  Saved to `Movies/FrameNova`.

## Building

Android project in `android/`: Kotlin, Jetpack Compose, AndroidX Media3. JDK 17 and the Android SDK (platform 36,
build-tools 36) are needed; no Android Studio.

```bash
scripts/build-android-debug.sh            # debug APK in dist/, with unit tests and lint
scripts/build-android-debug.sh --install  # and install it with adb
```

Or directly: `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug` in `android/`. Engine tests that run
on a device or emulator: `./gradlew :app:connectedDebugAndroidTest`.

## Updating over the local network

Debug builds can update themselves from your computer:

1. Create `.env` at the repository root (it is gitignored):
   ```
   FRAMENOVA_DEV_UPDATE_HOST=192.168.1.20   # your computer's address on the Wi-Fi
   FRAMENOVA_DEV_UPDATE_PORT=8767           # optional
   ```
2. Build the debug APK and install it once (USB / adb). Every debug build made with the host set writes
   `android/dist/dev-update/` (APK, `SHA256SUMS`, `latest.json`).
3. Run `scripts/serve-dev-update.sh` and leave it running. It serves that folder on your LAN address only.
4. After each new build, the app shows **Update** (home screen banner, or Settings > Check for updates). Downloads are
   verified against the checksum and the package, and Android installs them only if the signing key matches.

## Releases and signing

| Script | Purpose |
|---|---|
| `scripts/generate-signing-key.sh` | Create the release key (`~/.framenova-signing/framenova-upload.jks`) and print its SHA-256 |
| `scripts/build-android-release.sh` | Signed, verified sideload APK + `SHA256SUMS` in `dist/` |
| `scripts/build-android-play.sh` | Signed Google Play bundle (no self-update permission) |
| `scripts/release-github.sh` | Tag and publish the APK to GitHub Releases (`--dry-run` to only build) |
| `scripts/print-signing-fingerprint.sh` | Show the key fingerprint (for Play App Signing) |
| `scripts/rotate-signing-key.sh` | Let installs signed with an older key update in place |

Signing settings come only from the environment (`FRAMENOVA_KEYSTORE`, `FRAMENOVA_KEY_ALIAS`, `FRAMENOVA_KEYSTORE_PASSWORD`,
`FRAMENOVA_KEY_PASSWORD`); passwords are asked for when unset. Release APKs update from GitHub Releases; Play builds
update through Google Play.

## Known issue

When a project has picture-in-picture clips, dip transitions or a blurred background, the live preview can pause its
picture for about a second where one of those layers moves to its next clip, then continues on its own. Projects with
only the main track (plus text and audio) play through cuts and gaps smoothly. Exports are not affected.

## Licences

FrameNova: PolyForm Strict License 1.0.0. AndroidX Media3, Jetpack Compose and Kotlin libraries: Apache License 2.0.
Fonts: SIL Open Font License 1.1, licence texts in `third_party/fonts/`.
