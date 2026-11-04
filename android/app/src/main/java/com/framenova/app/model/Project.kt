package com.framenova.app.model

import kotlinx.serialization.Serializable
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** All times are microseconds. Spatial values are normalized to the canvas unless stated otherwise. */

@Serializable
enum class AspectPreset(val w: Int, val h: Int, val label: String) {
    R16_9(16, 9, "16:9"), R9_16(9, 16, "9:16"), R1_1(1, 1, "1:1"), R4_5(4, 5, "4:5"),
    R4_3(4, 3, "4:3"), R3_4(3, 4, "3:4"), R21_9(21, 9, "21:9");

    val ratio: Float get() = w.toFloat() / h
}

/** Output quality tiers, named after the long side of a 16:9 frame. */
@Serializable
enum class ResolutionTier(val longSide: Int, val label: String) {
    HD(1280, "720p"), FHD(1920, "1080p"), QHD(2560, "2K"), UHD(3840, "4K");

    companion object {
        /** For pickers: highest first. */
        val highToLow: List<ResolutionTier> get() = entries.reversed()
    }
}

/** Frame rates offered for projects and exports, highest first. */
val FRAME_RATES = listOf(60, 50, 30, 25, 24)

@Serializable
enum class BackgroundMode { COLOR, BLUR }

@Serializable
data class Background(
    val mode: BackgroundMode = BackgroundMode.COLOR,
    val color: Long = 0xFF000000,
    /** 0..1, used when [mode] is BLUR. */
    val blur: Float = 0.6f,
)

@Serializable
data class CanvasSettings(
    val aspect: AspectPreset = AspectPreset.R16_9,
    val tier: ResolutionTier = ResolutionTier.UHD,
    val fps: Int = 30,
    val background: Background = Background(),
) {
    val size: PixelSize get() = sizeFor(aspect, tier.longSide)

    companion object {
        /** Fits [aspect] into a 16:9 box (or 9:16 for portrait) whose long side is [longSide]. Even dimensions. */
        fun sizeFor(aspect: AspectPreset, longSide: Int): PixelSize {
            val shortSide = longSide * 9 / 16
            val (boxW, boxH) = if (aspect.w >= aspect.h) longSide to shortSide else shortSide to longSide
            val r = aspect.ratio
            var w = boxW.toFloat()
            var h = w / r
            if (h > boxH) { h = boxH.toFloat(); w = h * r }
            return PixelSize(even(w), even(h))
        }

        private fun even(v: Float): Int = max(2, (v / 2f).roundToInt() * 2)
    }
}

@Serializable
data class PixelSize(val width: Int, val height: Int) {
    val aspect: Float get() = width.toFloat() / height
}

@Serializable
enum class MediaType { VIDEO, IMAGE, AUDIO }

@Serializable
data class MediaAsset(
    val id: String,
    val uri: String,
    val type: MediaType,
    val name: String,
    val durationUs: Long,
    /** Display size, rotation already applied. Zero for audio. */
    val width: Int = 0,
    val height: Int = 0,
    val hasAudio: Boolean = false,
    val hasVideo: Boolean = false,
    val isHdr: Boolean = false,
    val frameRate: Float = 0f,
)

@Serializable
enum class TrackKind { TEXT, OVERLAY, MAIN, AUDIO }

@Serializable
data class Track(
    val id: String,
    val kind: TrackKind,
    val clips: List<Clip> = emptyList(),
    val muted: Boolean = false,
    val hidden: Boolean = false,
    val locked: Boolean = false,
)

@Serializable
data class Transform(
    /** Center of the layer, 0..1 from the canvas' left/top. */
    val cx: Float = 0.5f,
    val cy: Float = 0.5f,
    /** 1 = the (cropped) layer fits the canvas. */
    val scale: Float = 1f,
    /** Degrees, clockwise. */
    val rotation: Float = 0f,
    val opacity: Float = 1f,
)

@Serializable
data class Keyframe(
    /** Offset from the clip's timeline start. */
    val offsetUs: Long,
    val transform: Transform,
    val easing: Easing = Easing.EASE_IN_OUT,
)

@Serializable
enum class Easing { LINEAR, EASE_IN_OUT }

/** Fractions of the source frame removed from each edge. */
@Serializable
data class CropRect(val left: Float = 0f, val top: Float = 0f, val right: Float = 0f, val bottom: Float = 0f) {
    val isFull: Boolean get() = left == 0f && top == 0f && right == 0f && bottom == 0f
    val widthFraction: Float get() = (1f - left - right).coerceAtLeast(0.01f)
    val heightFraction: Float get() = (1f - top - bottom).coerceAtLeast(0.01f)
}

@Serializable
data class Adjust(
    /** -1..1 */
    val brightness: Float = 0f,
    val contrast: Float = 0f,
    val saturation: Float = 0f,
    val warmth: Float = 0f,
    val tint: Float = 0f,
    /** Degrees, -180..180. */
    val hue: Float = 0f,
    /** 0..1 */
    val vignette: Float = 0f,
    val sharpen: Float = 0f,
) {
    val isNeutral: Boolean get() = this == Adjust()
}

@Serializable
data class FilterSetting(val id: String, val intensity: Float = 1f)

@Serializable
enum class TransitionType(val label: String) {
    FADE("Fade"), DIP_BLACK("Dip to black"), DIP_WHITE("Dip to white"),
    PUSH_LEFT("Push left"), PUSH_RIGHT("Push right"), PUSH_UP("Push up"), PUSH_DOWN("Push down"),
    SLIDE_LEFT("Slide left"), SLIDE_RIGHT("Slide right"), SLIDE_UP("Slide up"), SLIDE_DOWN("Slide down"),
    ZOOM_IN("Zoom in"), ZOOM_OUT("Zoom out"),
}

@Serializable
data class Transition(val type: TransitionType, val durationUs: Long = 500_000)

@Serializable
enum class TextAlign { LEFT, CENTER, RIGHT }

@Serializable
enum class TextAnim(val label: String) { NONE("None"), FADE("Fade"), SLIDE_UP("Slide up"), SLIDE_DOWN("Slide down"), POP("Pop"), TYPEWRITER("Typewriter"), ZOOM("Zoom") }

@Serializable
enum class TextRole { TITLE, SUBTITLE, STICKER }

@Serializable
data class TextStyle(
    val text: String = "Text",
    val fontId: String = "system",
    /** Text height as a fraction of the canvas height. */
    val size: Float = 0.07f,
    val color: Long = 0xFFFFFFFF,
    val bold: Boolean = true,
    val italic: Boolean = false,
    val align: TextAlign = TextAlign.CENTER,
    val strokeColor: Long = 0xFF000000,
    /** Fraction of the text size; 0 disables the outline. */
    val strokeWidth: Float = 0f,
    val shadow: Boolean = true,
    /** 0 disables the background box. */
    val backgroundColor: Long = 0,
    val letterSpacing: Float = 0f,
    val lineSpacing: Float = 1.1f,
    val animIn: TextAnim = TextAnim.NONE,
    val animOut: TextAnim = TextAnim.NONE,
    val animDurationUs: Long = 400_000,
    val role: TextRole = TextRole.TITLE,
)

@Serializable
data class Clip(
    val id: String,
    /** Null for text clips. */
    val assetId: String? = null,
    val startUs: Long,
    /** Source range. For images and text: 0..duration at speed 1. */
    val srcInUs: Long = 0,
    val srcOutUs: Long,
    val speed: Float = 1f,
    val volume: Float = 1f,
    val fadeInUs: Long = 0,
    val fadeOutUs: Long = 0,
    val transform: Transform = Transform(),
    val keyframes: List<Keyframe> = emptyList(),
    val crop: CropRect = CropRect(),
    val flipH: Boolean = false,
    val flipV: Boolean = false,
    val adjust: Adjust = Adjust(),
    val filter: FilterSetting? = null,
    /** Transition from the previous clip. Main track only. */
    val transitionIn: Transition? = null,
    val text: TextStyle? = null,
    /** Uses only the audio of a video asset (audio tracks). */
    val audioOnly: Boolean = false,
) {
    val durationUs: Long get() = ((srcOutUs - srcInUs) / speed.toDouble()).toLong()
    val endUs: Long get() = startUs + durationUs
    val isText: Boolean get() = text != null

    /** Maps a timeline time inside the clip to source media time. */
    fun sourceTimeAt(timelineUs: Long): Long =
        (srcInUs + ((timelineUs - startUs).coerceIn(0, durationUs) * speed.toDouble())).toLong()
            .coerceIn(srcInUs, srcOutUs)

    fun contains(timeUs: Long): Boolean = timeUs >= startUs && timeUs < endUs
}

@Serializable
data class Project(
    val id: String,
    val name: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val canvas: CanvasSettings = CanvasSettings(),
    val assets: List<MediaAsset> = emptyList(),
    /** Visual order, top to bottom: text tracks, overlays (top-most first), main, audio. */
    val tracks: List<Track> = listOf(Track(id = "main", kind = TrackKind.MAIN)),
    val coverAssetId: String? = null,
) {
    val durationUs: Long get() = tracks.maxOfOrNull { t -> t.clips.maxOfOrNull { it.endUs } ?: 0L } ?: 0L
    val mainTrack: Track get() = tracks.first { it.kind == TrackKind.MAIN }

    fun asset(id: String?): MediaAsset? = if (id == null) null else assets.firstOrNull { it.id == id }
    fun track(id: String): Track? = tracks.firstOrNull { it.id == id }
    fun trackOf(clipId: String): Track? = tracks.firstOrNull { t -> t.clips.any { it.id == clipId } }
    fun clip(clipId: String): Clip? = tracks.firstNotNullOfOrNull { t -> t.clips.firstOrNull { it.id == clipId } }
}

/** Interpolates a clip's transform at a timeline time, honoring keyframes. */
fun Clip.transformAt(timelineUs: Long): Transform {
    if (keyframes.isEmpty()) return transform
    val offset = timelineUs - startUs
    val sorted = keyframes.sortedBy { it.offsetUs }
    if (offset <= sorted.first().offsetUs) return sorted.first().transform
    if (offset >= sorted.last().offsetUs) return sorted.last().transform
    val nextIndex = sorted.indexOfFirst { it.offsetUs > offset }
    val a = sorted[nextIndex - 1]
    val b = sorted[nextIndex]
    var t = (offset - a.offsetUs).toFloat() / max(1L, b.offsetUs - a.offsetUs)
    if (b.easing == Easing.EASE_IN_OUT) t = t * t * (3 - 2 * t)
    return lerp(a.transform, b.transform, t)
}

fun lerp(a: Transform, b: Transform, t: Float): Transform = Transform(
    cx = a.cx + (b.cx - a.cx) * t,
    cy = a.cy + (b.cy - a.cy) * t,
    scale = a.scale + (b.scale - a.scale) * t,
    rotation = a.rotation + (b.rotation - a.rotation) * t,
    opacity = a.opacity + (b.opacity - a.opacity) * t,
)

fun clamp01(v: Float): Float = min(1f, max(0f, v))

/** Rejects changes to clips on tracks that were locked before an edit. */
fun Project.preservesLockedClips(next: Project): Boolean = tracks.filter { it.locked }.all { locked ->
    next.tracks.firstOrNull { it.id == locked.id }?.clips == locked.clips
}

/** Selection is shared by timeline, preview and inspector controls. */
fun Project.selectableClipId(clipId: String?): String? = clipId?.takeIf { trackOf(it)?.locked == false }
