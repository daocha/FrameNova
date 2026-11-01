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

Every video layer is padded to the end of the project. In the preview, a project whose only video layer is the main
track drops the clock: the main track leads the compositor and text is drawn after compositing (see below).

Positions, scale, rotation, opacity, keyframes and transitions are computed per frame from the current project
(`PlanCompositorSettings`), so dragging a layer or editing text updates the preview without rebuilding the pipeline.
Clips shown much smaller than their source are downscaled with a Lanczos filter on export.

### Timeline model

Clips keep their position. Main-track clips never overlap, except that a transition makes the incoming clip overlap the
previous one by its duration, and a transition exists only between touching clips. Trimming or moving leaves gaps;
inserting or extending pushes later clips only where they would overlap (`TimelineOps.normalized`).

### Preview player (Media3 1.9)

- A used `CompositionPlayer` keeps its video graph across `setComposition`, and a new composition on it can fail to
  start (or crash when the number of layers changes). Every rebuild gets a new player (`PreviewEngine`).
- The compositor needs two frames from each secondary input before it composites, so a secondary layer stalls briefly
  where it moves to its next clip. The leading (primary) input does not, hence the main-track-leads mode. The stall
  watchdog prepares the composition again if the picture stops.
- A layer that has ended and is then prepared at a later position makes the compositor throw, hence the padding.
- The multi-input video graph does not clear the compositor on a seek: old frames stay queued, so the player waits
  forever (or throws once a layer has ended). Every seek therefore prepares a new player at the target, at most every
  250 ms while dragging and once at the final position; play prepares one when the player is not at the playhead.
- Export: a layer declared with audio and video whose first clip has no sound makes the exporter add a silent track,
  which races with the other layers' setup (`SequenceAssetLoader` null consumer). Exports carry clip sound on separate
  audio-only layers instead.

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
1. Check preview behaviour on the S26 for projects with overlays (brief pauses where a layer changes clips).
2. Verify 4K60 HEVC preview and export performance on the device; tune the preview resolution if needed.
3. Clip animations (in/out) for video layers, masks and rounded corners for picture-in-picture.
4. Traditional Chinese UI translation.
