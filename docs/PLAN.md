# FrameNova — Plan and architecture

> v0.3 (2026-11-01). Android only, for editing on a Galaxy S26 Ultra (portrait and landscape). Non-commercial and
> source-available; every feature is free.

## Goals

- An easy multi-track editor that keeps 4K phone footage at full quality.
- Several clips in one frame, each laid out freely or with layout presets.
- Rich editing (text, filters, adjustments, keyframes, speed, audio) and basic transitions.
- Landscape editing on a large phone screen.
- No cloud, no account, no audio library. Updates over the LAN for development builds.

## Stack

Kotlin, Jetpack Compose (UI), AndroidX Media3 1.9 (`CompositionPlayer` for preview, `Transformer` for export, GPU
effects), kotlinx.serialization (projects as JSON). Built with Gradle from the command line.

## Architecture

```
ui/            Compose screens: home (projects), editor (preview, timeline, panels, export)
  editor/      EditorViewModel: project state, undo/redo, autosave, playback, all edit actions
model/         Pure Kotlin, unit-tested: Project, tracks, clips, timeline operations, layouts, subtitles
engine/        Media3 integration
  CompositionFactory   project -> Composition: one compositor input per layer
  PreviewEngine        CompositionPlayer; swaps per-frame state without rebuilding; stall watchdog
  ExportManager/Service  Transformer export in a foreground service, saved to MediaStore
  SpeedRenders         renders speed-changed clips on their own (see below)
  TextRenderer, Fonts, Filters (LUTs), DetailEffect (vignette/sharpen shader), MediaProbe, MediaCache
data/          ProjectRepository (atomic JSON saves, covers, stills), VoiceRecorder
update/        In-app updates: LAN (debug), GitHub releases (sideload), Google Play
```

### Compositing

Each layer is a Media3 sequence; the compositor draws input 0 on top and takes its frame rate and duration from it.

| Input | Content |
|---|---|
| 0 | Transparent "clock" image at output size and frame rate, carrying the text overlays |
| 1…n | Overlay tracks, top-most first |
| next | Dip-to-white / dip-to-black colour layers (only when used) |
| next | Main track: one layer, plus a second for clips that overlap the previous one through a transition |
| next | Blurred copies of the main track (blur background), then a background colour |
| last | Audio tracks |

Every video layer is padded to the end of the project.

Positions, scale, rotation, opacity, keyframes and transitions are computed per frame from the current project
(`PlanCompositorSettings`), so dragging a layer or editing text updates the preview without rebuilding the pipeline.
Clips shown much smaller than their source are downscaled with a Lanczos filter on export.

### Timeline model

Clips keep their position. Main-track clips never overlap, except that a transition makes the incoming clip overlap the
previous one by its duration, and a transition exists only between touching clips. Trimming or moving leaves gaps;
inserting or extending pushes later clips only where they would overlap (`TimelineOps.normalized`).

### Preview player (Media3 1.9)

Media3 1.9's preview player needed several workarounds, all in `PreviewEngine` and `CompositionFactory` (exports use
`Transformer` and are not affected unless noted):

- **Lower layers changing clips froze the picture.** The compositor waited for a second frame from every lower layer,
  while that layer could only move to its next clip once its last frame was consumed. `PreviewVideoCompositor` (a
  modified copy in `androidx.media3.effect`, used through `PreviewMultipleInputVideoGraph`) uses a single waiting frame.
- **A lower layer going from a still or an empty stretch to a video stayed blank for seconds:** the still renderer only
  counts as finished when the whole preview ends. In the preview, video clips and stills of a layer go on separate
  sequences, and empty stretches between video clips are filled with a tiny black video (`assets/preview_filler.mp4`).
- **Released players leaked** (CompositionTrackSelector never releases its DefaultTrackSelector, whose spatializer
  listener keeps the player reachable). `PreviewEngine.releasePlayer` removes that listener after releasing the player
  (releasing the selector before made the player, still preparing, fail on it).
- **Seeking and redrawing are unreliable** on the multi-input graph (old frames stay queued; `experimentalRedrawLastFrame`
  throws on the playback thread). A seek or paused edit prepares a new player at the position (edits at most every
  250 ms). While the timeline is dragged or a layer is moved on the preview, nothing is rebuilt: `PreviewPane` draws a
  quick composite from decoded stills (`MediaCache.scrubFrame`, only the latest request per clip is decoded), and the
  player is prepared once when the finger lifts.
- **A layer that ended and is prepared later makes the compositor throw**, so every video layer is padded to the end.
- A watchdog and an automatic re-prepare on player errors remain as a safety net.
- Export: a layer declared with audio and video whose first clip has no sound makes the exporter add a silent track,
  which races with other layers (`SequenceAssetLoader`); exports carry clip sound on separate audio-only layers.

### Filmstrips

`MediaCache.prepareFilmstrip` gives every video clip frames over its whole length (one per second, 10 to 120), taken
at keyframes and saved as JPEGs under `cache/filmstrip/`, so a reopened project shows them at once. Missing frames are
made in the background, coarse to fine (ten spread over the clip first). The timeline and the quick preview use the
nearest frame.

### Speed changes

In Media3 1.9 a speed change inside a multi-layer composition can stall the pipeline (`ExportBisectTest`). Speed-changed
clips are therefore rendered once, alone, at source resolution and a high bitrate, and compositions use the render at
normal speed. Export waits for pending renders; the preview uses the live effect until a render is ready.

### Quality

- Export renders from the original files at the chosen resolution (up to 4K), VBR at about 0.06/0.11/0.18 bits per
  pixel (HEVC 30% less).
- Text is rasterised at output resolution.
- HDR clips are tone-mapped to SDR (the compositor does not mix HDR and SDR inputs).

## Status

Done:
- Projects, timeline editing and all features listed in the README.
- Portrait and landscape layouts.
- Export, LAN/GitHub/Play updates, build and signing scripts.

Tests:
- Unit tests for the model and engine maths.
- Device tests for layer placement (pixel check), a full-feature export, preview playback and storage.

Next:
1. Check preview smoothness on the S26 with several 4K layers.
2. Verify 4K60 HEVC preview and export performance on the device; tune the preview resolution if needed.
3. Clip animations (in/out) for video layers, masks and rounded corners for picture-in-picture.
4. Traditional Chinese UI translation.
