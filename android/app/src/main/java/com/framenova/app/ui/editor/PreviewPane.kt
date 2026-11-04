package com.framenova.app.ui.editor

import android.view.TextureView
import androidx.compose.foundation.Image
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateRotation
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import com.framenova.app.engine.LayerGeometry
import com.framenova.app.engine.TextRenderer
import com.framenova.app.engine.visualGeometriesAt
import com.framenova.app.model.Clip
import com.framenova.app.model.Transform
import com.framenova.app.model.transformAt
import com.framenova.app.model.updateClip
import com.framenova.app.model.withTransformAt
import com.framenova.app.ui.theme.Palette
import kotlin.math.abs
import kotlin.math.roundToInt

private val textSizeCache = HashMap<Any, Pair<Float, Float>>()

/** Size of a text clip in canvas pixels, cached per style and scale. */
fun textSize(clip: Clip, atUs: Long, canvasW: Int, canvasH: Int): Pair<Float, Float>? {
    val style = clip.text ?: return null
    val scale = clip.transformAt(atUs).scale
    val key = listOf(style, scale, canvasW, canvasH)
    return textSizeCache.getOrPut(key) {
        if (textSizeCache.size > 400) textSizeCache.clear()
        TextRenderer.measure(style, scale, canvasW, canvasH)
    }
}

/**
 * Where the canvas sits inside a preview area of [w] x [h]: left, top, width, height, fitted and centred within a
 * margin of [pad] on every side (so all canvas edges, and a little beyond them, are always visible).
 */
private fun canvasRect(w: Float, h: Float, aspect: Float, pad: Float): FloatArray {
    val aw = w - 2 * pad; val ah = h - 2 * pad
    val cw: Float; val ch: Float
    if (aw / ah > aspect) { ch = ah; cw = ah * aspect } else { cw = aw; ch = aw / aspect }
    return floatArrayOf((w - cw) / 2, (h - ch) / 2, cw, ch)
}

private val CanvasMargin = 12.dp

/** The surround of the canvas: lighter than the canvas, so its edge is always visible. */
private val Surround = Color(0xFF2A2A33)
private val OutsideOrange = Color(0xFFFFA726)

@UnstableApi
@Composable
fun PreviewPane(vm: EditorViewModel, modifier: Modifier = Modifier) {
    val project = vm.project
    val canvas = project.canvas.size
    val density = LocalDensity.current
    val viewConfig = LocalViewConfiguration.current
    var guideX by remember { mutableStateOf(false) }
    var guideY by remember { mutableStateOf(false) }
    // Double tap on a text layer opens the text editor.
    var lastTapMs by remember { mutableStateOf(0L) }
    var lastTapId by remember { mutableStateOf<String?>(null) }

    BoxWithConstraints(modifier.background(Surround), contentAlignment = Alignment.Center) {
        val margin = CanvasMargin
        Box(Modifier.padding(margin).aspectRatio(canvas.aspect, matchHeightConstraintsFirst = (maxWidth - margin * 2) / (maxHeight - margin * 2) > canvas.aspect).background(Color.Black)) {
            AndroidView(
                factory = { ctx -> TextureView(ctx).also { vm.engine.attach(it) } },
                onRelease = { vm.engine.detach(it) },
                modifier = Modifier.fillMaxSize(),
            )
            // The last frame, covering a rebuild until the new player's first frame is on screen.
            vm.engine.cover.value?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds) }
            if (vm.quickPreview) QuickPreview(vm, Modifier.fillMaxSize())
        }
        val snapPx = with(density) { 8.dp.toPx() }
        val snapReleasePx = with(density) { 20.dp.toPx() }
        val borderPx = with(density) { 1.5.dp.toPx() }
        val marginPx = with(density) { margin.toPx() }
        // Gestures and outlines cover the whole preview area, so layers moved off the canvas can still be grabbed.
        Canvas(
            Modifier.fillMaxSize().pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val p0 = vm.project
                    val cs = p0.canvas.size
                    val (left, top, w, h) = canvasRect(size.width.toFloat(), size.height.toFloat(), cs.aspect, marginPx).let { listOf(it[0], it[1], it[2], it[3]) }
                    val scale = cs.width / w
                    fun cx(o: Offset) = (o.x - left) * scale
                    fun cy(o: Offset) = (o.y - top) * scale
                    val t = vm.playheadUs
                    val layers = p0.visualGeometriesAt(t, cs.width, cs.height) { c -> textSize(c, t, cs.width, cs.height) }
                        .filter { (clip, _) -> p0.trackOf(clip.id)?.locked == false }
                    // Text is small: it gets an extra margin to be easier to grab, and wins over the layers below it.
                    val textSlop = with(density) { 20.dp.toPx() } * scale
                    val px = cx(down.position); val py = cy(down.position)
                    val hit = layers.lastOrNull { (c, g) -> c.isText && containsWithin(g, px, py, textSlop) }?.first
                        ?: layers.lastOrNull { (_, g) -> g.contains(px, py) }?.first
                    val selected = vm.selectedClip?.takeIf { s -> layers.any { it.first.id == s.id } }
                    // Keep editing the selected layer when the touch is inside it, even if another one is on top.
                    var target = selected?.takeIf { s -> layers.any { (c, g) -> c.id == s.id && containsWithin(g, px, py, if (c.isText) textSlop else 0f) } } ?: hit
                    // Dragging a corner handle of the selected layer resizes it about its centre.
                    val selectedGeometry = selected?.let { s -> layers.firstOrNull { it.first.id == s.id }?.second }
                    val cornerSlop = with(density) { 28.dp.toPx() }
                    val centre = selectedGeometry?.let { Offset(left + it.centerX / scale, top + it.centerY / scale) }
                    val cornerResize = selectedGeometry != null && centre != null &&
                        corners(selectedGeometry).any { (x, y) -> (Offset(left + x / scale, top + y / scale) - down.position).getDistance() < cornerSlop }
                    if (cornerResize) target = selected
                    var transforming = false
                    var moved = false
                    var base: Transform? = null
                    var acc = Transform()
                    while (true) {
                        val event = awaitPointerEvent()
                        if (event.changes.none { it.pressed }) break
                        // A two-finger gesture (pinch to resize, twist to rotate) always works on the selected layer,
                        // wherever the fingers are: on small text they often land on the layer behind it.
                        if (!transforming && event.changes.count { it.pressed } >= 2 && selected != null) target = selected
                        if (target == null) continue
                        val pan = event.calculatePan()
                        val zoom = event.calculateZoom()
                        val rotation = event.calculateRotation()
                        if (!moved && (event.changes.first().position - down.position).getDistance() < viewConfig.touchSlop && event.changes.size < 2) continue
                        moved = true
                        val active = target
                        if (!transforming) {
                            transforming = true
                            if (vm.selectedId != active.id) vm.selectedId = active.id
                            vm.layerGesture = true
                            vm.beginGesture()
                            base = vm.project.clip(active.id)?.transformAt(t) ?: active.transform
                            acc = base
                        }
                        if (cornerResize && centre != null) {
                            // The scale follows the finger's distance from the centre.
                            val start = (down.position - centre).getDistance().coerceAtLeast(1f)
                            val now = (event.changes.first().position - centre).getDistance()
                            acc = base!!.copy(scale = (base!!.scale * now / start).coerceIn(0.05f, 20f))
                        } else acc = acc.copy(
                            cx = acc.cx + pan.x / w,
                            cy = acc.cy + pan.y / h,
                            scale = (acc.scale * zoom).coerceIn(0.05f, 20f),
                            rotation = acc.rotation + rotation,
                        )
                        // Snap to the canvas center and right angles. A snap holds until the layer is moved clearly
                        // away (hysteresis), so a slightly unsteady drag does not make it jump on and off the line.
                        var shown = acc
                        if (!cornerResize) {
                            guideX = abs(acc.cx - 0.5f) * w < (if (guideX) snapReleasePx else snapPx)
                            guideY = abs(acc.cy - 0.5f) * h < (if (guideY) snapReleasePx else snapPx)
                        }
                        if (guideX) shown = shown.copy(cx = 0.5f)
                        if (guideY) shown = shown.copy(cy = 0.5f)
                        val r = acc.rotation
                        val nearest = (r / 90f).roundToInt() * 90f
                        if (abs(r - nearest) < 3f) shown = shown.copy(rotation = nearest)
                        val frame = vm.frameUs
                        vm.live(vm.project.updateClip(active.id) { it.withTransformAt(t, shown, frame) })
                        event.changes.forEach { if (it.positionChanged()) it.consume() }
                    }
                    guideX = false; guideY = false
                    if (transforming) vm.endGesture()
                    else if (!moved) {
                        val now = System.currentTimeMillis()
                        val double = hit != null && hit.id == lastTapId && now - lastTapMs < viewConfig.doubleTapTimeoutMillis
                        if (double && hit.isText) { vm.openTextEditor(hit.id); lastTapId = null }
                        else { vm.selectedId = hit?.id; lastTapId = hit?.id; lastTapMs = now }
                    }
                }
            }
        ) {
            val cs = project.canvas.size
            val (left, top, w, h) = canvasRect(size.width, size.height, cs.aspect, marginPx).let { listOf(it[0], it[1], it[2], it[3]) }
            val s = w / cs.width
            // The canvas edge: what is outside it is not in the video.
            drawRect(Color.White.copy(alpha = 0.55f), Offset(left - borderPx / 2, top - borderPx / 2), Size(w + borderPx, h + borderPx), style = Stroke(width = borderPx))
            if (guideX) drawLine(Palette.Teal, Offset(left + w / 2, top), Offset(left + w / 2, top + h), strokeWidth = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)))
            if (guideY) drawLine(Palette.Teal, Offset(left, top + h / 2), Offset(left + w, top + h / 2), strokeWidth = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)))
            val sel = vm.selectedId ?: return@Canvas
            val t = vm.playheadUs
            val g: LayerGeometry = project.visualGeometriesAt(t, cs.width, cs.height) { c -> textSize(c, t, cs.width, cs.height) }
                .firstOrNull { it.first.id == sel }?.second ?: return@Canvas
            val cx = left + g.centerX * s; val cy = top + g.centerY * s
            val hw = g.width * s / 2; val hh = g.height * s / 2
            val outside = layerOutsideCanvas(g, cs.width.toFloat(), cs.height.toFloat())
            val outline = if (outside) OutsideOrange else Color.White
            rotate(g.rotation, Offset(cx, cy)) {
                val path = Path().apply {
                    moveTo(cx - hw, cy - hh); lineTo(cx + hw, cy - hh); lineTo(cx + hw, cy + hh); lineTo(cx - hw, cy + hh); close()
                }
                drawPath(path, outline, style = Stroke(width = 3f, pathEffect = if (outside) PathEffect.dashPathEffect(floatArrayOf(14f, 8f)) else null))
                for ((x, y) in listOf(cx - hw to cy - hh, cx + hw to cy - hh, cx + hw to cy + hh, cx - hw to cy + hh)) {
                    drawCircle(outline, radius = 9f, center = Offset(x, y))
                    drawCircle(Palette.Accent, radius = 6f, center = Offset(x, y))
                }
            }
        }
        // Says so when the selected layer reaches past the canvas edge.
        val selectedOutside = vm.selectedId?.let { sel ->
            val t = vm.playheadUs
            project.visualGeometriesAt(t, canvas.width, canvas.height) { c -> textSize(c, t, canvas.width, canvas.height) }
                .firstOrNull { it.first.id == sel }?.second?.let { layerOutsideCanvas(it, canvas.width.toFloat(), canvas.height.toFloat()) }
        } == true
        if (selectedOutside) Text(
            "Partly outside the canvas: only the part inside is in the video",
            color = Color.Black, fontSize = 11.sp,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 6.dp)
                .background(OutsideOrange, RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}

/** The four corners of a layer's rotated rectangle, in canvas pixels. */
private fun corners(g: LayerGeometry): List<Pair<Float, Float>> {
    val r = Math.toRadians(g.rotation.toDouble())
    val c = kotlin.math.cos(r).toFloat(); val sn = kotlin.math.sin(r).toFloat()
    val hw = g.width / 2; val hh = g.height / 2
    return listOf(-hw to -hh, hw to -hh, hw to hh, -hw to hh).map { (x, y) -> (g.centerX + x * c - y * sn) to (g.centerY + x * sn + y * c) }
}

/** Whether canvas point ([x], [y]) is inside the layer's rotated rectangle grown by [slop] on every side. */
private fun containsWithin(g: LayerGeometry, x: Float, y: Float, slop: Float): Boolean {
    val r = Math.toRadians(-g.rotation.toDouble())
    val dx = x - g.centerX; val dy = y - g.centerY
    val lx = dx * kotlin.math.cos(r) - dy * kotlin.math.sin(r)
    val ly = dx * kotlin.math.sin(r) + dy * kotlin.math.cos(r)
    return kotlin.math.abs(lx) <= g.width / 2 + slop && kotlin.math.abs(ly) <= g.height / 2 + slop
}

/** Whether a layer's rotated rectangle reaches past the canvas (beyond a pixel of rounding). */
private fun layerOutsideCanvas(g: LayerGeometry, canvasW: Float, canvasH: Float): Boolean {
    val r = Math.toRadians(g.rotation.toDouble())
    val c = kotlin.math.cos(r).toFloat(); val sn = kotlin.math.sin(r).toFloat()
    val hw = g.width / 2; val hh = g.height / 2
    return listOf(-hw to -hh, hw to -hh, hw to hh, -hw to hh).any { (x, y) ->
        val px = g.centerX + x * c - y * sn
        val py = g.centerY + x * sn + y * c
        px < -1f || py < -1f || px > canvasW + 1f || py > canvasH + 1f
    }
}

private val quickTextCache = object : android.util.LruCache<Any, androidx.compose.ui.graphics.ImageBitmap>(24) {}

/**
 * The frame at the playhead drawn from decoded stills (MediaCache.scrubFrame), positioned like the real composition:
 * shown while the timeline is dragged or a layer is moved on the preview, when rebuilding the player for every change
 * would be far too slow to follow the finger. Filters and adjustments are left out.
 */
@UnstableApi
@Composable
private fun QuickPreview(vm: EditorViewModel, modifier: Modifier) {
    val version by vm.media.version
    // Clipped to the canvas, like the video: what lies outside is not in it.
    Canvas(modifier.clipToBounds().background(Color.Black)) {
        @Suppress("UNUSED_EXPRESSION") version
        val project = vm.project
        val t = vm.playheadUs
        val cs = project.canvas.size
        val s = size.width / cs.width
        val frameHeight = (size.height).roundToInt().coerceIn(180, 720)
        val layers = project.visualGeometriesAt(t, cs.width, cs.height) { c -> textSize(c, t, cs.width, cs.height) }
        for ((clip, g) in layers) {
            if (g.opacity <= 0f) continue
            val image: androidx.compose.ui.graphics.ImageBitmap
            var src = androidx.compose.ui.unit.IntOffset.Zero to androidx.compose.ui.unit.IntSize(0, 0)
            val style = clip.text
            var geometry = g
            if (style != null) {
                // Match the renderer's text animation (fade, slide, scale) at this time.
                val anim = com.framenova.app.engine.TextAnimations.at(style, t - clip.startUs, clip.durationUs)
                if (anim.alpha <= 0f) continue
                geometry = g.copy(centerY = g.centerY + anim.dy * cs.height, width = g.width * anim.scale, height = g.height * anim.scale, opacity = g.opacity * anim.alpha)
                val scale = clip.transformAt(t).scale
                // Text is rendered at the preview's size, not the canvas size, to stay cheap.
                val key = listOf(style, scale, size.width.roundToInt(), size.height.roundToInt())
                image = quickTextCache.get(key) ?: TextRenderer.render(style, scale, size.width.roundToInt(), size.height.roundToInt())
                    .asImageBitmap().also { quickTextCache.put(key, it) }
                src = androidx.compose.ui.unit.IntOffset.Zero to androidx.compose.ui.unit.IntSize(image.width, image.height)
            } else {
                val asset = project.asset(clip.assetId) ?: continue
                image = vm.media.scrubFrame(asset, clip.sourceTimeAt(t), frameHeight) ?: continue
                val c = clip.crop
                src = androidx.compose.ui.unit.IntOffset((c.left * image.width).roundToInt(), (c.top * image.height).roundToInt()) to
                    androidx.compose.ui.unit.IntSize((c.widthFraction * image.width).roundToInt().coerceAtLeast(1), (c.heightFraction * image.height).roundToInt().coerceAtLeast(1))
            }
            val cx = geometry.centerX * s; val cy = geometry.centerY * s
            val w = geometry.width * s; val h = geometry.height * s
            rotate(geometry.rotation, Offset(cx, cy)) {
                scale(if (clip.flipH) -1f else 1f, if (clip.flipV) -1f else 1f, Offset(cx, cy)) {
                    drawImage(
                        image, srcOffset = src.first, srcSize = src.second,
                        dstOffset = androidx.compose.ui.unit.IntOffset((cx - w / 2).roundToInt(), (cy - h / 2).roundToInt()),
                        dstSize = androidx.compose.ui.unit.IntSize(w.roundToInt().coerceAtLeast(1), h.roundToInt().coerceAtLeast(1)),
                        alpha = geometry.opacity.coerceIn(0f, 1f),
                    )
                }
            }
        }
    }
}
