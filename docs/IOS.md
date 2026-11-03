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
Regenerate after pulling changes that add or remove files, then reopen the project if the IDE still shows old sources.

## Layout and controls

Phone windows stack preview, transport, timeline and inline tools/panels. Landscape windows place tools beside
the preview. Text editing gives the preview the space above its controls; fullscreen hides editing controls. The desktop build uses its own workspace with a persistent media browser on the left,
a preview in the center, a contextual inspector on the right, and a timeline across the full window below them.
Desktop windows have a minimum size of 1000 × 640 points.

Tap the project name to rename it. The separate format summary underneath shows ratio, resolution and frame
rate; its triangle toggles the project format controls and clears clip selection. The preview has a gray surround,
a white canvas boundary and corner handles on the selected layer. An orange dashed outline and message identify
layers extending outside the output frame. Corner dragging scales around the layer's center; text supports double-tap editing.

The home grid keeps two compact cards across a phone and adds columns on larger windows. Covers stay within
their 16:10 thumbnail area. Project covers are saved with project data and use the first main clip's trimmed source
frame. Timeline filmstrips and waveform peaks are cached on disk; both timelines and the desktop media browser
use the same thumbnail service. Filmstrips fill coarse to fine with 10–120 frames per video. Reopening reads cached
images and peaks, generating only missing entries; the operating system can reclaim temporary media caches.

Desktop New project, Media, Add layer, Replace and Import offer Files and Photos as media sources.
Files opens the file selection interface; Photos opens the library browser. Audio uses file selection.
A seek bar sits directly below the desktop player. Pressing a timeline clip selects it without changing the playhead;
dragging moves it in stable timeline coordinates. Empty track space and the ruler seek independently.
The desktop browser supports searching, filtering by media type, thumbnail previews and file drops. Import adds
files to the project's media bin without changing its timeline. Double-click an asset to insert it at the playhead,
use its menu to add a layer or audio, or drag it onto a track at a chosen time. Empty drop lanes create layer and
audio tracks. Incompatible media is retained in the bin, with a message explaining the destination restriction.
Locked tracks reject edits and drops.

Drag the desktop dividers to resize the media browser, inspector and timeline. Panel sizes and visibility are
remembered across sessions. The Workspace menu toggles panels and resets the layout. The inspector follows
the selected clip and reuses the same controls as the phone and tablet versions. Clip actions, including Split
followed immediately by To new layer, appear beside Undo, Redo and Snap in the desktop timeline toolbar.
The same contextual tool list drives phone, tablet and desktop editing. Tools occupy one row and scroll horizontally
when the window cannot fit them; navigation, snapping and zoom stay available beside them.

The phone/tablet timeline uses a fixed center playhead: swipe to scrub and fling, hold a clip before dragging,
and drag its white handles to trim. It draws filmstrips, waveforms, keyframes and fades. Header taps mute
main/audio tracks or hide layers. The desktop timeline retains pointer controls and track mute/hide/lock actions. Desktop controls add a snapping toggle, track-height adjustment and Fit for
long projects. Playback follows the playhead horizontally. Drag clips onto compatible tracks to move them;
trim handles preserve the original source limits and gap behavior. Preview gestures still move, scale and rotate
a selected visual layer.

Desktop menus and shortcuts apply to the active editor window:

| Shortcut | Action |
|---|---|
| Command-I / Command-E | Import media / export project |
| Command-Z / Command-Shift-Z | Undo / redo; text entry retains its text undo history |
| Command-B / Command-D | Split / duplicate selected clip |
| Command-Shift-L / Command-Shift-T | Move selected clip to a layer / add text |
| Option-Q / Option-W | Trim selected clip's start / end to the playhead |
| Command-Option-1 / Command-Option-2 | Toggle media browser / inspector |
| Command-Plus / Command-Minus / Shift-Z | Zoom in / zoom out / fit timeline |

Click the desktop timeline or ruler to focus it. Space plays/pauses; left/right arrows step one frame; Shift-arrows
step ten frames; Option-arrows move to adjacent cuts; Command-arrows seek to the start/end. Delete removes the
selected clip and Escape clears selection. These timeline keys do not intercept typing in search or text fields.

Tap the version in Settings ten times to unlock local developer logs. Sharing logs uses the system share sheet.
The tools lock again when the version changes.

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
the app active for long exports. Projects remain editable after cancellation. The media browser has Library/Photos/Videos filters, Recent/Albums, sorting and ordered drag selection.
Photo access supports limited-library management. Audio selection and save/share flows use system interfaces.

## Validation status

Core timeline, sizing, persistence and subtitle tests run with `swift test --disable-xctest --package-path ios`.
Core tests also cover desktop media placement, locked tracks, zoom-aware snapping and cut navigation.
App tests exercise rendering, still-only export, media-bin persistence and undo, locked editing actions, and
frame-step boundaries. Persistence tests use temporary project directories.
Run them through the generated project's scheme or the debug build script.

Thirty-seven core tests cover editing and presentation geometry. App/model/rendering tests have been added for live
preview, replacement, defaults, filmstrip frames, cache reuse across fresh instances, corrupt-cache recovery, cover
invalidation and waveform persistence. The dedicated `FrameNovaInteractions` scheme covers gestures, media filters
and the format summary toggle.
Full app builds and device test execution remain pending on a machine with full Xcode; exact parity is unverified.
See [the alignment matrix](IOS_PARITY.md) for implemented behavior, regression coverage and remaining checks.

Before shipping, run the following checks on both a tablet simulator and an Apple silicon desktop build:

- Import ordered video/photo selections and audio files; reopen projects after terminating the app.
- Edit portrait and landscape projects with multiple visual, text and audio tracks. Resize the window through
  portrait/landscape layouts; check the desktop full-width timeline, panel resizing, pointer actions and shortcuts.
- Compare source trims, gaps, split boundaries, speed, keyframes, layouts, text, each filter and transition with
  the Android version, using the same media and timeline positions.
- Compare preview and exported frames at cuts and overlaps; check audio pitch, fades and synchronization.
- Export both codecs, every resolution and frame rate, still-only and audio-bearing timelines; cancel and retry.
- Check microphone and save permissions when granted and denied, media-picker cancellation, missing media,
  insufficient storage, background expiration and project deletion while another project references its assets.
