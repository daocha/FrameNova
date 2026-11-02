package com.framenova.app.engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.DefaultGainProvider
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Brightness
import androidx.media3.effect.Contrast
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.HslAdjustment
import androidx.media3.effect.LanczosResample
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbAdjustment
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.SingleColorLut
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import com.framenova.app.model.BackgroundMode
import com.framenova.app.model.CanvasSettings
import com.framenova.app.model.Clip
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import com.framenova.app.model.PixelSize
import com.framenova.app.model.Project
import com.framenova.app.model.Track
import com.framenova.app.model.TrackKind
import com.framenova.app.model.TransitionType
import com.framenova.app.model.transformAt
import java.io.File
import java.io.FileOutputStream
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.roundToInt

enum class PlanMode { PREVIEW, EXPORT }

/** Fast lookups into the project snapshot the renderer reads every frame. Swapped without rebuilding the pipeline. */
class HotState(val project: Project) {
    val clips: Map<String, Clip> = project.tracks.flatMap { it.clips }.associateBy { it.id }
    val tracks: Map<String, Track> = project.tracks.associateBy { it.id }
    val main: Track = project.mainTrack
}

enum class SolidRole { BACKGROUND, DIP_BLACK, DIP_WHITE }
enum class VideoRole { OVERLAY, MAIN, BLUR }

sealed interface LayerSpec
data class ClockLayer(val width: Int, val height: Int) : LayerSpec
data class SolidLayer(val role: SolidRole) : LayerSpec
data class VideoLayer(val trackId: String, val role: VideoRole, val clips: List<LayerClip>) : LayerSpec

/** A clip inside a compositor layer, with the size of the frames that reach the compositor. */
data class LayerClip(val clipId: String, val startUs: Long, val endUs: Long, val deliveredW: Int, val deliveredH: Int, val mainIndex: Int = -1)

class RenderPlan(
    val outW: Int,
    val outH: Int,
    val fps: Int,
    val layers: List<LayerSpec>,
    val textTrackIds: List<String>,
    val key: String,
)

class PlanHolder(plan: RenderPlan, hot: HotState) {
    @Volatile var plan: RenderPlan = plan
    @Volatile var hot: HotState = hot
}

private const val SOLID_SIZE = 16

/** A tiny black video (assets) that fills empty stretches of video layers in the preview, and its length. */
private const val FILLER_URI = "asset:///preview_filler.mp4"
private const val FILLER_US = 120_000_000L

@UnstableApi
object CompositionFactory {
    fun outputSize(canvas: CanvasSettings, mode: PlanMode, exportLongSide: Int? = null): PixelSize = when (mode) {
        PlanMode.PREVIEW -> CanvasSettings.sizeFor(canvas.aspect, minOf(canvas.tier.longSide, 1920))
        PlanMode.EXPORT -> CanvasSettings.sizeFor(canvas.aspect, exportLongSide ?: canvas.tier.longSide)
    }

    /**
     * Everything that requires rebuilding the Media3 pipeline. Transforms, opacity, keyframes and text are read per frame
     * from [HotState] instead, so dragging a layer or editing text updates the preview instantly.
     */
    fun structureKey(project: Project, mode: PlanMode, out: PixelSize, fps: Int): String {
        val sb = StringBuilder()
        sb.append(mode).append(out).append(fps).append(project.canvas.background.mode).append(project.canvas.background.color)
            .append(project.canvas.background.blur)
        for (t in project.tracks) {
            sb.append('|').append(t.id).append(t.kind).append(t.muted)
            if (t.kind == TrackKind.TEXT) continue
            for (c in t.clips) {
                sb.append(';').append(c.id).append(c.assetId).append(c.startUs).append(c.srcInUs).append(c.srcOutUs).append(c.speed)
                    .append(c.volume).append(c.fadeInUs).append(c.fadeOutUs).append(c.crop).append(c.flipH).append(c.flipV)
                    .append(c.adjust).append(c.filter).append(c.audioOnly).append(c.transitionIn)
                if (mode == PlanMode.EXPORT) sb.append(prescaleBucket(project, c, out))
            }
        }
        return sb.toString()
    }

    /** The project with every speed-changed clip that has a finished render replaced by that render at normal speed. */
    fun resolve(context: Context, model: Project): Project {
        val added = mutableListOf<MediaAsset>()
        val tracks = model.tracks.map { t ->
            if (t.kind != TrackKind.MAIN && t.kind != TrackKind.OVERLAY) t
            else t.copy(clips = t.clips.map { c ->
                val asset = model.asset(c.assetId)
                if (asset == null) c else SpeedRenders.substitute(context, c, asset)?.let { (clip, a) -> added += a; clip } ?: c
            })
        }
        return if (added.isEmpty()) model else model.copy(tracks = tracks, assets = model.assets + added)
    }

    fun build(context: Context, model: Project, mode: PlanMode, exportLongSide: Int? = null, fps: Int = model.canvas.fps): Pair<Composition, PlanHolder> {
        val project = resolve(context, model)
        val out = outputSize(project.canvas, mode, exportLongSide)
        val key = structureKey(project, mode, out, fps)
        val duration = project.durationUs
        val layers = mutableListOf<LayerSpec>()
        val sequences = mutableListOf<EditedMediaItemSequence>()
        val anyHdr = project.assets.any { it.isHdr }
        val hot = HotState(model)
        val textTracks = project.tracks.filter { it.kind == TrackKind.TEXT && it.clips.isNotEmpty() }.reversed().map { it.id }
        // Built before the holder exists; the overlays read the holder lazily.
        lateinit var holder: PlanHolder

        val textOverlays: List<TextureOverlay> = textTracks.map { id -> TextTrackOverlay(id) { holder } }
        // Export carries the sound of video clips on separate audio-only layers (see clipAudioSequence).
        val separateAudio = mode == PlanMode.EXPORT
        val clipAudio = mutableListOf<EditedMediaItemSequence>()
        // 0: clock. The compositor's primary input sets the output frame rate and duration; it is drawn on top and
        // carries the text. Always output-sized: the pipeline takes its frame size from the inputs, and text is
        // drawn onto this frame.
        val clockSize = out
        val clockUri = solidImage(context, 0x00000000, clockSize.width, clockSize.height)
        val clockEffects = if (textOverlays.isEmpty()) Effects.EMPTY else Effects(emptyList(), listOf<Effect>(OverlayEffect(textOverlays)))
        sequences += EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
            .addItem(stillItem(clockUri, duration, fps, clockEffects))
            .build()
        layers += ClockLayer(clockSize.width, clockSize.height)

        // Overlay tracks, top-most first.
        for (track in project.tracks.filter { it.kind == TrackKind.OVERLAY && it.clips.isNotEmpty() }) {
            val clips = track.clips.mapNotNull { c -> project.asset(c.assetId)?.let { c to it } }
            if (clips.isEmpty()) continue
            for (part in previewParts(mode, clips)) {
                sequences += videoSequence(context, project, track, part, mode, out, fps, withAudio = !separateAudio)
                layers += VideoLayer(track.id, VideoRole.OVERLAY, part.map { (c, a) -> layerClip(project, c, a, mode, out) })
            }
            if (separateAudio) clipAudioSequence(project, track, clips, mode, out)?.let { clipAudio += it }
        }

        val main = project.mainTrack
        val transitionTypes = main.clips.mapNotNull { it.transitionIn?.type }.toSet()
        if (TransitionType.DIP_WHITE in transitionTypes) {
            sequences += solidSequence(context, 0xFFFFFFFF.toInt(), duration, fps); layers += SolidLayer(SolidRole.DIP_WHITE)
        }
        if (TransitionType.DIP_BLACK in transitionTypes) {
            sequences += solidSequence(context, 0xFF000000.toInt(), duration, fps); layers += SolidLayer(SolidRole.DIP_BLACK)
        }

        // Main track: one layer, plus a second only for clips that overlap the previous one through a transition. Cuts
        // and gaps stay within a layer, which plays them seamlessly (a layer that starts with a gap can keep the preview
        // from starting in Media3 1.9).
        val indexed = main.clips.mapIndexedNotNull { i, c -> project.asset(c.assetId)?.let { Triple(i, c, it) } }
        val mainGroups = mainLayerGroups(main.clips).map { group -> indexed.filter { it.first in group } }.filter { it.isNotEmpty() }
        for (group in mainGroups) {
            val pairs = group.map { it.second to it.third }
            val indexOf = group.associate { (i, c, _) -> c.id to i }
            for (part in previewParts(mode, pairs)) {
                sequences += videoSequence(context, project, main, part, mode, out, fps, withAudio = !separateAudio)
                layers += VideoLayer(main.id, VideoRole.MAIN, part.map { (c, a) -> layerClip(project, c, a, mode, out).copy(mainIndex = indexOf.getValue(c.id)) })
            }
            if (separateAudio) clipAudioSequence(project, main, pairs, mode, out)?.let { clipAudio += it }
        }
        if (project.canvas.background.mode == BackgroundMode.BLUR) {
            for (group in mainGroups) {
                val blurW = max(2, out.width / 4 / 2 * 2)
                val blurH = max(2, out.height / 4 / 2 * 2)
                val indexOf = group.associate { (i, c, _) -> c.id to i }
                for (part in previewParts(mode, group.map { it.second to it.third })) {
                    sequences += blurSequence(context, project, part, blurW, blurH, fps, mode)
                    layers += VideoLayer(main.id, VideoRole.BLUR, part.map { (c, _) -> LayerClip(c.id, c.startUs, c.endUs, blurW, blurH, indexOf.getValue(c.id)) })
                }
            }
        }
        val bgColor = project.canvas.background.color.toInt()
        if (project.canvas.background.mode == BackgroundMode.COLOR && bgColor != Color.BLACK) {
            sequences += solidSequence(context, bgColor, duration, fps); layers += SolidLayer(SolidRole.BACKGROUND)
        }

        // Audio tracks come last so video inputs keep their indices.
        sequences += clipAudio
        for (track in project.tracks.filter { it.kind == TrackKind.AUDIO && it.clips.isNotEmpty() }) {
            val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
            var cursor = 0L
            var added = 0
            for (clip in track.clips) {
                val asset = project.asset(clip.assetId) ?: continue
                if (clip.startUs > cursor) builder.addGap(clip.startUs - cursor)
                builder.addItem(avItem(clip, asset, mode, out, removeVideo = true, removeAudio = false, gain = if (track.muted) 0f else clip.volume))
                cursor = clip.endUs
                added++
            }
            if (added > 0) sequences += builder.build()
        }

        val plan = RenderPlan(out.width, out.height, fps, layers, textTracks, key)
        holder = PlanHolder(plan, hot)
        val composition = Composition.Builder(sequences)
            .setVideoCompositorSettings(PlanCompositorSettings(holder))
            .setHdrMode(if (anyHdr) Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL else Composition.HDR_MODE_KEEP_HDR)
            .build()
        return composition to holder
    }

    // -----------------------------------------------------------------------------------------------------------
    // Sequences and items

    private fun videoSequence(
        context: Context, project: Project, track: Track, clips: List<Pair<Clip, MediaAsset>>, mode: PlanMode, out: PixelSize, fps: Int, withAudio: Boolean,
    ): EditedMediaItemSequence {
        val hasAudio = withAudio && clips.any { (c, a) -> a.type == MediaType.VIDEO && a.hasAudio && c.volume > 0f } && !track.muted
        val types = if (hasAudio) setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO) else setOf(C.TRACK_TYPE_VIDEO)
        val builder = EditedMediaItemSequence.Builder(types)
        val videoFill = fillsWithVideo(mode, clips)
        var cursor = 0L
        for ((clip, asset) in clips) {
            if (clip.startUs > cursor) addGap(builder, clip.startUs - cursor, videoFill)
            val gain = if (track.muted) 0f else clip.volume
            val (fadeIn, fadeOut) = audioFades(project, track, clip)
            builder.addItem(
                if (asset.type == MediaType.IMAGE) stillItem(Uri.parse(asset.uri), clip.durationUs, fps, Effects(emptyList(), videoEffects(project, clip, asset, mode, out)))
                else avItem(clip, asset, mode, out, removeVideo = false, removeAudio = !hasAudio || !asset.hasAudio || gain == 0f, gain = gain, fadeInUs = fadeIn, fadeOutUs = fadeOut, project = project)
            )
            cursor = clip.endUs
        }
        padToEnd(builder, cursor, project.durationUs, videoFill)
        return builder.build()
    }

    /**
     * In the preview, a layer's video clips and stills go on separate sequences. Media3 1.9's preview player can only
     * move a lower layer from a still (or an empty stretch, which it fills with still frames) to a video once the whole
     * preview has ended, so such a layer would stay blank for seconds. Kept apart, and with empty stretches between video
     * clips filled with a tiny black video ([addGap]), every layer only switches between items of one kind. The parts
     * never overlap in time, so their order does not matter. Exports are not affected.
     */
    private fun previewParts(mode: PlanMode, clips: List<Pair<Clip, MediaAsset>>): List<List<Pair<Clip, MediaAsset>>> =
        if (mode != PlanMode.PREVIEW) listOf(clips)
        else clips.partition { it.second.type == MediaType.VIDEO }.toList().filter { it.isNotEmpty() }

    private fun fillsWithVideo(mode: PlanMode, clips: List<Pair<Clip, MediaAsset>>): Boolean =
        mode == PlanMode.PREVIEW && clips.all { it.second.type == MediaType.VIDEO }

    /** An empty stretch: a gap, or (see [previewParts]) the filler video, hidden by the compositor settings. */
    private fun addGap(builder: EditedMediaItemSequence.Builder, durationUs: Long, videoFill: Boolean) {
        if (!videoFill) { builder.addGap(durationUs); return }
        var left = durationUs
        while (left > 0) {
            val part = minOf(left, FILLER_US)
            val item = MediaItem.Builder().setUri(FILLER_URI).setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder().setEndPositionUs(part).build()
            ).build()
            builder.addItem(EditedMediaItem.Builder(item).setDurationUs(FILLER_US).setRemoveAudio(true).build())
            left -= part
        }
    }

    /** Fade-in and fade-out of a clip's sound; on the main track the sound crossfades under video transitions. */
    private fun audioFades(project: Project, track: Track, clip: Clip): Pair<Long, Long> {
        var fadeIn = clip.fadeInUs
        var fadeOut = clip.fadeOutUs
        if (track.kind == TrackKind.MAIN) {
            val main = project.mainTrack
            val i = main.clips.indexOfFirst { it.id == clip.id }
            clip.transitionIn?.let { fadeIn = max(fadeIn, it.durationUs) }
            main.clips.getOrNull(i + 1)?.transitionIn?.let { fadeOut = max(fadeOut, it.durationUs) }
        }
        return fadeIn to fadeOut
    }

    /**
     * The sound of a visual layer's video clips as an audio-only layer, or null when nothing is audible. Used for export:
     * a layer carrying both audio and video whose first clip has no sound makes Media3 1.9's exporter add a silent track,
     * which races with the other layers' setup and can fail the export.
     */
    private fun clipAudioSequence(project: Project, track: Track, clips: List<Pair<Clip, MediaAsset>>, mode: PlanMode, out: PixelSize): EditedMediaItemSequence? {
        if (track.muted) return null
        val audible = { c: Clip, a: MediaAsset -> a.type == MediaType.VIDEO && a.hasAudio && c.volume > 0f }
        if (clips.none { (c, a) -> audible(c, a) }) return null
        val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
        var cursor = 0L
        for ((clip, asset) in clips) {
            if (clip.startUs > cursor) builder.addGap(clip.startUs - cursor)
            if (audible(clip, asset)) {
                val (fadeIn, fadeOut) = audioFades(project, track, clip)
                builder.addItem(avItem(clip, asset, mode, out, removeVideo = true, removeAudio = false, gain = clip.volume, fadeInUs = fadeIn, fadeOutUs = fadeOut))
            } else builder.addGap(clip.durationUs)
            cursor = clip.endUs
        }
        return builder.build()
    }

    /**
     * Fills a layer to the end of the project. Media3 1.9 fails when a layer that has already ended is prepared at a
     * later position (the compositor rejects its frame), so no video layer ends early.
     */
    private fun padToEnd(builder: EditedMediaItemSequence.Builder, cursor: Long, durationUs: Long, videoFill: Boolean = false) {
        if (durationUs - cursor >= 1_000) addGap(builder, durationUs - cursor, videoFill)
    }

    private fun blurSequence(context: Context, project: Project, clips: List<Pair<Clip, MediaAsset>>, w: Int, h: Int, fps: Int, mode: PlanMode): EditedMediaItemSequence {
        val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
        val sigma = 4f + 26f * project.canvas.background.blur
        val effects = listOf<Effect>(
            Presentation.createForWidthAndHeight(w, h, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP),
            GaussianBlur(sigma / 4f),
        )
        val videoFill = fillsWithVideo(mode, clips)
        var cursor = 0L
        for ((clip, asset) in clips) {
            if (clip.startUs > cursor) addGap(builder, clip.startUs - cursor, videoFill)
            val item = when {
                asset.type == MediaType.IMAGE -> stillItem(Uri.parse(asset.uri), clip.durationUs, fps, Effects(emptyList(), effects))
                // A speed change not yet rendered (preview only): leave the backdrop empty, since a second video copy of a
                // speed-changed clip can stall Media3 1.9 (ExportBisectTest). Rendered clips arrive here at normal speed.
                clip.speed != 1f -> null
                else -> EditedMediaItem.Builder(videoMediaItem(clip, asset)).setDurationUs(asset.durationUs).setRemoveAudio(true)
                    .setEffects(Effects(emptyList(), effects)).build()
            }
            if (item != null) builder.addItem(item) else addGap(builder, clip.durationUs, videoFill)
            cursor = clip.endUs
        }
        padToEnd(builder, cursor, project.durationUs, videoFill)
        return builder.build()
    }

    private fun solidSequence(context: Context, argb: Int, durationUs: Long, fps: Int): EditedMediaItemSequence =
        EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
            .addItem(stillItem(solidImage(context, argb, SOLID_SIZE, SOLID_SIZE), durationUs, fps, Effects.EMPTY))
            .build()

    private fun stillItem(uri: Uri, durationUs: Long, fps: Int, effects: Effects): EditedMediaItem {
        val item = MediaItem.Builder().setUri(uri).setImageDurationMs(max(1L, (durationUs + 500) / 1000)).build()
        return EditedMediaItem.Builder(item).setDurationUs(durationUs).setFrameRate(fps).setEffects(effects).build()
    }

    private fun videoMediaItem(clip: Clip, asset: MediaAsset): MediaItem = MediaItem.Builder()
        .setUri(Uri.parse(asset.uri))
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder().setStartPositionUs(clip.srcInUs).setEndPositionUs(clip.srcOutUs).build()
        ).build()

    private fun avItem(
        clip: Clip, asset: MediaAsset, mode: PlanMode, out: PixelSize, removeVideo: Boolean, removeAudio: Boolean, gain: Float,
        fadeInUs: Long = clip.fadeInUs, fadeOutUs: Long = clip.fadeOutUs, project: Project? = null,
    ): EditedMediaItem {
        val audio = mutableListOf<AudioProcessor>()
        val video = mutableListOf<Effect>()
        speedEffects(clip.speed)?.let { (a, v) -> audio += a; video += v }
        if (!removeAudio) {
            val dur = clip.durationUs
            val provider = DefaultGainProvider.Builder(gain.coerceIn(0f, 4f))
            if (fadeInUs > 0) provider.addFadeAt(0, minOf(fadeInUs, dur), DefaultGainProvider.FADE_IN_LINEAR)
            if (fadeOutUs > 0) provider.addFadeAt(max(0L, dur - fadeOutUs), minOf(fadeOutUs, dur), DefaultGainProvider.FADE_OUT_LINEAR)
            audio += GainProcessor(provider.build())
        }
        if (!removeVideo && project != null) video += videoEffects(project, clip, asset, mode, out)
        return EditedMediaItem.Builder(videoMediaItem(clip, asset))
            .setDurationUs(asset.durationUs)
            .setRemoveVideo(removeVideo || !asset.hasVideo)
            .setRemoveAudio(removeAudio || !asset.hasAudio)
            .setEffects(Effects(audio, video))
            .build()
    }

    /**
     * Speed change as the first audio processor and video effect. EditedMediaItem.setSpeed() stalls multi-sequence
     * exports in Media3 1.9 (see ExportBisectTest), so the paired effect is used for both preview and export.
     */
    @Suppress("DEPRECATION")
    private fun speedEffects(speed: Float): Pair<AudioProcessor, Effect>? =
        if (speed == 1f) null else Effects.createExperimentalSpeedChangingEffect(ConstantSpeed(speed)).let { it.first to it.second }

    /** Per-clip picture effects, in order: flip, crop, color, filter, detail, then a high-quality downscale (export). */
    private fun videoEffects(project: Project, clip: Clip, asset: MediaAsset, mode: PlanMode, out: PixelSize): List<Effect> {
        val list = mutableListOf<Effect>()
        if (clip.flipH || clip.flipV) {
            list += ScaleAndRotateTransformation.Builder().setScale(if (clip.flipH) -1f else 1f, if (clip.flipV) -1f else 1f).build()
        }
        val crop = clip.crop
        if (!crop.isFull) list += Crop(-1f + 2f * crop.left, 1f - 2f * crop.right, -1f + 2f * crop.bottom, 1f - 2f * crop.top)
        val a = clip.adjust
        if (a.brightness != 0f) list += Brightness((a.brightness * 0.5f).coerceIn(-1f, 1f))
        if (a.contrast != 0f) list += Contrast((a.contrast * 0.7f).coerceIn(-1f, 1f))
        if (a.saturation != 0f || a.hue != 0f) {
            list += HslAdjustment.Builder().adjustSaturation(a.saturation * 100f).adjustHue(a.hue).build()
        }
        if (a.warmth != 0f || a.tint != 0f) {
            list += RgbAdjustment.Builder()
                .setRedScale(1f + 0.12f * a.warmth)
                .setBlueScale(1f - 0.12f * a.warmth)
                .setGreenScale(1f - 0.10f * a.tint)
                .build()
        }
        Filters.byId(clip.filter?.id)?.let { def ->
            list += SingleColorLut.createFromCube(Filters.cube(def, clip.filter?.intensity ?: 1f))
        }
        if (a.vignette > 0f || a.sharpen > 0f) list += DetailEffect(a.vignette, a.sharpen)
        if (mode == PlanMode.EXPORT) {
            val bucket = prescaleBucket(project, clip, out)
            if (bucket < 1f) {
                val (cw, ch) = LayerMath.croppedSize(asset.width, asset.height, clip.crop)
                list += LanczosResample.scaleToFit(max(2, (cw * bucket).roundToInt()), max(2, (ch * bucket).roundToInt()))
            }
        }
        return list
    }

    /** Frame size reaching the compositor for a clip; mirrors [videoEffects]. */
    private fun layerClip(project: Project, clip: Clip, asset: MediaAsset, mode: PlanMode, out: PixelSize): LayerClip {
        var (w, h) = LayerMath.croppedSize(asset.width, asset.height, clip.crop)
        if (mode == PlanMode.EXPORT) {
            val bucket = prescaleBucket(project, clip, out)
            if (bucket < 1f) { w = max(2f, (w * bucket).roundToInt().toFloat()); h = max(2f, (h * bucket).roundToInt().toFloat()) }
        }
        return LayerClip(clip.id, clip.startUs, clip.endUs, w.roundToInt().coerceAtLeast(1), h.roundToInt().coerceAtLeast(1))
    }

    /**
     * When a clip is shown much smaller than its source (picture-in-picture, grids), it is downscaled first with a Lanczos
     * filter for a sharp, alias-free result. Buckets of powers of two keep the pipeline stable while resizing.
     */
    fun prescaleBucket(project: Project, clip: Clip, out: PixelSize): Float {
        val asset = project.asset(clip.assetId) ?: return 1f
        if (asset.type == MediaType.AUDIO || clip.audioOnly) return 1f
        val (cw, ch) = LayerMath.croppedSize(asset.width, asset.height, clip.crop)
        val maxScale = (clip.keyframes.map { it.transform.scale } + clip.transform.scale).max()
        val ratio = LayerMath.fitFactor(cw, ch, out.width, out.height) * maxScale
        if (ratio >= 0.5f) return 1f
        val steps = floor(ln(1.0 / ratio) / ln(2.0)).toInt().coerceIn(1, 4)
        return 1f / (1 shl steps)
    }

    /** A solid (or transparent) PNG in the cache, reused across builds. */
    fun solidImage(context: Context, argb: Int, w: Int, h: Int): Uri {
        val dir = File(context.cacheDir, "render").apply { mkdirs() }
        val file = File(dir, "solid_%08x_%dx%d.png".format(argb, w, h))
        if (!file.isFile) {
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply { eraseColor(argb) }
            val tmp = File(dir, file.name + ".tmp")
            FileOutputStream(tmp).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            tmp.renameTo(file)
            bmp.recycle()
        }
        return Uri.fromFile(file)
    }
}

@UnstableApi
private class ConstantSpeed(private val speed: Float) : SpeedProvider {
    override fun getSpeed(timeUs: Long): Float = speed
    override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
}

private val HIDDEN: OverlaySettings = StaticOverlaySettings.Builder().setAlphaScale(0f).setScale(0.001f, 0.001f).build()

/** Places every compositor input each frame from the current [PlanHolder]. */
@UnstableApi
private class PlanCompositorSettings(private val holder: PlanHolder) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: List<Size>): Size = holder.plan.let { Size(it.outW, it.outH) }

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val plan = holder.plan
        val hot = holder.hot
        val t = presentationTimeUs
        return when (val layer = plan.layers.getOrNull(inputId) ?: return HIDDEN) {
            is ClockLayer -> if (plan.textTrackIds.isEmpty()) HIDDEN else StaticOverlaySettings.Builder()
                .setScale(plan.outW.toFloat() / layer.width, plan.outH.toFloat() / layer.height).build()
            is SolidLayer -> {
                val alpha = when (layer.role) {
                    SolidRole.BACKGROUND -> 1f
                    SolidRole.DIP_BLACK -> TransitionMath.dipLayerAlpha(hot.main, TransitionType.DIP_BLACK, t)
                    SolidRole.DIP_WHITE -> TransitionMath.dipLayerAlpha(hot.main, TransitionType.DIP_WHITE, t)
                }
                if (alpha <= 0f) HIDDEN else StaticOverlaySettings.Builder()
                    .setScale(plan.outW.toFloat() / SOLID_SIZE, plan.outH.toFloat() / SOLID_SIZE).setAlphaScale(alpha).build()
            }
            is VideoLayer -> videoSettings(plan, hot, layer, t)
        }
    }

    private fun videoSettings(plan: RenderPlan, hot: HotState, layer: VideoLayer, t: Long): OverlaySettings {
        val lc = layer.clips.firstOrNull { t >= it.startUs && t < it.endUs } ?: return HIDDEN
        val track = hot.tracks[layer.trackId] ?: return HIDDEN
        if (track.hidden) return HIDDEN
        val clip = hot.clips[lc.clipId] ?: return HIDDEN
        val asset = hot.project.asset(clip.assetId) ?: return HIDDEN
        val mainIndex = hot.main.clips.indexOfFirst { it.id == clip.id }
        val fx = if (layer.role != VideoRole.OVERLAY && mainIndex >= 0) TransitionMath.mainClipFx(hot.main, mainIndex, t) else LayerFx.NONE
        if (layer.role == VideoRole.BLUR) {
            if (fx.alpha <= 0f) return HIDDEN
            return StaticOverlaySettings.Builder()
                .setScale(plan.outW.toFloat() / lc.deliveredW, plan.outH.toFloat() / lc.deliveredH)
                .setAlphaScale(fx.alpha).build()
        }
        val g = LayerMath.geometry(asset.width, asset.height, clip.crop, clip.transformAt(t), plan.outW, plan.outH, fx)
        if (g.opacity <= 0f) return HIDDEN
        return StaticOverlaySettings.Builder()
            .setScale(g.width / lc.deliveredW, g.height / lc.deliveredH)
            .setBackgroundFrameAnchor(g.centerX / plan.outW * 2f - 1f, 1f - g.centerY / plan.outH * 2f)
            .setRotationDegrees(-g.rotation)
            .setAlphaScale(g.opacity)
            .build()
    }
}

/** Draws the active clip of one text track. Bitmaps are rendered at output resolution and cached until they change. */
@UnstableApi
private class TextTrackOverlay(private val trackId: String, private val holderRef: () -> PlanHolder) : BitmapOverlay() {
    private val empty: Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    private var cachedKey: Any? = null
    private var cachedBitmap: Bitmap = empty

    private fun active(t: Long): Clip? {
        val hot = holderRef().hot
        val track = hot.tracks[trackId] ?: return null
        if (track.hidden) return null
        return track.clips.firstOrNull { it.isText && it.contains(t) }
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val clip = active(presentationTimeUs) ?: return empty
        val style = clip.text ?: return empty
        val plan = holderRef().plan
        val anim = TextAnimations.at(style, presentationTimeUs - clip.startUs, clip.durationUs)
        val scale = clip.transformAt(presentationTimeUs).scale
        val chars = if (anim.visibleFraction < 1f) (style.text.length * anim.visibleFraction).toInt() else -1
        val key = listOf(style, scale, plan.outW, plan.outH, chars)
        if (key != cachedKey) {
            cachedBitmap = TextRenderer.render(style, scale, plan.outW, plan.outH, chars)
            cachedKey = key
        }
        return cachedBitmap
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val clip = active(presentationTimeUs) ?: return HIDDEN
        val style = clip.text ?: return HIDDEN
        val tr = clip.transformAt(presentationTimeUs)
        val anim = TextAnimations.at(style, presentationTimeUs - clip.startUs, clip.durationUs)
        val alpha = tr.opacity * anim.alpha
        if (alpha <= 0f) return HIDDEN
        return StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(tr.cx * 2f - 1f, 1f - (tr.cy + anim.dy) * 2f)
            .setScale(anim.scale, anim.scale)
            .setRotationDegrees(-tr.rotation)
            .setAlphaScale(alpha)
            .build()
    }
}
