package com.framenova.app.ui.editor

import android.view.SurfaceView
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
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

@UnstableApi
@Composable
fun PreviewPane(vm: EditorViewModel, modifier: Modifier = Modifier) {
    val project = vm.project
    val canvas = project.canvas.size
    val density = LocalDensity.current
    val viewConfig = LocalViewConfiguration.current
    var guideX by remember { mutableStateOf(false) }
    var guideY by remember { mutableStateOf(false) }

    BoxWithConstraints(modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        Box(Modifier.aspectRatio(canvas.aspect, matchHeightConstraintsFirst = maxWidth / maxHeight > canvas.aspect)) {
            AndroidView(
                factory = { ctx -> SurfaceView(ctx).also { vm.engine.attach(it) } },
                onRelease = { vm.engine.detach(it) },
                modifier = Modifier.fillMaxSize(),
            )
            val snapPx = with(density) { 8.dp.toPx() }
            Canvas(
                Modifier.fillMaxSize().pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val w = size.width.toFloat()
                        val h = size.height.toFloat()
                        val p0 = vm.project
                        val cs = p0.canvas.size
                        val scale = cs.width / w
                        val t = vm.playheadUs
                        val layers = p0.visualGeometriesAt(t, cs.width, cs.height) { c -> textSize(c, t, cs.width, cs.height) }
                        val hit = layers.lastOrNull { (_, g) -> g.contains(down.position.x * scale, down.position.y * scale) }?.first
                        val selected = vm.selectedClip
                        // Keep editing the selected layer when the touch is inside it, even if another one is on top.
                        val target = selected?.takeIf { s -> layers.any { (c, g) -> c.id == s.id && g.contains(down.position.x * scale, down.position.y * scale) } } ?: hit
                        var transforming = false
                        var moved = false
                        var base: Transform? = null
                        var acc = Transform()
                        while (true) {
                            val event = awaitPointerEvent()
                            if (event.changes.none { it.pressed }) break
                            if (target == null) continue
                            val pan = event.calculatePan()
                            val zoom = event.calculateZoom()
                            val rotation = event.calculateRotation()
                            if (!moved && (event.changes.first().position - down.position).getDistance() < viewConfig.touchSlop && event.changes.size < 2) continue
                            moved = true
                            if (!transforming) {
                                transforming = true
                                if (vm.selectedId != target.id) vm.selectedId = target.id
                                vm.beginGesture()
                                base = vm.project.clip(target.id)?.transformAt(t) ?: target.transform
                                acc = base!!
                            }
                            acc = acc.copy(
                                cx = acc.cx + pan.x / w,
                                cy = acc.cy + pan.y / h,
                                scale = (acc.scale * zoom).coerceIn(0.05f, 20f),
                                rotation = acc.rotation + rotation,
                            )
                            // Snap to the canvas center and right angles.
                            var shown = acc
                            guideX = abs(acc.cx - 0.5f) * w < snapPx
                            guideY = abs(acc.cy - 0.5f) * h < snapPx
                            if (guideX) shown = shown.copy(cx = 0.5f)
                            if (guideY) shown = shown.copy(cy = 0.5f)
                            val r = acc.rotation
                            val nearest = (r / 90f).roundToInt() * 90f
                            if (abs(r - nearest) < 3f) shown = shown.copy(rotation = nearest)
                            val frame = vm.frameUs
                            vm.live(vm.project.updateClip(target.id) { it.withTransformAt(t, shown, frame) })
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                        guideX = false; guideY = false
                        if (transforming) vm.endGesture()
                        else if (!moved) vm.selectedId = hit?.id
                    }
                }
            ) {
                val cs = project.canvas.size
                val s = size.width / cs.width
                if (guideX) drawLine(Palette.Teal, Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), strokeWidth = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)))
                if (guideY) drawLine(Palette.Teal, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), strokeWidth = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)))
                val sel = vm.selectedId ?: return@Canvas
                val t = vm.playheadUs
                val g: LayerGeometry = project.visualGeometriesAt(t, cs.width, cs.height) { c -> textSize(c, t, cs.width, cs.height) }
                    .firstOrNull { it.first.id == sel }?.second ?: return@Canvas
                val cx = g.centerX * s; val cy = g.centerY * s
                val hw = g.width * s / 2; val hh = g.height * s / 2
                rotate(g.rotation, Offset(cx, cy)) {
                    val path = Path().apply {
                        moveTo(cx - hw, cy - hh); lineTo(cx + hw, cy - hh); lineTo(cx + hw, cy + hh); lineTo(cx - hw, cy + hh); close()
                    }
                    drawPath(path, Color.White, style = Stroke(width = 3f))
                    for ((x, y) in listOf(cx - hw to cy - hh, cx + hw to cy - hh, cx + hw to cy + hh, cx - hw to cy + hh)) {
                        drawCircle(Color.White, radius = 9f, center = Offset(x, y))
                        drawCircle(Palette.Accent, radius = 6f, center = Offset(x, y))
                    }
                }
            }
        }
    }
}
