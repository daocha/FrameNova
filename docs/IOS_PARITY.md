# Editor behavior alignment

The Android editor defines timeline and editing behavior. The phone/tablet implementation now uses a native
single-surface timeline rather than nested scroll views competing for the same touch.

| Area | Implemented behavior | Regression coverage |
|---|---|---|
| Scrubbing | Fixed center playhead; swipe content in either direction, fling, clamp at project bounds, pinch zoom | Coordinate/scrub tests; swipe UI test |
| Moving clips | Hold a clip to pick it up, drag across compatible tracks or into a new layer, keep gaps, snap either edge | Placement/snapping tests; long-press UI test |
| Trimming | Selected white handles have separate hit targets; preserve source limits, opposite edge, gaps and transition overlap | Timeline tests; handle UI test |
| Timeline visuals | Source-time video/photo filmstrips, audio waveforms, clip labels, speed/mute/effect badges, keyframes and fade lines | Real-frame app test; device visual checks pending |
| Gaps and track headers | Tap a gap to select/delete it; header taps mute main/audio tracks or hide layers | Gap/placement tests |
| Preview | Hit-test actual layers, drag/pinch/rotate, snap centers/right angles, update visuals during one undoable gesture | Live-edit app tests; device gestures pending |
| Panels | Inline portrait panels; landscape side panels; text-focus layout; fullscreen preview | Layout UI test; rotation checks pending |
| Layout | Visual diagrams for every preset, active clip count, spacing, cropped cell placement | Shared layout math; device comparison pending |
| Media browser | Library/Photos/Videos, Recent/Albums, date/name sorting, ordered selection up to 50, clear and drag selection | Ordered-selection tests; filter UI test |
| Permissions/import | Full or limited photo access, manage-access action, original/current media copies, cloud download progress | Permission/device checks pending |
| Text | Separate edit/font/style/animation controls; bundled font groups and downloads; title/subtitle/sticker defaults | Defaults/animation tests |
| Looks | Filter swatches, intensity, brightness/contrast/HSL/warmth/tint, sharpen/vignette, cropped aspect presets | Color/animation tests; device pixel comparisons pending |
| Transitions | Alternating main layers, shared easing/slide/push/zoom math, dip color below overlays, apply to all | Transition core tests and compositing app tests |
| Replacement | Preserve source-range length and speed, bound video range, reset crop | Replacement app test |
| Voiceover | Play video with preview audio muted, record at the playhead, show elapsed time/level, insert recording on stop | Microphone/device checks pending |
| Export | Shared renderer with export snapshots isolated from live preview state; codec/size/fps/quality and audio mix | Export/rendering app tests; full device matrix pending |

Core regression tests run independently of the app. App tests and interaction tests require full Xcode and an
appropriate simulator/device. Source type checks do not establish gesture correctness, rendering performance,
or pixel equivalence. Exact parity remains unverified until the device checks above run successfully.

Generate the project, then run the dedicated interaction scheme on a phone and tablet simulator:

```bash
cd ios
xcodegen generate
xcodebuild test -project FrameNova.xcodeproj -scheme FrameNovaInteractions \
  -destination 'platform=iOS Simulator,id=<simulator-id>' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

The interaction scheme launches a debug-only fixture with a private temporary project store. It exercises a real
swipe, long-press move, trim-handle drag, layout panel, and media filter controls. It does not clear existing projects.
The normal app scheme retains rendering, export and model tests. Desktop keeps its dedicated workspace while
sharing the media browser, editing operations, inspector controls and render math.

Platform differences remain: audio files use the file selection interface, distribution/update installation follows
the platform, optional fonts use their native typefaces, and background export is limited by available execution time.
