package com.framenova.app.ui.editor

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatAlignLeft
import androidx.compose.material.icons.automirrored.filled.FormatAlignRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.FormatAlignCenter
import androidx.compose.material.icons.filled.FormatBold
import androidx.compose.material.icons.filled.FormatItalic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import com.framenova.app.engine.FontCatalog
import com.framenova.app.engine.FontGroup
import com.framenova.app.engine.FontManager
import com.framenova.app.engine.Filters
import com.framenova.app.model.*
import com.framenova.app.ui.theme.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

@Composable
fun PanelScaffold(title: String, onDone: () -> Unit, modifier: Modifier = Modifier, actions: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().background(Palette.Surface)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            actions()
            IconButton(onClick = onDone) { Icon(Icons.Default.Check, "Done", tint = Palette.Accent) }
        }
        Column(Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp), content = content)
    }
}

@Composable
fun LabeledSlider(
    label: String, value: Float, range: ClosedFloatingPointRange<Float>, format: (Float) -> String,
    onChange: (Float) -> Unit, onFinished: () -> Unit = {},
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = androidx.compose.material3.MaterialTheme.typography.bodySmall, modifier = Modifier.width(84.dp), color = Palette.TextDim)
        Slider(value = value.coerceIn(range), onValueChange = onChange, valueRange = range, onValueChangeFinished = onFinished, modifier = Modifier.weight(1f))
        Text(format(value), style = androidx.compose.material3.MaterialTheme.typography.bodySmall, modifier = Modifier.width(52.dp), color = Palette.Text)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChipRow(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) { content() }
}

@Composable
fun ColorRow(colors: List<Long>, selected: Long, onPick: (Long) -> Unit, allowNone: Boolean = false) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
        if (allowNone) item {
            Box(
                Modifier.size(30.dp).clip(CircleShape).background(Palette.Surface3)
                    .border(2.dp, if (selected == 0L) Palette.Accent else Color.Transparent, CircleShape).clickable { onPick(0L) },
                contentAlignment = Alignment.Center,
            ) { Text("⌀", fontSize = 14.sp) }
        }
        items(colors) { c ->
            Box(
                Modifier.size(30.dp).clip(CircleShape).background(Color(c.toInt()))
                    .border(2.dp, if (selected == c) Palette.Accent else Color.White.copy(alpha = 0.25f), CircleShape).clickable { onPick(c) }
            )
        }
    }
}

val textColors = listOf(0xFFFFFFFF, 0xFF000000, 0xFFFFD54F, 0xFFFF7043, 0xFFE53935, 0xFFEC407A, 0xFFAB47BC, 0xFF7E57C2, 0xFF42A5F5, 0xFF26C6DA, 0xFF66BB6A, 0xFF9CCC65, 0xFF8D6E63, 0xFF9E9E9E)
private val bgColors = listOf(0xCC000000, 0x99000000, 0xCCFFFFFF, 0xE6FFD54F, 0xE6E53935, 0xE642A5F5, 0xE666BB6A, 0xE67E57C2)

private fun pct(v: Float) = "${(v * 100).roundToInt()}%"
private fun signed(v: Float) = (if (v > 0) "+" else "") + (v * 100).roundToInt()
private fun secs(us: Long) = "%.1fs".format(us / 1_000_000f)

// ---------------------------------------------------------------------------------------------------------------

@UnstableApi
@Composable
fun SpeedPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    var v by remember(clip.id) { mutableFloatStateOf((ln(clip.speed.toDouble()) / ln(4.0)).toFloat()) }
    val speed = 4.0.pow(v.toDouble()).toFloat()
    PanelScaffold("Speed", { vm.panel = Panel.NONE }) {
        if (vm.project.asset(clip.assetId)?.type == MediaType.IMAGE) { Text("Photos don't have a speed. Trim them to change their duration.", color = Palette.TextDim); return@PanelScaffold }
        LabeledSlider("Speed", v, -1f..1f, { "%.2f×".format(speed) }, { v = it }, { vm.setSpeed(speed) })
        ChipRow {
            listOf(0.25f, 0.5f, 0.75f, 1f, 1.5f, 2f, 3f, 4f).forEach { s ->
                FilterChip(selected = abs(clip.speed - s) < 0.01f, onClick = { v = (ln(s.toDouble()) / ln(4.0)).toFloat(); vm.setSpeed(s) }, label = { Text("${s}×") })
            }
        }
        Text("New duration ${secs(((clip.srcOutUs - clip.srcInUs) / speed).toLong())}. Pitch is preserved.", color = Palette.TextDim, style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
    }
}

private fun abs(f: Float) = kotlin.math.abs(f)

@UnstableApi
@Composable
fun VolumePanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    var vol by remember(clip.id) { mutableFloatStateOf(clip.volume) }
    var fin by remember(clip.id) { mutableFloatStateOf(clip.fadeInUs / 1_000_000f) }
    var fout by remember(clip.id) { mutableFloatStateOf(clip.fadeOutUs / 1_000_000f) }
    val maxFade = (clip.durationUs / 2_000_000f).coerceIn(0.1f, 10f)
    PanelScaffold("Volume & fades", { vm.panel = Panel.NONE }) {
        LabeledSlider("Volume", vol, 0f..2f, ::pct, { vol = it }, { vm.updateSelected { c -> c.copy(volume = vol) } })
        LabeledSlider("Fade in", fin, 0f..maxFade, { "%.1fs".format(it) }, { fin = it }, { vm.updateSelected { c -> c.copy(fadeInUs = (fin * 1_000_000).toLong()) } })
        LabeledSlider("Fade out", fout, 0f..maxFade, { "%.1fs".format(it) }, { fout = it }, { vm.updateSelected { c -> c.copy(fadeOutUs = (fout * 1_000_000).toLong()) } })
        ChipRow {
            FilterChip(selected = clip.volume == 0f, onClick = { vol = if (clip.volume == 0f) 1f else 0f; vm.updateSelected { c -> c.copy(volume = vol) } }, label = { Text(if (clip.volume == 0f) "Unmute" else "Mute") })
        }
    }
}

@UnstableApi
@Composable
fun AdjustPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    var a by remember(clip.id) { mutableStateOf(clip.adjust) }
    val commit = { vm.updateSelected { c -> c.copy(adjust = a) } }
    PanelScaffold("Adjust", { vm.panel = Panel.NONE }, actions = {
        androidx.compose.material3.TextButton(onClick = { a = Adjust(); commit() }) { Text("Reset") }
        androidx.compose.material3.TextButton(onClick = { vm.applyAdjustToAll(a) }) { Text("Apply to all") }
    }) {
        LabeledSlider("Brightness", a.brightness, -1f..1f, ::signed, { a = a.copy(brightness = it) }, commit)
        LabeledSlider("Contrast", a.contrast, -1f..1f, ::signed, { a = a.copy(contrast = it) }, commit)
        LabeledSlider("Saturation", a.saturation, -1f..1f, ::signed, { a = a.copy(saturation = it) }, commit)
        LabeledSlider("Warmth", a.warmth, -1f..1f, ::signed, { a = a.copy(warmth = it) }, commit)
        LabeledSlider("Tint", a.tint, -1f..1f, ::signed, { a = a.copy(tint = it) }, commit)
        LabeledSlider("Hue", a.hue, -180f..180f, { "${it.roundToInt()}°" }, { a = a.copy(hue = it) }, commit)
        LabeledSlider("Sharpen", a.sharpen, 0f..1f, ::pct, { a = a.copy(sharpen = it) }, commit)
        LabeledSlider("Vignette", a.vignette, 0f..1f, ::pct, { a = a.copy(vignette = it) }, commit)
    }
}

@UnstableApi
@Composable
fun FilterPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    var intensity by remember(clip.id) { mutableFloatStateOf(clip.filter?.intensity ?: 1f) }
    PanelScaffold("Filters", { vm.panel = Panel.NONE }, actions = {
        androidx.compose.material3.TextButton(onClick = { vm.applyFilterToAll(clip.filter) }) { Text("Apply to all") }
    }) {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 8.dp)) {
            item { FilterTile("None", null, clip.filter == null) { vm.updateSelected { it.copy(filter = null) } } }
            items(Filters.all) { def ->
                FilterTile(def.name, def, clip.filter?.id == def.id) { vm.updateSelected { it.copy(filter = FilterSetting(def.id, intensity)) } }
            }
        }
        if (clip.filter != null) {
            LabeledSlider("Intensity", intensity, 0f..1f, ::pct, { intensity = it }, { vm.updateSelected { c -> c.copy(filter = c.filter?.copy(intensity = intensity)) } })
        }
    }
}

private val sampleColors = listOf(0xFF3B6EA8.toInt(), 0xFFE0A46A.toInt(), 0xFF5E8C4A.toInt(), 0xFFD8D2C8.toInt(), 0xFF2A2A2A.toInt())

@Composable
private fun FilterTile(name: String, def: com.framenova.app.engine.FilterDef?, selected: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(64.dp).clickable(onClick = onClick)) {
        val colors = sampleColors.map { c -> Color(if (def == null) c else Filters.applyArgb(def, c)) }
        Box(
            Modifier.size(56.dp).clip(RoundedCornerShape(10.dp)).background(Brush.linearGradient(colors))
                .border(BorderStroke(2.dp, if (selected) Palette.Accent else Color.Transparent), RoundedCornerShape(10.dp))
        )
        Text(name, fontSize = 11.sp, maxLines = 1, color = if (selected) Palette.Accent else Palette.Text)
    }
}

@UnstableApi
@Composable
fun CropPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val asset = vm.project.asset(clip.assetId) ?: return
    var crop by remember(clip.id) { mutableStateOf(clip.crop) }
    val commit = { vm.updateSelected { c -> c.copy(crop = crop) } }
    PanelScaffold("Crop", { vm.panel = Panel.NONE }, actions = {
        androidx.compose.material3.TextButton(onClick = { crop = CropRect(); commit() }) { Text("Reset") }
    }) {
        ChipRow {
            listOf("Original" to 0f, "1:1" to 1f, "16:9" to 16f / 9, "9:16" to 9f / 16, "4:5" to 0.8f, "4:3" to 4f / 3, "21:9" to 21f / 9).forEach { (label, ratio) ->
                FilterChip(selected = false, onClick = {
                    crop = if (ratio == 0f) CropRect() else {
                        val src = asset.width.toFloat() / asset.height
                        if (src > ratio) { val keep = ratio / src; CropRect(left = (1 - keep) / 2, right = (1 - keep) / 2) }
                        else { val keep = src / ratio; CropRect(top = (1 - keep) / 2, bottom = (1 - keep) / 2) }
                    }
                    commit()
                }, label = { Text(label) })
            }
        }
        LabeledSlider("Left", crop.left, 0f..0.45f, ::pct, { crop = crop.copy(left = it) }, commit)
        LabeledSlider("Right", crop.right, 0f..0.45f, ::pct, { crop = crop.copy(right = it) }, commit)
        LabeledSlider("Top", crop.top, 0f..0.45f, ::pct, { crop = crop.copy(top = it) }, commit)
        LabeledSlider("Bottom", crop.bottom, 0f..0.45f, ::pct, { crop = crop.copy(bottom = it) }, commit)
    }
}

@UnstableApi
@Composable
fun TransformPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val t = clip.transformAt(vm.playheadUs)
    val frame = vm.frameUs
    fun live(nt: Transform) = vm.liveSelected { it.withTransformAt(vm.playheadUs, nt, frame) }
    val asset = vm.project.asset(clip.assetId)
    PanelScaffold("Position & size", { vm.panel = Panel.NONE }) {
        ChipRow {
            OutlinedButton(onClick = { vm.updateSelected { it.withTransformAt(vm.playheadUs, t.copy(scale = 1f, cx = 0.5f, cy = 0.5f), frame) } }) { Text("Fit") }
            if (asset != null && asset.width > 0) OutlinedButton(onClick = {
                val (cw, ch) = com.framenova.app.engine.LayerMath.croppedSize(asset.width, asset.height, clip.crop)
                val cs = vm.project.canvas.size
                val fit = minOf(cs.width / cw, cs.height / ch)
                val fill = maxOf(cs.width / cw, cs.height / ch)
                vm.updateSelected { it.withTransformAt(vm.playheadUs, t.copy(scale = fill / fit, cx = 0.5f, cy = 0.5f), frame) }
            }) { Text("Fill") }
            OutlinedButton(onClick = { vm.updateSelected { it.withTransformAt(vm.playheadUs, t.copy(rotation = ((t.rotation / 90f).roundToInt() + 1) * 90f % 360f), frame) } }) { Text("Rotate 90°") }
            if (!clip.isText) {
                OutlinedButton(onClick = { vm.updateSelected { it.copy(flipH = !it.flipH) } }) { Text("Flip ↔") }
                OutlinedButton(onClick = { vm.updateSelected { it.copy(flipV = !it.flipV) } }) { Text("Flip ↕") }
            }
            OutlinedButton(onClick = { vm.updateSelected { it.copy(transform = Transform(), keyframes = emptyList()) } }) { Text("Reset") }
        }
        LabeledSlider("Scale", t.scale, 0.05f..4f, ::pct, { live(t.copy(scale = it)) }, vm::endGesture)
        LabeledSlider("Rotation", t.rotation, -180f..180f, { "${it.roundToInt()}°" }, { live(t.copy(rotation = it)) }, vm::endGesture)
        LabeledSlider("Opacity", t.opacity, 0f..1f, ::pct, { live(t.copy(opacity = it)) }, vm::endGesture)
        LabeledSlider("X", t.cx, -0.5f..1.5f, ::pct, { live(t.copy(cx = it)) }, vm::endGesture)
        LabeledSlider("Y", t.cy, -0.5f..1.5f, ::pct, { live(t.copy(cy = it)) }, vm::endGesture)
        if (clip.keyframes.isNotEmpty()) Text("Keyframed: changes apply to the keyframe at the playhead.", color = Palette.TextDim, style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
    }
}

@UnstableApi
@Composable
fun TransitionPanel(vm: EditorViewModel) {
    val id = vm.transitionTargetId ?: return
    val main = vm.project.mainTrack
    val index = main.clips.indexOfFirst { it.id == id }
    if (index <= 0) return
    val clip = main.clips[index]
    val maxD = (minOf(main.clips[index - 1].durationUs, clip.durationUs) / 2_000_000f).coerceAtLeast(0.1f)
    var dur by remember(id) { mutableFloatStateOf((clip.transitionIn?.durationUs ?: 500_000L) / 1_000_000f) }
    val current = clip.transitionIn
    PanelScaffold("Transition", { vm.panel = Panel.NONE }, actions = {
        androidx.compose.material3.TextButton(onClick = { vm.setTransitionForAll(current) }) { Text("Apply to all") }
    }) {
        ChipRow {
            FilterChip(selected = current == null, onClick = { vm.setTransition(id, null) }, label = { Text("None") })
            TransitionType.entries.forEach { type ->
                FilterChip(
                    selected = current?.type == type,
                    onClick = { vm.setTransition(id, Transition(type, (dur.coerceAtMost(maxD) * 1_000_000).toLong())) },
                    label = { Text(type.label) },
                )
            }
        }
        if (current != null) LabeledSlider("Duration", dur.coerceAtMost(maxD), 0.1f..maxD, { "%.1fs".format(it) }, { dur = it }, {
            vm.setTransition(id, current.copy(durationUs = (dur * 1_000_000).toLong()))
        })
    }
}

@UnstableApi
@Composable
fun LayoutPanel(vm: EditorViewModel) {
    var gap by remember { mutableFloatStateOf(0f) }
    val count = vm.project.clipsAt(vm.playheadUs, setOf(TrackKind.MAIN, TrackKind.OVERLAY)).size
    val aspect = vm.project.canvas.size.aspect
    PanelScaffold("Layout", { vm.panel = Panel.NONE }) {
        Text(
            if (count <= 1) "Add overlays (picture-in-picture) at the playhead, then pick a layout to arrange them in one frame."
            else "Arranges the $count clips showing at the playhead. Drag on the preview to fine-tune each one.",
            color = Palette.TextDim, style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 8.dp)) {
            items(LayoutPresets.all) { preset ->
                val match = preset.cells.size == count || preset.id == "fit"
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(72.dp).clickable { vm.applyLayout(preset, gap) }) {
                    Canvas(Modifier.width(64.dp).height((64 / aspect.coerceIn(0.5f, 2.2f)).dp.coerceAtMost(72.dp))) {
                        drawRect(Palette.Surface3)
                        preset.cells.forEachIndexed { i, c ->
                            val inset = 2f
                            drawRect(
                                (if (match) Palette.Accent else Palette.TextDim).copy(alpha = 0.35f + 0.15f * (i % 3)),
                                Offset(c.x * size.width + inset, c.y * size.height + inset),
                                Size(c.w * size.width - 2 * inset, c.h * size.height - 2 * inset),
                            )
                        }
                        drawRect(Color.White.copy(alpha = 0.3f), style = Stroke(1f))
                    }
                    Text(preset.label, fontSize = 10.sp, maxLines = 1, color = if (match) Palette.Text else Palette.TextDim)
                }
            }
        }
        LabeledSlider("Spacing", gap, 0f..0.05f, { "${(it * 1000).roundToInt() / 10f}%" }, { gap = it })
    }
}

@UnstableApi
@Composable
fun CanvasPanel(vm: EditorViewModel) {
    val c = vm.project.canvas
    var blur by remember { mutableFloatStateOf(c.background.blur) }
    PanelScaffold("Canvas", { vm.panel = Panel.NONE }) {
        Text("Ratio", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow { AspectPreset.entries.forEach { a -> FilterChip(selected = c.aspect == a, onClick = { vm.updateCanvas { it.copy(aspect = a) } }, label = { Text(a.label) }) } }
        Text("Resolution", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow { ResolutionTier.entries.forEach { r -> FilterChip(selected = c.tier == r, onClick = { vm.updateCanvas { it.copy(tier = r) } }, label = { Text(r.label) }) } }
        Text("Frame rate", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow { listOf(24, 25, 30, 50, 60).forEach { f -> FilterChip(selected = c.fps == f, onClick = { vm.updateCanvas { it.copy(fps = f) } }, label = { Text("$f fps") }) } }
        Text("Background", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow {
            FilterChip(selected = c.background.mode == BackgroundMode.COLOR, onClick = { vm.updateCanvas { it.copy(background = it.background.copy(mode = BackgroundMode.COLOR)) } }, label = { Text("Color") })
            FilterChip(selected = c.background.mode == BackgroundMode.BLUR, onClick = { vm.updateCanvas { it.copy(background = it.background.copy(mode = BackgroundMode.BLUR)) } }, label = { Text("Blur") })
        }
        if (c.background.mode == BackgroundMode.COLOR) ColorRow(textColors, c.background.color, { col -> vm.updateCanvas { it.copy(background = it.background.copy(color = col)) } })
        else LabeledSlider("Blur", blur, 0f..1f, ::pct, { blur = it }, { vm.updateCanvas { it.copy(background = it.background.copy(blur = blur)) } })
        Text("${c.size.width} × ${c.size.height}", color = Palette.TextDim, fontSize = 12.sp)
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Text

@UnstableApi
@Composable
fun TextEditPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val style = clip.text ?: return
    PanelScaffold("Text", { vm.endGesture(); vm.panel = Panel.NONE }) {
        OutlinedTextField(
            value = style.text,
            onValueChange = { v -> vm.liveText { it.copy(text = v) } },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
            maxLines = 5,
            label = { Text("Text") },
        )
        Spacer(Modifier.height(8.dp))
        ChipRow {
            listOf("Top" to 0.14f, "Center" to 0.5f, "Bottom" to 0.86f).forEach { (label, y) ->
                OutlinedButton(onClick = { vm.updateSelected { c -> c.withTransformAt(vm.playheadUs, c.transformAt(vm.playheadUs).copy(cy = y, cx = 0.5f), vm.frameUs) } }) { Text(label) }
            }
            OutlinedButton(onClick = { vm.panel = Panel.TEXT_FONT }) { Text("Font") }
            OutlinedButton(onClick = { vm.panel = Panel.TEXT_STYLE }) { Text("Style") }
            OutlinedButton(onClick = { vm.panel = Panel.TEXT_ANIM }) { Text("Animation") }
        }
    }
}

@UnstableApi
@Composable
fun FontPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val style = clip.text ?: return
    val scope = rememberCoroutineScope()
    val progress = remember { mutableStateMapOf<String, Float>() }
    var refresh by remember { mutableIntStateOf(0) }
    PanelScaffold("Font", { vm.panel = Panel.NONE }) {
        @Suppress("UNUSED_EXPRESSION") refresh
        FontGroup.entries.forEach { group ->
            Text(when (group) { FontGroup.SYSTEM -> "System"; FontGroup.LATIN -> "English"; FontGroup.CHINESE -> "繁體中文 (download once)" }, color = Palette.TextDim, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
            FontCatalog.all.filter { it.group == group }.forEach { def ->
                val available = FontManager.isAvailable(def.id)
                val p = progress[def.id]
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
                        .background(if (style.fontId == def.id) Palette.AccentSoft else Color.Transparent)
                        .clickable {
                            if (available) vm.updateText { it.copy(fontId = def.id) }
                            else if (p == null) scope.launch {
                                progress[def.id] = 0f
                                try {
                                    FontManager.download(def.id) { v -> progress[def.id] = v }
                                    vm.updateText { it.copy(fontId = def.id) }
                                } catch (e: Exception) {
                                    vm.message = "Font download failed: ${e.message}"
                                } finally { progress.remove(def.id); refresh++ }
                            }
                        }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val family = remember(def.id, available) { if (available) FontFamily(FontManager.typeface(def.id)) else FontFamily.Default }
                    Text(def.name, fontFamily = family, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    Text(def.sample, fontFamily = family, fontSize = 16.sp, color = Palette.TextDim)
                    Spacer(Modifier.width(8.dp))
                    when {
                        p != null -> CircularProgressIndicator(progress = { p }, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        !available -> Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${def.sizeMb} MB", fontSize = 11.sp, color = Palette.TextDim)
                            Icon(Icons.Default.Download, null, tint = Palette.TextDim, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
        }
    }
}

@UnstableApi
@Composable
fun TextStylePanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val s = clip.text ?: return
    PanelScaffold("Style", { vm.endGesture(); vm.panel = Panel.NONE }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconToggleButton(checked = s.bold, onCheckedChange = { b -> vm.updateText { it.copy(bold = b) } }) { Icon(Icons.Default.FormatBold, "Bold", tint = if (s.bold) Palette.Accent else Palette.TextDim) }
            IconToggleButton(checked = s.italic, onCheckedChange = { b -> vm.updateText { it.copy(italic = b) } }) { Icon(Icons.Default.FormatItalic, "Italic", tint = if (s.italic) Palette.Accent else Palette.TextDim) }
            Spacer(Modifier.width(12.dp))
            listOf(TextAlign.LEFT to Icons.AutoMirrored.Filled.FormatAlignLeft, TextAlign.CENTER to Icons.Default.FormatAlignCenter, TextAlign.RIGHT to Icons.AutoMirrored.Filled.FormatAlignRight).forEach { (a, icon) ->
                IconButton(onClick = { vm.updateText { it.copy(align = a) } }) { Icon(icon, a.name, tint = if (s.align == a) Palette.Accent else Palette.TextDim) }
            }
            Spacer(Modifier.weight(1f))
            Text("Shadow", fontSize = 12.sp, color = Palette.TextDim)
            Switch(checked = s.shadow, onCheckedChange = { b -> vm.updateText { it.copy(shadow = b) } })
        }
        LabeledSlider("Size", s.size, 0.02f..0.35f, { "${(it * 1000).roundToInt() / 10f}" }, { v -> vm.liveText { it.copy(size = v) } }, vm::endGesture)
        Text("Color", color = Palette.TextDim, fontSize = 12.sp)
        ColorRow(textColors, s.color, { c -> vm.updateText { it.copy(color = c) } })
        LabeledSlider("Outline", s.strokeWidth, 0f..0.25f, ::pct, { v -> vm.liveText { it.copy(strokeWidth = v) } }, vm::endGesture)
        if (s.strokeWidth > 0f) ColorRow(textColors, s.strokeColor, { c -> vm.updateText { it.copy(strokeColor = c) } })
        Text("Background", color = Palette.TextDim, fontSize = 12.sp)
        ColorRow(bgColors, s.backgroundColor, { c -> vm.updateText { it.copy(backgroundColor = c) } }, allowNone = true)
        LabeledSlider("Letters", s.letterSpacing, -0.05f..0.5f, { "%.2f".format(it) }, { v -> vm.liveText { it.copy(letterSpacing = v) } }, vm::endGesture)
        LabeledSlider("Lines", s.lineSpacing, 0.8f..2f, { "%.1f".format(it) }, { v -> vm.liveText { it.copy(lineSpacing = v) } }, vm::endGesture)
    }
}

@UnstableApi
@Composable
fun TextAnimPanel(vm: EditorViewModel) {
    val clip = vm.selectedClip ?: return
    val s = clip.text ?: return
    var dur by remember(clip.id) { mutableFloatStateOf(s.animDurationUs / 1_000_000f) }
    PanelScaffold("Animation", { vm.panel = Panel.NONE }) {
        Text("In", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow { TextAnim.entries.forEach { a -> FilterChip(selected = s.animIn == a, onClick = { vm.updateText { it.copy(animIn = a) } }, label = { Text(a.label) }) } }
        Text("Out", color = Palette.TextDim, fontSize = 12.sp)
        ChipRow { TextAnim.entries.filter { it != TextAnim.TYPEWRITER }.forEach { a -> FilterChip(selected = s.animOut == a, onClick = { vm.updateText { it.copy(animOut = a) } }, label = { Text(a.label) }) } }
        LabeledSlider("Duration", dur, 0.1f..2f, { "%.1fs".format(it) }, { dur = it }, { vm.updateText { it.copy(animDurationUs = (dur * 1_000_000).toLong()) } })
    }
}

private val emojis = listOf(
    "⭐", "✨", "🔥", "❤️", "💖", "😂", "😍", "🥰", "😎", "🤩", "😭", "🥺", "👍", "👏", "🙌", "🎉", "🎂", "🎵", "🎬", "📸",
    "🌸", "🌈", "☀️", "🌙", "⚡", "💯", "✅", "❌", "➡️", "⬅️", "⬆️", "⬇️", "💬", "💭", "🐶", "🐱", "🍜", "☕", "✈️", "🏝️",
)

@UnstableApi
@Composable
fun StickerPanel(vm: EditorViewModel) {
    PanelScaffold("Stickers", { vm.panel = Panel.NONE }) {
        ChipRow {
            emojis.forEach { e ->
                Box(Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(Palette.Surface2).clickable { vm.addSticker(e) }, contentAlignment = Alignment.Center) {
                    Text(e, fontSize = 26.sp)
                }
            }
        }
        Text("Tip: use Overlay to add your own PNG stickers with transparency.", color = Palette.TextDim, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp))
    }
}

@UnstableApi
@Composable
fun VoiceoverPanel(vm: EditorViewModel, requestPermission: () -> Unit, hasPermission: Boolean) {
    var level by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(vm.recording) {
        while (vm.recording) { level = (vm.recorderLevel / 20000f).coerceIn(0f, 1f); delay(60) }
        level = 0f
    }
    PanelScaffold("Voiceover", { if (vm.recording) vm.stopRecording(); vm.panel = Panel.NONE }) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
            Button(
                onClick = { if (!hasPermission) requestPermission() else if (vm.recording) vm.stopRecording() else vm.startRecording() },
                shape = CircleShape,
                modifier = Modifier.size(72.dp),
                colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = if (vm.recording) Palette.Danger else Palette.Accent),
            ) { Icon(if (vm.recording) Icons.Default.Stop else Icons.Default.FiberManualRecord, null, modifier = Modifier.size(32.dp)) }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(if (vm.recording) "Recording… ${formatTime(vm.playheadUs - vm.recordingStartUs)}" else "Records from the playhead while the video plays.", color = Palette.TextDim)
                Box(Modifier.padding(top = 8.dp).fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(Palette.Surface3)) {
                    Box(Modifier.fillMaxWidth(level).height(8.dp).background(Palette.Teal))
                }
            }
        }
    }
}

@Composable
fun EmptyPanelBox(modifier: Modifier = Modifier) = Box(modifier.fillMaxSize())
