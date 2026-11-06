# Platform rendering review

Base: `origin/main` at `314293c`.

The source review followed timeline gestures and drawing, clip timing and keyframes, preview layer geometry,
composition, thumbnail loading and text rasterization across Android, iOS/iPadOS and macOS.
It identified these reproducible code paths; this is not an exhaustive runtime certification.

| Finding | Targets | Fix | Regression coverage |
|---|---|---|---|
| Trimming a clip between animation keys discarded earlier keys, so the new start jumped to the next key. Trimming beyond the last key reverted to the base transform. | All three | Insert the evaluated pose at offset zero unless a key already exists there; retain later keys and the clip end. | Trim between, exactly on, and beyond keys; check the boundary pose, end time and remaining linear interpolation. |
| Filmstrip drawing walked all tiles from the clip start on every draw, including offscreen tiles. Work grew with duration and zoom. | Android | Calculate the intersecting tile indices directly, preserving the clip-relative tile alignment. | A heavily zoomed long clip visits 11 tiles in a 1080-pixel viewport; partial and offscreen cases. |
| Every text clip allocated and painted a canvas-sized bitmap on every frame, including frames with unchanged text appearance. | iOS/iPadOS, macOS | Reuse text rasters with a 32 MiB cache cost limit. Keys include style, resolved font, canvas size and visible character count; transforms remain outside the raster. | App regression for reuse across time and invalidation by color, resolution and typewriter progress. |

Validation on the review machine:

- Android: 54 unit tests, debug assembly and lint passed.
- Swift core: 50 tests passed, including the shared trim regression.
- Modified app renderer and rendering tests passed syntax parsing.
- Debug APK copied to `android/dist/FrameNova-debug.apk`; local update service checked.

Full app compilation, the new text-cache app regression, pixel rendering tests and gesture tests on iOS/iPadOS
and macOS remain unexecuted because full Xcode is unavailable. Syntax parsing does not establish type correctness.
No device frame-rate or playback latency measurement was made; the performance fixes remove identifiable repeated
work without claiming a measured speedup. Trimming a smoothed segment retains the boundary pose but can still
change the interpolation curve of the shortened segment, as the keyframe representation has no tangent controls.
