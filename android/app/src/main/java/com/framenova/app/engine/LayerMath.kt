package com.framenova.app.engine

import com.framenova.app.model.Clip
import com.framenova.app.model.CropRect
import com.framenova.app.model.Project
import com.framenova.app.model.Track
import com.framenova.app.model.TrackKind
import com.framenova.app.model.Transform
import com.framenova.app.model.TransitionType
import com.framenova.app.model.transformAt
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** A layer's placement on the canvas, in canvas pixels. Rotation in degrees, clockwise. */
data class LayerGeometry(
    val centerX: Float,
    val centerY: Float,
    val width: Float,
    val height: Float,
    val rotation: Float,
    val opacity: Float,
) {
    /** Whether canvas point (x, y) falls inside the rotated rectangle. */
    fun contains(x: Float, y: Float): Boolean {
        val r = Math.toRadians(-rotation.toDouble())
        val dx = x - centerX
        val dy = y - centerY
        val lx = dx * cos(r) - dy * sin(r)
        val ly = dx * sin(r) + dy * cos(r)
        return abs(lx) <= width / 2 && abs(ly) <= height / 2
    }
}

/** Per-frame modifiers a transition applies on top of a layer's transform. Offsets in canvas fractions. */
data class LayerFx(val alpha: Float = 1f, val dx: Float = 0f, val dy: Float = 0f, val scale: Float = 1f) {
    companion object { val NONE = LayerFx() }
}

object LayerMath {
    /** Source display size after the crop. */
    fun croppedSize(srcW: Int, srcH: Int, crop: CropRect): Pair<Float, Float> =
        max(1f, srcW * crop.widthFraction) to max(1f, srcH * crop.heightFraction)

    /** Factor that makes a [w]×[h] frame fit the canvas (transform scale 1). */
    fun fitFactor(w: Float, h: Float, canvasW: Int, canvasH: Int): Float = min(canvasW / w, canvasH / h)

    /** Geometry of a visual clip on a [canvasW]×[canvasH] canvas. */
    fun geometry(srcW: Int, srcH: Int, crop: CropRect, t: Transform, canvasW: Int, canvasH: Int, fx: LayerFx = LayerFx.NONE): LayerGeometry {
        val (cw, ch) = croppedSize(srcW, srcH, crop)
        val s = fitFactor(cw, ch, canvasW, canvasH) * t.scale * fx.scale
        return LayerGeometry(
            centerX = (t.cx + fx.dx) * canvasW,
            centerY = (t.cy + fx.dy) * canvasH,
            width = cw * s,
            height = ch * s,
            rotation = t.rotation,
            opacity = (t.opacity * fx.alpha).coerceIn(0f, 1f),
        )
    }

    /** Geometry of an element whose rendered size is already known (text), centered at its transform. */
    fun sizedGeometry(width: Float, height: Float, t: Transform, canvasW: Int, canvasH: Int, fx: LayerFx = LayerFx.NONE): LayerGeometry =
        LayerGeometry((t.cx + fx.dx) * canvasW, (t.cy + fx.dy) * canvasH, width * fx.scale, height * fx.scale, t.rotation, (t.opacity * fx.alpha).coerceIn(0f, 1f))
}

object TransitionMath {
    /** Triangle that peaks at the transition's midpoint; the opacity of a dip-to-color layer. */
    fun dipAlpha(p: Float): Float = (1f - abs(2f * p - 1f)).coerceIn(0f, 1f)

    /**
     * Modifiers for the outgoing or incoming main-track clip at transition progress [p] (0..1). Layer order cannot change
     * per frame, so [incomingOnTop] tells which of the two is drawn above the other; every effect is built to look the
     * same either way (for example a fade raises the incoming clip when it is on top, else lowers the outgoing one).
     */
    fun fx(type: TransitionType, p: Float, incoming: Boolean, incomingOnTop: Boolean): LayerFx {
        val q = p.coerceIn(0f, 1f)
        val eased = q * q * (3 - 2 * q)
        val top = incoming == incomingOnTop
        return when (type) {
            TransitionType.FADE -> if (top) LayerFx(alpha = if (incoming) eased else 1 - eased) else LayerFx.NONE
            TransitionType.DIP_BLACK, TransitionType.DIP_WHITE ->
                LayerFx(alpha = if (incoming) (if (q >= 0.5f) 1f else 0f) else (if (q < 0.5f) 1f else 0f))
            TransitionType.PUSH_LEFT -> LayerFx(dx = if (incoming) 1 - eased else -eased)
            TransitionType.PUSH_RIGHT -> LayerFx(dx = if (incoming) eased - 1 else eased)
            TransitionType.PUSH_UP -> LayerFx(dy = if (incoming) 1 - eased else -eased)
            TransitionType.PUSH_DOWN -> LayerFx(dy = if (incoming) eased - 1 else eased)
            // Cover when the incoming clip is on top, else the outgoing one slides away and uncovers it.
            TransitionType.SLIDE_LEFT -> if (!top) LayerFx.NONE else if (incoming) LayerFx(dx = 1 - eased) else LayerFx(dx = -eased)
            TransitionType.SLIDE_RIGHT -> if (!top) LayerFx.NONE else if (incoming) LayerFx(dx = eased - 1) else LayerFx(dx = eased)
            TransitionType.SLIDE_UP -> if (!top) LayerFx.NONE else if (incoming) LayerFx(dy = 1 - eased) else LayerFx(dy = -eased)
            TransitionType.SLIDE_DOWN -> if (!top) LayerFx.NONE else if (incoming) LayerFx(dy = eased - 1) else LayerFx(dy = eased)
            TransitionType.ZOOM_IN -> {
                val scale = if (incoming) 0.6f + 0.4f * eased else 1f + 0.6f * eased
                LayerFx(alpha = if (top) (if (incoming) eased else 1 - eased) else 1f, scale = scale)
            }
            TransitionType.ZOOM_OUT -> {
                val scale = if (incoming) 1.6f - 0.6f * eased else 1f - 0.4f * eased
                LayerFx(alpha = if (top) (if (incoming) eased else 1 - eased) else 1f, scale = scale)
            }
        }
    }

    /**
     * Transition modifiers for main-track clip [clipIndex] at timeline [timeUs]. Clips sit on the upper or lower main
     * layer as [mainLayerGroups] assigns them.
     */
    fun mainClipFx(main: Track, clipIndex: Int, timeUs: Long): LayerFx {
        val clip = main.clips[clipIndex]
        clip.transitionIn?.let { tr ->
            if (clipIndex > 0 && timeUs < clip.startUs + tr.durationUs) {
                val p = (timeUs - clip.startUs).toFloat() / tr.durationUs
                return fx(tr.type, p, incoming = true, incomingOnTop = onUpperMainLayer(main.clips, clipIndex))
            }
        }
        val next = main.clips.getOrNull(clipIndex + 1)
        next?.transitionIn?.let { tr ->
            if (timeUs >= next.startUs) {
                val p = (timeUs - next.startUs).toFloat() / tr.durationUs
                return fx(tr.type, p, incoming = false, incomingOnTop = onUpperMainLayer(main.clips, clipIndex + 1))
            }
        }
        return LayerFx.NONE
    }

    /** Opacity of the dip-to-[type] color layer at [timeUs] (0 outside such transitions). */
    fun dipLayerAlpha(main: Track, type: TransitionType, timeUs: Long): Float {
        for (clip in main.clips) {
            val tr = clip.transitionIn ?: continue
            if (tr.type == type && timeUs >= clip.startUs && timeUs < clip.startUs + tr.durationUs) {
                return dipAlpha((timeUs - clip.startUs).toFloat() / tr.durationUs)
            }
        }
        return 0f
    }
}

/** Visual layers at a time, bottom to top, with their geometry. Used for hit testing and selection outlines. */
fun Project.visualGeometriesAt(timeUs: Long, canvasW: Int, canvasH: Int, textSize: (Clip) -> Pair<Float, Float>?): List<Pair<Clip, LayerGeometry>> {
    val result = mutableListOf<Pair<Clip, LayerGeometry>>()
    val ordered = tracks.filter { !it.hidden }.reversed() // bottom to top
    for (track in ordered) {
        if (track.kind == TrackKind.AUDIO) continue
        val index = track.clips.indexOfFirst { it.contains(timeUs) }
        if (index < 0) continue
        val clip = track.clips[index]
        val t = clip.transformAt(timeUs)
        if (track.kind == TrackKind.TEXT) {
            val (w, h) = textSize(clip) ?: continue
            result += clip to LayerMath.sizedGeometry(w, h, t, canvasW, canvasH)
        } else {
            val asset = asset(clip.assetId) ?: continue
            val fx = if (track.kind == TrackKind.MAIN) TransitionMath.mainClipFx(track, index, timeUs) else LayerFx.NONE
            result += clip to LayerMath.geometry(asset.width, asset.height, clip.crop, t, canvasW, canvasH, fx)
        }
    }
    return result
}

/**
 * Splits main-track clips (by index) into compositor layers. A clip stays on the previous clip's layer unless it overlaps
 * it through a transition, in which case it goes on the other layer. Without transitions everything is one layer.
 */
fun mainLayerGroups(clips: List<Clip>): List<Set<Int>> {
    // The first group is the upper layer (the compositor draws earlier inputs on top).
    val first = mutableSetOf<Int>()
    val second = mutableSetOf<Int>()
    var onFirst = true
    clips.forEachIndexed { i, c ->
        if (i > 0 && c.transitionIn != null) onFirst = !onFirst
        (if (onFirst) first else second) += i
    }
    return listOf(first, second).filter { it.isNotEmpty() }
}

/** Whether main-track clip [index] is on the upper of the two main layers (see [mainLayerGroups]). */
fun onUpperMainLayer(clips: List<Clip>, index: Int): Boolean = (1..index).count { clips[it].transitionIn != null } % 2 == 0
