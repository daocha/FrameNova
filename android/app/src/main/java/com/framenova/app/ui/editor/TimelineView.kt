package com.framenova.app.ui.editor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.framenova.app.engine.MediaCache
import com.framenova.app.model.Clip
import com.framenova.app.model.ClipCategory
import com.framenova.app.model.MediaType
import com.framenova.app.model.Project
import com.framenova.app.model.Track
import com.framenova.app.model.TrackKind
import com.framenova.app.model.accepts
import com.framenova.app.model.categoryOf
import com.framenova.app.model.mainGapAt
import com.framenova.app.model.touches
import com.framenova.app.ui.theme.Palette
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

private data class Row(val track: Track, val top: Float, val height: Float)

private sealed interface Hit {
    data class Body(val clip: Clip, val track: Track) : Hit
    data class Handle(val clip: Clip, val track: Track, val start: Boolean) : Hit
    data class TransitionButton(val clipId: String) : Hit
    data class TrackHeader(val track: Track) : Hit
    data class Gap(val timeUs: Long) : Hit
    data object Empty : Hit
}

private data class DragState(val clip: Clip, val track: Track, val dx: Float, val dy: Float, val fingerY: Float)
private data class TrimState(val clip: Clip, val start: Boolean, val dx: Float)

fun formatTime(us: Long, withFrames: Boolean = false, fps: Int = 30): String {
    val totalMs = max(0L, us) / 1000
    val m = totalMs / 60_000
    val s = totalMs / 1000 % 60
    return if (withFrames) "%02d:%02d.%02d".format(m, s, (totalMs % 1000) * fps / 1000) else "%02d:%02d".format(m, s)
}

@Composable
fun TimelineView(
    project: Project,
    playheadUs: Long,
    pxPerSecond: Float,
    selectedId: String?,
    selectedGapUs: Long?,
    media: MediaCache,
    onScrub: (Long, Boolean) -> Unit,
    onZoom: (Float) -> Unit,
    onSelect: (String?) -> Unit,
    onGapTap: (Long?) -> Unit,
    onMove: (clipId: String, trackId: String, startUs: Long, newTrack: Boolean) -> Unit,
    onTrim: (clipId: String, start: Boolean, deltaUs: Long) -> Unit,
    onTransitionTap: (clipId: String) -> Unit,
    onTrackHeaderTap: (Track) -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val viewConfig = LocalViewConfiguration.current
    val measurer = rememberTextMeasurer()
    val mediaVersion by media.version
    var vOffset by remember { mutableFloatStateOf(0f) }
    var drag by remember { mutableStateOf<DragState?>(null) }
    var trim by remember { mutableStateOf<TrimState?>(null) }
    var snapX by remember { mutableStateOf<Float?>(null) }

    val rulerH = with(density) { 24.dp.toPx() }
    val gap = with(density) { 5.dp.toPx() }
    val handleW = with(density) { 14.dp.toPx() }
    val headerW = with(density) { 30.dp.toPx() }
    val snapPx = with(density) { 10.dp.toPx() }
    val corner = with(density) { 6.dp.toPx() }
    fun rowHeight(kind: TrackKind) = with(density) {
        when (kind) { TrackKind.TEXT -> 30.dp; TrackKind.OVERLAY -> 46.dp; TrackKind.MAIN -> 58.dp; TrackKind.AUDIO -> 38.dp }.toPx()
    }

    // Read in gesture callbacks through these holders so the pointer handler sees fresh values.
    val latest = remember { object { var project = project; var playhead = playheadUs; var pps = pxPerSecond; var selected = selectedId } }
    latest.project = project; latest.playhead = playheadUs; latest.pps = pxPerSecond; latest.selected = selectedId

    BoxWithConstraints(modifier.background(Palette.Bg)) {
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()
        val centerX = widthPx / 2f

        fun rows(p: Project): List<Row> {
            var y = rulerH + gap - vOffset
            return p.tracks.map { t -> Row(t, y, rowHeight(t.kind)).also { y += it.height + gap } }
        }
        fun contentHeight(p: Project) = rulerH + gap + p.tracks.sumOf { (rowHeight(it.kind) + gap).toDouble() }.toFloat() + rowHeight(TrackKind.OVERLAY)
        fun xOf(t: Long, playhead: Long, pps: Float) = centerX + (t - playhead) / 1_000_000f * pps
        fun tOf(x: Float, playhead: Long, pps: Float) = playhead + ((x - centerX) / pps * 1_000_000f).toLong()

        fun hitTest(pos: Offset): Hit {
            val p = latest.project
            val rs = rows(p)
            val row = rs.firstOrNull { pos.y >= it.top && pos.y < it.top + it.height }
            if (row != null && pos.x < headerW && row.track.kind != TrackKind.TEXT) return Hit.TrackHeader(row.track)
            // The selected clip's trim handles come first, so they can always be grabbed.
            if (row != null) row.track.clips.firstOrNull { it.id == latest.selected }?.let { clip ->
                val x0 = xOf(clip.startUs, latest.playhead, latest.pps)
                val x1 = xOf(clip.endUs, latest.playhead, latest.pps)
                if (pos.x in (x0 - handleW)..(x0 + handleW * 0.4f)) return Hit.Handle(clip, row.track, true)
                if (pos.x in (x1 - handleW * 0.4f)..(x1 + handleW)) return Hit.Handle(clip, row.track, false)
            }
            // Transition buttons sit where two main-track clips touch.
            rs.firstOrNull { it.track.kind == TrackKind.MAIN }?.let { mainRow ->
                transitionPoints(mainRow.track, latest.selected).forEach { (id, t) ->
                    val bx = xOf(t, latest.playhead, latest.pps)
                    val cy = mainRow.top + mainRow.height / 2
                    if (abs(pos.x - bx) < handleW && abs(pos.y - cy) < handleW) return Hit.TransitionButton(id)
                }
            }
            if (row == null) return Hit.Empty
            for (clip in row.track.clips) {
                val x0 = xOf(clip.startUs, latest.playhead, latest.pps)
                val x1 = xOf(clip.endUs, latest.playhead, latest.pps)
                if (pos.x in x0..x1) return Hit.Body(clip, row.track)
            }
            if (row.track.kind == TrackKind.MAIN) {
                val t = tOf(pos.x, latest.playhead, latest.pps)
                if (p.mainGapAt(t) != null) return Hit.Gap(t)
            }
            return Hit.Empty
        }

        /** Target of a clip being dragged: the row under the finger, or a new track when above its kind's group. */
        fun dropTarget(d: DragState): Pair<Track, Boolean>? {
            val p = latest.project
            val category = p.categoryOf(d.clip)
            val rs = rows(p)
            val under = rs.firstOrNull { d.fingerY >= it.top && d.fingerY < it.top + it.height + gap }
            if (under != null && under.track.kind.accepts(category)) {
                // Visual clips dropped on the main track from elsewhere move into it; overlays stay overlays.
                return under.track to false
            }
            val group = rs.filter { it.track.kind.accepts(category) && it.track.kind != TrackKind.MAIN }
            val anchor = group.firstOrNull() ?: rs.firstOrNull { it.track.kind == TrackKind.MAIN && category == ClipCategory.VISUAL }
            if (anchor != null && d.fingerY < anchor.top) {
                val kind = when (category) { ClipCategory.VISUAL -> TrackKind.OVERLAY; ClipCategory.TEXT -> TrackKind.TEXT; ClipCategory.AUDIO -> TrackKind.AUDIO }
                val ref = p.tracks.firstOrNull { it.kind == kind } ?: return null
                return ref to true
            }
            if (category == ClipCategory.AUDIO && rs.lastOrNull()?.let { d.fingerY > it.top + it.height } == true) {
                val ref = p.tracks.lastOrNull { it.kind == TrackKind.AUDIO } ?: return null
                return ref to true
            }
            if (category == ClipCategory.VISUAL && under?.track?.kind == TrackKind.TEXT) {
                val ref = p.tracks.firstOrNull { it.kind == TrackKind.OVERLAY }
                return if (ref != null) ref to true else null
            }
            return null
        }

        /** Snaps a dragged clip's start (or end) to the playhead and other clips' edges. */
        fun snappedStart(d: DragState): Long {
            val p = latest.project
            val pps = latest.pps
            val rawStart = d.clip.startUs + (d.dx / pps * 1_000_000f).toLong()
            val edges = mutableListOf(latest.playhead, 0L)
            p.tracks.forEach { t -> t.clips.forEach { c -> if (c.id != d.clip.id) { edges += c.startUs; edges += c.endUs } } }
            val dur = d.clip.durationUs
            var best = rawStart
            var bestDist = snapPx
            for (e in edges) {
                for (candidate in listOf(e, e - dur)) {
                    val dist = abs(candidate - rawStart) / 1_000_000f * pps
                    if (dist < bestDist) { bestDist = dist; best = candidate }
                }
            }
            snapX = if (best != rawStart) xOf(if (edges.contains(best)) best else best + dur, latest.playhead, pps) else null
            return max(0L, best)
        }

        /** Snaps a trimmed edge to the playhead and other clips' edges; returns the timeline delta to apply. */
        fun snappedTrim(tr: TrimState): Long {
            val pps = latest.pps
            val edge = if (tr.start) tr.clip.startUs else tr.clip.endUs
            val raw = edge + (tr.dx / pps * 1_000_000f).toLong()
            val edges = mutableListOf(latest.playhead, 0L)
            latest.project.tracks.forEach { t -> t.clips.forEach { c -> if (c.id != tr.clip.id) { edges += c.startUs; edges += c.endUs } } }
            val best = edges.minByOrNull { abs(it - raw) }?.takeIf { abs(it - raw) / 1_000_000f * pps < snapPx } ?: raw
            snapX = if (best != raw) xOf(best, latest.playhead, pps) else null
            return best - edge
        }

        Canvas(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val hit = hitTest(down.position)
                        var last = down.position
                        var mode = 0 // 0 undecided, 1 scroll, 2 move, 3 trim, 4 zoom
                        var lastSpan = 0f
                        val startPlayhead = latest.playhead
                        val downAt = System.currentTimeMillis()
                        if (hit is Hit.Handle) { mode = 3; trim = TrimState(hit.clip, hit.start, 0f) }
                        while (true) {
                            val remaining = viewConfig.longPressTimeoutMillis - (System.currentTimeMillis() - downAt)
                            val event: PointerEvent? = if (mode == 0 && hit is Hit.Body) withTimeoutOrNull(max(1L, remaining)) { awaitPointerEvent() } else awaitPointerEvent()
                            if (event == null) {
                                // Long press without movement: pick the clip up.
                                mode = 2
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                val b = hit as Hit.Body
                                onSelect(b.clip.id)
                                drag = DragState(b.clip, b.track, 0f, 0f, down.position.y)
                                continue
                            }
                            val pressed = event.changes.filter { it.pressed }
                            if (pressed.isEmpty()) break
                            if (pressed.size >= 2 && mode != 2 && mode != 3) {
                                val a = pressed[0].position; val b = pressed[1].position
                                val span = sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
                                if (mode == 4 && lastSpan > 0f) onZoom((latest.pps * span / lastSpan).coerceIn(8f, 1600f))
                                lastSpan = span
                                mode = 4
                                event.changes.forEach { it.consume() }
                                continue
                            }
                            val change = pressed.first()
                            val pos = change.position
                            val moved = (pos - down.position).getDistance()
                            if (mode == 0 && moved > viewConfig.touchSlop) mode = 1
                            when (mode) {
                                1 -> {
                                    val dx = pos.x - last.x
                                    val dy = pos.y - last.y
                                    if (dx != 0f) onScrub(latest.playhead - (dx / latest.pps * 1_000_000f).toLong(), false)
                                    val maxV = max(0f, contentHeight(latest.project) - heightPx)
                                    vOffset = (vOffset - dy).coerceIn(0f, maxV)
                                }
                                2 -> drag = drag?.copy(dx = pos.x - down.position.x, dy = pos.y - down.position.y, fingerY = pos.y)
                                3 -> trim = trim?.copy(dx = pos.x - down.position.x)?.also { snappedTrim(it) }
                            }
                            last = pos
                            change.consume()
                        }
                        when (mode) {
                            0 -> when (hit) {
                                is Hit.TransitionButton -> onTransitionTap(hit.clipId)
                                is Hit.Body -> onSelect(if (latest.selected == hit.clip.id) null else hit.clip.id)
                                is Hit.Handle -> onSelect(hit.clip.id)
                                is Hit.TrackHeader -> onTrackHeaderTap(hit.track)
                                is Hit.Gap -> onGapTap(hit.timeUs)
                                Hit.Empty -> { onSelect(null); onGapTap(null) }
                            }
                            1 -> onScrub(latest.playhead, true)
                            2 -> drag?.let { d ->
                                val target = dropTarget(d)
                                val start = snappedStart(d)
                                if (target != null) onMove(d.clip.id, target.first.id, start, target.second)
                                drag = null
                                snapX = null
                            }
                            3 -> trim?.let { tr ->
                                if (tr.dx != 0f) onTrim(tr.clip.id, tr.start, snappedTrim(tr))
                                trim = null
                                snapX = null
                            }
                        }
                        if (mode != 1 && mode != 4 && startPlayhead != latest.playhead) onScrub(latest.playhead, true)
                    }
                }
        ) {
            @Suppress("UNUSED_EXPRESSION") mediaVersion
            val p = project
            val rs = rows(p)
            val pps = pxPerSecond
            val ph = playheadUs
            drawRuler(p, ph, pps, centerX, rulerH, measurer)
            for (row in rs) {
                if (row.top > size.height || row.top + row.height < rulerH) continue
                clipRect(top = rulerH) {
                    drawRect(Palette.Surface.copy(alpha = 0.5f), Offset(0f, row.top), Size(size.width, row.height))
                    if (row.track.kind == TrackKind.MAIN) selectedGapUs?.let { g -> p.mainGapAt(g) }?.let { gap ->
                        val gx0 = xOf(gap.first, ph, pps)
                        val gx1 = xOf(gap.last + 1, ph, pps)
                        drawRoundRect(Color.White.copy(alpha = 0.16f), Offset(gx0, row.top), Size(gx1 - gx0, row.height), CornerRadius(corner))
                        drawRoundRect(Color.White, Offset(gx0, row.top), Size(gx1 - gx0, row.height), CornerRadius(corner), style = Stroke(width = 3f))
                    }
                    for (clip in row.track.clips) {
                        if (drag?.clip?.id == clip.id) continue
                        var x0 = xOf(clip.startUs, ph, pps)
                        var x1 = xOf(clip.endUs, ph, pps)
                        trim?.takeIf { it.clip.id == clip.id }?.let { tr -> if (tr.start) x0 += tr.dx else x1 += tr.dx }
                        if (x1 < 0 || x0 > size.width) continue
                        drawClip(p, row, clip, x0, x1, corner, media, measurer, clip.id == selectedId, handleW, alpha = if (row.track.hidden) 0.35f else 1f)
                    }
                    if (row.track.kind == TrackKind.MAIN) drawTransitionButtons(row, transitionPoints(row.track, selectedId), ph, pps, centerX, handleW)
                    if (row.track.kind != TrackKind.TEXT) drawTrackHeader(row, headerW, measurer)
                }
            }
            drag?.let { d ->
                val y = (rs.firstOrNull { it.track.id == d.track.id }?.top ?: 0f) + d.dy
                val x0 = xOf(d.clip.startUs, ph, pps) + d.dx
                val x1 = x0 + d.clip.durationUs / 1_000_000f * pps
                val row = Row(d.track, y, rowHeight(d.track.kind))
                drawClip(p, row, d.clip, x0, x1, corner, media, measurer, selected = true, handleW = 0f, alpha = 0.85f)
            }
            snapX?.let { drawLine(Palette.Teal, Offset(it, rulerH), Offset(it, size.height), strokeWidth = 2f) }
            // Playhead
            drawLine(Color.White, Offset(centerX, 0f), Offset(centerX, size.height), strokeWidth = 3f)
            drawCircle(Color.White, radius = 6f, center = Offset(centerX, rulerH - 4f))
        }
    }
}

private fun DrawScope.drawRuler(p: Project, playhead: Long, pps: Float, centerX: Float, rulerH: Float, measurer: androidx.compose.ui.text.TextMeasurer) {
    drawRect(Palette.Surface, Offset.Zero, Size(size.width, rulerH))
    val steps = listOf(0.1f, 0.25f, 0.5f, 1f, 2f, 5f, 10f, 15f, 30f, 60f, 120f, 300f)
    val major = steps.firstOrNull { it * pps >= 90f } ?: 600f
    val minor = major / 5
    val startS = (playhead / 1_000_000f) - centerX / pps
    val endS = startS + size.width / pps
    val style = TextStyle(color = Palette.TextDim, fontSize = 9.sp)
    // Ticks by integer index, so labels never drift (every fifth tick is a labelled major tick).
    var k = floor(startS / minor).toLong().coerceAtLeast(0)
    while (k * minor <= endS) {
        val s = k * minor
        val x = centerX + (s - playhead / 1_000_000f) * pps
        val isMajor = k % 5 == 0L
        drawLine(Palette.TextDim.copy(alpha = if (isMajor) 0.8f else 0.35f), Offset(x, rulerH - if (isMajor) 9f else 5f), Offset(x, rulerH), strokeWidth = 1.5f)
        if (isMajor) {
            val us = Math.round(s.toDouble() * 1_000_000)
            val label = if (major < 1f) "%.1fs".format(us / 1_000_000f) else formatTime(us)
            drawText(measurer, label, Offset(x + 3f, 2f), style)
        }
        k++
    }
    val endX = centerX + (p.durationUs - playhead) / 1_000_000f * pps
    if (endX in 0f..size.width) drawLine(Palette.Accent.copy(alpha = 0.6f), Offset(endX, 0f), Offset(endX, size.height), strokeWidth = 1.5f)
}

private fun DrawScope.drawClip(
    p: Project, row: Row, clip: Clip, x0: Float, x1: Float, corner: Float, media: MediaCache,
    measurer: androidx.compose.ui.text.TextMeasurer, selected: Boolean, handleW: Float, alpha: Float,
) {
    val top = row.top
    val h = row.height
    val w = max(2f, x1 - x0)
    val asset = p.asset(clip.assetId)
    val base = when {
        clip.isText -> Palette.TextClip
        row.track.kind == TrackKind.AUDIO -> Palette.Audio
        row.track.kind == TrackKind.OVERLAY -> Palette.Overlay
        else -> Palette.Main
    }
    drawRoundRect(base.copy(alpha = alpha), Offset(x0, top), Size(w, h), CornerRadius(corner))
    clipRect(left = max(0f, x0), top = top, right = min(size.width, x1), bottom = top + h) {
        when {
            asset != null && (asset.type == MediaType.VIDEO || asset.type == MediaType.IMAGE) && !clip.audioOnly && row.track.kind != TrackKind.AUDIO -> {
                val heightPx = h.toInt()
                val tileW = max(16f, h * (asset.width.toFloat() / max(1, asset.height)).coerceIn(0.5f, 2f))
                val tileUs = tileW / max(1f, (x1 - x0)) * clip.durationUs
                val step = listOf(250_000L, 500_000L, 1_000_000L, 2_000_000L, 5_000_000L, 10_000_000L, 30_000_000L).firstOrNull { it >= tileUs * clip.speed } ?: 60_000_000L
                var tx = x0
                while (tx < x1) {
                    if (tx + tileW >= 0 && tx <= size.width) {
                        val tl = clip.startUs + ((tx - x0) / max(1f, x1 - x0) * clip.durationUs).toLong()
                        val img = media.thumbnail(asset, clip.sourceTimeAt(tl), step, heightPx)
                        if (img != null) {
                            val dstW = tileW.toInt().coerceAtLeast(1)
                            drawImage(img, srcOffset = IntOffset.Zero, srcSize = IntSize(img.width, img.height), dstOffset = IntOffset(tx.toInt(), top.toInt()), dstSize = IntSize(dstW, h.toInt()), alpha = alpha)
                        }
                    }
                    tx += tileW
                }
            }
            asset != null && asset.hasAudio -> {
                val peaks = media.peaks(asset)
                val mid = top + h / 2
                if (peaks != null) {
                    var x = max(0f, x0)
                    val end = min(size.width, x1)
                    while (x < end) {
                        val tl = clip.startUs + ((x - x0) / max(1f, x1 - x0) * clip.durationUs).toLong()
                        val idx = (clip.sourceTimeAt(tl) / MediaCache.PEAK_US).toInt()
                        val v = peaks.getOrNull(idx) ?: 0f
                        val amp = (v * clip.volume.coerceAtMost(1.5f)).coerceIn(0.02f, 1f) * (h * 0.42f)
                        drawLine(Palette.Teal.copy(alpha = 0.85f * alpha), Offset(x, mid - amp), Offset(x, mid + amp), strokeWidth = 2f)
                        x += 3f
                    }
                }
            }
        }
        val label = when {
            clip.isText -> clip.text!!.text.lineSequence().firstOrNull().orEmpty()
            else -> asset?.name.orEmpty()
        }
        val badges = buildList {
            if (clip.speed != 1f) add("${"%.2f".format(clip.speed).trimEnd('0').trimEnd('.')}×")
            if (!clip.isText && clip.volume == 0f) add("muted")
            if (clip.filter != null) add("fx")
        }.joinToString(" · ")
        val text = listOf(label, badges).filter { it.isNotEmpty() }.joinToString("  ")
        if (text.isNotEmpty() && w > 30f) {
            val tx = max(x0, 0f) + 6f
            drawRect(Color.Black.copy(alpha = 0.35f), Offset(tx - 3f, top + 2f), Size(min(w - 6f, text.length * 13f + 6f), 26f))
            drawText(measurer, text, Offset(tx, top + 3f), TextStyle(color = Color.White, fontSize = 10.sp), overflow = TextOverflow.Ellipsis, maxLines = 1, size = Size(max(1f, min(w - 12f, 600f)), 30f))
        }
        // Keyframes
        clip.keyframes.forEach { k ->
            val kx = x0 + k.offsetUs / max(1f, clip.durationUs.toFloat()) * (x1 - x0)
            val cy = top + h - 9f
            val path = Path().apply { moveTo(kx, cy - 6f); lineTo(kx + 6f, cy); lineTo(kx, cy + 6f); lineTo(kx - 6f, cy); close() }
            drawPath(path, Color(0xFFFFD54F))
        }
        // Fades
        if (clip.fadeInUs > 0) {
            val fx = x0 + clip.fadeInUs / max(1f, clip.durationUs.toFloat()) * (x1 - x0)
            drawLine(Color.White.copy(alpha = 0.7f), Offset(x0, top + h), Offset(fx, top), strokeWidth = 1.5f)
        }
        if (clip.fadeOutUs > 0) {
            val fx = x1 - clip.fadeOutUs / max(1f, clip.durationUs.toFloat()) * (x1 - x0)
            drawLine(Color.White.copy(alpha = 0.7f), Offset(fx, top), Offset(x1, top + h), strokeWidth = 1.5f)
        }
    }
    if (selected) {
        drawRoundRect(Color.White, Offset(x0, top), Size(w, h), CornerRadius(corner), style = Stroke(width = 4f))
        if (handleW > 0f) {
            drawRoundRect(Color.White, Offset(x0 - handleW * 0.6f, top), Size(handleW * 0.6f, h), CornerRadius(corner))
            drawRoundRect(Color.White, Offset(x1, top), Size(handleW * 0.6f, h), CornerRadius(corner))
            val gy = top + h / 2
            drawLine(Palette.Bg, Offset(x0 - handleW * 0.3f, gy - 8f), Offset(x0 - handleW * 0.3f, gy + 8f), strokeWidth = 3f)
            drawLine(Palette.Bg, Offset(x1 + handleW * 0.3f, gy - 8f), Offset(x1 + handleW * 0.3f, gy + 8f), strokeWidth = 3f)
        }
    }
}

/**
 * Where transition buttons go: (incoming clip id, time) for every pair of touching main-track clips. Boundaries of the
 * selected clip are left out so its trim handles stay free.
 */
private fun transitionPoints(main: Track, selectedId: String?): List<Pair<String, Long>> {
    val clips = main.clips
    return (1 until clips.size).mapNotNull { i ->
        val prev = clips[i - 1]
        val c = clips[i]
        if (!touches(prev, c) || c.id == selectedId || prev.id == selectedId) null
        else c.id to c.startUs + (c.transitionIn?.durationUs ?: 0L) / 2
    }
}

private fun DrawScope.drawTransitionButtons(row: Row, points: List<Pair<String, Long>>, playhead: Long, pps: Float, centerX: Float, handleW: Float) {
    for ((id, t) in points) {
        val c = row.track.clips.first { it.id == id }
        val bx = centerX + (t - playhead) / 1_000_000f * pps
        if (bx < -handleW || bx > size.width + handleW) continue
        val cy = row.top + row.height / 2
        val s = handleW * 1.1f
        val has = c.transitionIn != null
        drawRoundRect(if (has) Palette.Accent else Color.White, Offset(bx - s / 2, cy - s / 2), Size(s, s), CornerRadius(4f))
        val ink = if (has) Color.White else Palette.Bg
        drawLine(ink, Offset(bx - s * 0.25f, cy - s * 0.15f), Offset(bx + s * 0.25f, cy - s * 0.15f), strokeWidth = 2.5f)
        drawLine(ink, Offset(bx - s * 0.25f, cy + s * 0.15f), Offset(bx + s * 0.25f, cy + s * 0.15f), strokeWidth = 2.5f)
    }
}

private fun DrawScope.drawTrackHeader(row: Row, headerW: Float, measurer: androidx.compose.ui.text.TextMeasurer) {
    val t = row.track
    drawRect(Palette.Bg.copy(alpha = 0.75f), Offset(0f, row.top), Size(headerW, row.height))
    val icon = when {
        t.kind == TrackKind.AUDIO || t.kind == TrackKind.MAIN -> if (t.muted) "🔇" else "🔊"
        else -> if (t.hidden) "🚫" else "👁"
    }
    drawText(measurer, icon, Offset(5f, row.top + row.height / 2 - 18f), TextStyle(fontSize = 13.sp))
}
