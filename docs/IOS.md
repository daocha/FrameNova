# FrameNova for iOS and desktop

The app sources live in `ios/FrameNova`. The minimum deployment versions are iOS 17 and macOS 14.
The desktop target uses Mac Catalyst and supports Apple silicon. Project generation uses `ios/project.yml`.
Version and build numbers are synchronized from the Android build settings into `ios/Config/Version.xcconfig`
by the generation hook.

## Build

Full Xcode with the required SDK and simulator runtime, XcodeGen, Python 3, and Swift 6 or newer are required.
The scripts install no software and do not change the selected developer directory. If necessary, export
`DEVELOPER_DIR` with the path to the installed developer directory before building.

```bash
scripts/build-ios-debug.sh                       # simulator app, core and rendering tests
scripts/build-ios-debug.sh --run                 # install and launch on an available simulator
scripts/build-ios-debug.sh --mac --run           # Apple silicon desktop app
DEVELOPMENT_TEAM=ABCDEFGHIJ scripts/build-ios-debug.sh --device
DEVELOPMENT_TEAM=ABCDEFGHIJ scripts/build-ios-app-store.sh
DEVELOPMENT_TEAM=ABCDEFGHIJ scripts/build-ios-app-store.sh --mac
```

`SIMULATOR_ID` selects a specific simulator. With `--run` or tests enabled, the default prefers an already booted
simulator, then a tablet simulator. `--skip-tests` skips core and app tests. Device installation uses the IDE.
Artifacts go in the gitignored `dist/` directory. Archives retain their debug symbols. Release scripts export
locally and never upload or submit a build. Signing credentials come from the environment and local signing
identities. Release provisioning profiles must already be available.

To generate and open the project manually:

```bash
cd ios
xcodegen generate
open FrameNova.xcodeproj
```

Both build scripts run `xcodegen generate` automatically. Make `xcodegen` available on `PATH` before running
them; they install no tools. Edit `ios/project.yml` to change targets, resources, build settings, or the shared
scheme. The app and rendering-test targets support both iOS and the desktop destination. Project generation
updates the version configuration automatically; it does not fetch dependencies or signing credentials.

## Layout and controls

Compact windows stack preview, transport, timeline and tools. At 900 points wide, the inspector appears beside
the editing area. Drag its divider to resize it; drag the timeline divider to adjust its height. Tablet and desktop
windows keep scrollable track controls aligned with their clips. Project cards use an adaptive grid.
Desktop windows have a minimum size of 720 × 520 points.

Select a timeline clip to reveal its tools. Drag clips horizontally to move them, or vertically onto a compatible
track. Drag the white handles to trim. Pinch to zoom the timeline, or use its zoom buttons. The ruler seeks the
preview. Drag, pinch and rotate a selected visual layer in the preview. Track controls mute, hide or lock tracks.

Tap the version in Settings ten times to unlock local developer logs. Sharing logs uses the system share sheet.
The tools lock again when the version changes.

Keyboard shortcuts: Space plays/pauses; Command-Z undoes; Command-Shift-Z redoes; Command-B splits;
Delete removes the selection; Command-E opens export. Context menus provide clip actions for pointer use.

## Media and rendering

Projects use microsecond timeline positions and atomic local persistence. Selected media is copied into the
app's private Application Support directory, so projects retain access after relaunch. Deleting a project only
removes imported copies that other projects do not reference. Original media is left untouched.

Preview and export share the composition and frame renderer, including layers, still images, timed text,
transforms, keyframes, crop, adjustments, the 16 filters, transitions and canvas backgrounds. Bundled fonts,
font license files and the timing video are shared repository resources. Optional fonts download only when
selected and are cached locally. Export offers H.264 or HEVC, resolution, frame rate, and bitrate quality.
The exported file can be shared or saved to the photo library. Microphone access is requested for voiceover.

The operating system limits background execution. An export cancels when its background time expires; keep
the app active for long exports. Projects remain editable after cancellation. The media picker and save/share
flows use system interfaces, so those interfaces follow the platform's behavior.

## Validation status

Core timeline, sizing, persistence and subtitle tests run with `swift test --disable-xctest --package-path ios`.
App tests exercise rendering without video sources and a still-only export, including its size and duration.
Run them through the generated project's scheme or the debug build script.

The app and rendering tests pass type checking for the Apple silicon desktop target, and all ten core tests
pass. The app has not been built or visually validated with full Xcode. Exact parity is not yet verified. In particular, the system media picker differs from the custom Android library, the update
installation flow follows platform distribution, and background export is subject to the platform limit described above.

Before shipping, run the following checks on both a tablet simulator and an Apple silicon desktop build:

- Import ordered video/photo selections and audio files; reopen projects after terminating the app.
- Edit portrait and landscape projects with multiple visual, text and audio tracks. Resize the window through
  the 900-point breakpoint; check track scrolling, inspector resizing, pointer actions and keyboard shortcuts.
- Compare source trims, gaps, split boundaries, speed, keyframes, layouts, text, each filter and transition with
  the Android version, using the same media and timeline positions.
- Compare preview and exported frames at cuts and overlaps; check audio pitch, fades and synchronization.
- Export both codecs, every resolution and frame rate, still-only and audio-bearing timelines; cancel and retry.
- Check microphone and save permissions when granted and denied, media-picker cancellation, missing media,
  insufficient storage, background expiration and project deletion while another project references its assets.
