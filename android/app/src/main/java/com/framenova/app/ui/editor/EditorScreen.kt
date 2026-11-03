package com.framenova.app.ui.editor

import android.Manifest
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Snackbar
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.util.UnstableApi
import com.framenova.app.engine.ExportManager
import com.framenova.app.engine.ExportQuality
import com.framenova.app.engine.ExportSettings
import com.framenova.app.engine.ExportState
import com.framenova.app.model.ClipCategory
import com.framenova.app.model.MediaType
import com.framenova.app.model.ResolutionTier
import com.framenova.app.model.FRAME_RATES
import com.framenova.app.model.TextRole
import com.framenova.app.model.TrackKind
import com.framenova.app.ui.media.LibraryKind
import com.framenova.app.ui.media.MediaLibrary
import com.framenova.app.ui.theme.Palette
import kotlinx.coroutines.delay

@UnstableApi
@Composable
fun EditorRoute(projectId: String, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as Application
    // The editor owns its view model: leaving the editor saves, releases the player and clears it.
    val store = remember(projectId) { ViewModelStore() }
    val owner = remember(store) { object : ViewModelStoreOwner { override val viewModelStore = store } }
    DisposableEffect(store) { onDispose { store.clear() } }
    val vm: EditorViewModel = viewModel(viewModelStoreOwner = owner, key = projectId, factory = EditorViewModel.Factory(app, projectId))
    EditorScreen(vm, onClose)
}

private data class LibraryRequest(val target: ImportTarget)

private data class Tool(val label: String, val icon: ImageVector, val enabled: Boolean = true, val onClick: () -> Unit)

@UnstableApi
@Composable
fun EditorScreen(vm: EditorViewModel, onClose: () -> Unit) {
    val context = LocalContext.current
    var renaming by remember { mutableStateOf(false) }
    var micGranted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) }
    var library by remember { mutableStateOf<LibraryRequest?>(null) }
    val pickSubs = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) vm.importSubtitles(uri) }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { micGranted = it }
    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val exportState by ExportManager.state.collectAsState()

    fun pickMedia(target: ImportTarget) {
        library = LibraryRequest(target)
    }

    val tools: List<Tool> = run {
        val clip = vm.selectedClip
        val category = vm.selectedCategory
        val track = vm.selectedTrack
        when {
            clip == null && vm.selectedGapUs != null -> listOf(
                Tool("Delete gap", Icons.Default.Delete) { vm.deleteGap() },
                Tool("Media", Icons.Default.AddPhotoAlternate) { pickMedia(ImportTarget.MAIN) },
            )
            clip == null -> listOf(
                Tool("Media", Icons.Default.AddPhotoAlternate) { pickMedia(ImportTarget.MAIN) },
                Tool("Add layer", Icons.Default.Layers) { pickMedia(ImportTarget.OVERLAY) },
                Tool("Text", Icons.Default.TextFields) { vm.addText(TextRole.TITLE) },
                Tool("Subtitle", Icons.Default.Subtitles) { vm.addText(TextRole.SUBTITLE) },
                Tool("Import SRT/LRC", Icons.Default.Subtitles) { pickSubs.launch(arrayOf("*/*")) },
                Tool("Stickers", Icons.Default.EmojiEmotions) { vm.panel = Panel.STICKER },
                Tool("Audio", Icons.Default.LibraryMusic) { pickMedia(ImportTarget.AUDIO) },
                Tool("Voiceover", Icons.Default.Mic) { vm.panel = Panel.VOICEOVER },
                Tool("Layout", Icons.Default.GridView) { vm.panel = Panel.LAYOUT },
                Tool("Ratio", Icons.Default.AspectRatio) { vm.panel = Panel.CANVAS },
                Tool("Split", Icons.Default.ContentCut) { vm.split() },
                Tool("Freeze", Icons.Default.AcUnit) { vm.freezeFrame() },
            )
            category == ClipCategory.TEXT -> listOf(
                Tool("Edit", Icons.Default.Edit) { vm.panel = Panel.TEXT_EDIT },
                Tool("Font", Icons.Default.FontDownload) { vm.panel = Panel.TEXT_FONT },
                Tool("Style", Icons.Default.FormatColorText) { vm.panel = Panel.TEXT_STYLE },
                Tool("Animation", Icons.Default.Animation) { vm.panel = Panel.TEXT_ANIM },
                Tool("Position", Icons.Default.OpenWith) { vm.panel = Panel.TRANSFORM },
                Tool("Keyframe", Icons.Default.Diamond) { vm.toggleKeyframe() },
                Tool("Split", Icons.Default.ContentCut) { vm.split() },
                Tool("Duplicate", Icons.Default.ContentCopy) { vm.duplicateSelected() },
                Tool("Delete", Icons.Default.Delete) { vm.deleteSelected() },
            )
            category == ClipCategory.AUDIO -> listOf(
                Tool("Volume", Icons.AutoMirrored.Filled.VolumeUp) { vm.panel = Panel.VOLUME },
                Tool("Speed", Icons.Default.Speed) { vm.panel = Panel.SPEED },
                Tool("Split", Icons.Default.ContentCut) { vm.split() },
                Tool("Duplicate", Icons.Default.ContentCopy) { vm.duplicateSelected() },
                Tool("Save audio", Icons.Default.SaveAlt) { vm.saveAudio() },
                Tool("Delete", Icons.Default.Delete) { vm.deleteSelected() },
            )
            else -> {
                val asset = vm.project.asset(clip.assetId)
                val isVideo = asset?.type == MediaType.VIDEO
                buildList {
                    add(Tool("Split", Icons.Default.ContentCut) { vm.split() })
                    if (track?.kind == TrackKind.MAIN) add(Tool("To new layer", Icons.Default.Layers) { vm.toOverlay() })
                    if (isVideo) add(Tool("Speed", Icons.Default.Speed) { vm.panel = Panel.SPEED })
                    if (isVideo) add(Tool("Volume", Icons.AutoMirrored.Filled.VolumeUp) { vm.panel = Panel.VOLUME })
                    add(Tool("Position", Icons.Default.OpenWith) { vm.panel = Panel.TRANSFORM })
                    add(Tool("Layout", Icons.Default.GridView) { vm.panel = Panel.LAYOUT })
                    add(Tool("Keyframe", Icons.Default.Diamond) { vm.toggleKeyframe() })
                    add(Tool("Adjust", Icons.Default.Tune) { vm.panel = Panel.ADJUST })
                    add(Tool("Filters", Icons.Default.PhotoFilter) { vm.panel = Panel.FILTER })
                    add(Tool("Crop", Icons.Default.Crop) { vm.panel = Panel.CROP })
                    if (track?.kind == TrackKind.OVERLAY) add(Tool("To main", Icons.Default.VerticalAlignBottom) { vm.toMain() })
                    if (isVideo) add(Tool("Freeze", Icons.Default.AcUnit) { vm.freezeFrame() })
                    if (isVideo && asset?.hasAudio == true) add(Tool("Extract audio", Icons.Default.MusicNote) { vm.extractAudio() })
                    if (isVideo && asset?.hasAudio == true) add(Tool("Save audio", Icons.Default.SaveAlt) { vm.saveAudio() })
                    add(Tool("Replace", Icons.Default.SwapHoriz) { pickMedia(ImportTarget.REPLACE) })
                    add(Tool("Duplicate", Icons.Default.ContentCopy) { vm.duplicateSelected() })
                    add(Tool("Delete", Icons.Default.Delete) { vm.deleteSelected() })
                }
            }
        }
    }

    val panelContent: @Composable () -> Unit = {
        when (vm.panel) {
            Panel.SPEED -> SpeedPanel(vm)
            Panel.VOLUME -> VolumePanel(vm)
            Panel.ADJUST -> AdjustPanel(vm)
            Panel.FILTER -> FilterPanel(vm)
            Panel.CROP -> CropPanel(vm)
            Panel.TRANSFORM -> TransformPanel(vm)
            Panel.TRANSITION -> TransitionPanel(vm)
            Panel.LAYOUT -> LayoutPanel(vm)
            Panel.CANVAS -> CanvasPanel(vm)
            Panel.TEXT_EDIT -> TextEditPanel(vm)
            Panel.TEXT_FONT -> FontPanel(vm)
            Panel.TEXT_STYLE -> TextStylePanel(vm)
            Panel.TEXT_ANIM -> TextAnimPanel(vm)
            Panel.STICKER -> StickerPanel(vm)
            Panel.VOICEOVER -> VoiceoverPanel(vm, { micPermission.launch(Manifest.permission.RECORD_AUDIO) }, micGranted)
            Panel.EXPORT, Panel.NONE -> {}
        }
    }
    // A panel that needs a selection closes when the selection goes away.
    LaunchedEffect(vm.selectedId) {
        val needsClip = vm.panel in setOf(Panel.SPEED, Panel.VOLUME, Panel.ADJUST, Panel.FILTER, Panel.CROP, Panel.TRANSFORM, Panel.TEXT_EDIT, Panel.TEXT_FONT, Panel.TEXT_STYLE, Panel.TEXT_ANIM)
        if (needsClip && vm.selectedClip == null) vm.panel = Panel.NONE
    }
    val showPanel = vm.panel != Panel.NONE && vm.panel != Panel.EXPORT

    // One preview for every layout: moving it between layouts keeps its view, where a new one starts out blank.
    val preview = remember(vm) { movableContentOf { m: Modifier -> PreviewPane(vm, m) } }

    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.Bg)) {
        val landscape = maxWidth > maxHeight
        val screenH = maxHeight
        val timeline: @Composable (Modifier) -> Unit = { m ->
            TimelineView(
                project = vm.project, playheadUs = vm.playheadUs, pxPerSecond = vm.pxPerSecond, selectedId = vm.selectedId,
                selectedGapUs = vm.selectedGapUs, media = vm.media,
                onScrub = vm::scrubTo, onZoom = { vm.pxPerSecond = it },
                onSelect = { id ->
                    vm.selectedId = id
                    if (id != null) vm.selectedGapUs = null
                    if (id == null && vm.panel != Panel.CANVAS && vm.panel != Panel.LAYOUT) vm.panel = Panel.NONE
                },
                onGapTap = { t ->
                    vm.selectedGapUs = t
                    if (t != null) { vm.selectedId = null; if (vm.panel != Panel.CANVAS && vm.panel != Panel.LAYOUT) vm.panel = Panel.NONE }
                },
                onMove = vm::move, onTrim = vm::trim,
                onTransitionTap = { id -> vm.transitionTargetId = id; vm.selectedId = null; vm.panel = Panel.TRANSITION },
                onClipDoubleTap = { id -> vm.openTextEditor(id) },
                onTrackLockTap = { t -> vm.toggleTrackLock(t.id) },
                onTrackHeaderTap = { t -> if (t.kind == TrackKind.TEXT) Unit else if (t.kind == TrackKind.OVERLAY) vm.toggleTrackHidden(t.id) else vm.toggleTrackMute(t.id) },
                modifier = m,
            )
        }
        Column(Modifier.fillMaxSize()) {
            TopBar(vm, onClose, onRename = { renaming = true }, onExport = {
                if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
                vm.panel = Panel.EXPORT
            })
            // While text is edited (words, font, style, animation, stickers), the preview takes the whole space above the
            // panel, so the result is easy to see.
            val textFocus = vm.panel in setOf(Panel.TEXT_EDIT, Panel.TEXT_FONT, Panel.TEXT_STYLE, Panel.TEXT_ANIM, Panel.STICKER)
            if (vm.fullscreen) {
                preview(Modifier.fillMaxWidth().weight(1f))
                TransportBar(vm)
            } else if (textFocus && landscape) {
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    preview(Modifier.weight(1f).fillMaxHeight())
                    Box(Modifier.width(380.dp).fillMaxHeight().background(Palette.Surface)) { panelContent() }
                }
            } else if (textFocus) {
                preview(Modifier.fillMaxWidth().weight(1f))
                Box(Modifier.fillMaxWidth().heightIn(min = 76.dp, max = screenH * 0.42f)) { panelContent() }
            } else if (landscape) {
                Row(Modifier.fillMaxWidth().weight(0.56f)) {
                    preview(Modifier.weight(1f).fillMaxHeight())
                    Box(Modifier.width(380.dp).fillMaxHeight().background(Palette.Surface)) {
                        if (showPanel) panelContent() else ToolGrid(tools)
                    }
                }
                TransportBar(vm)
                timeline(Modifier.fillMaxWidth().weight(0.44f))
            } else {
                preview(Modifier.fillMaxWidth().weight(1f))
                TransportBar(vm)
                timeline(Modifier.fillMaxWidth().height((screenH * 0.3f).coerceIn(180.dp, 320.dp)))
                Box(Modifier.fillMaxWidth().heightIn(min = 76.dp, max = screenH * 0.34f)) {
                    if (showPanel) panelContent() else ToolRow(tools)
                }
            }
        }

        vm.message?.let { msg ->
            LaunchedEffect(msg) { delay(3500); if (vm.message == msg) vm.message = null }
            Snackbar(Modifier.align(Alignment.BottomCenter).padding(16.dp), action = { TextButton(onClick = { vm.message = null }) { Text("OK") } }) { Text(msg) }
        }
        vm.busy?.let { label ->
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(); Spacer(Modifier.height(12.dp)); Text(label) }
            }
        }
    }

    if (vm.panel == Panel.EXPORT) ExportDialog(vm, onDismiss = { vm.panel = Panel.NONE })
    when (val s = exportState) {
        is ExportState.Running -> ExportProgressDialog(s)
        is ExportState.Done -> AlertDialog(
            onDismissRequest = { ExportManager.dismiss() },
            title = { Text(if (s.isAudio) "Audio saved" else "Video saved") },
            text = { Text("${s.displayName}\n${"%.1f".format(s.bytes / 1_000_000f)} MB · ${if (s.isAudio) "Music" else "Movies"}/FrameNova") },
            confirmButton = {
                TextButton(onClick = {
                    val share = Intent(Intent.ACTION_SEND).setType(if (s.isAudio) "audio/mp4" else "video/mp4").putExtra(Intent.EXTRA_STREAM, s.uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    context.startActivity(Intent.createChooser(share, "Share"))
                }) { Text("Share") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(s.uri, if (s.isAudio) "audio/mp4" else "video/mp4").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    }) { Text("Open") }
                    TextButton(onClick = { ExportManager.dismiss() }) { Text("Done") }
                }
            },
        )
        is ExportState.Failed -> AlertDialog(
            onDismissRequest = { ExportManager.dismiss() },
            title = { Text("Export failed") },
            text = { Text(s.message) },
            confirmButton = { TextButton(onClick = { ExportManager.dismiss() }) { Text("OK") } },
        )
        ExportState.Idle -> {}
    }
    library?.let { req ->
        val audio = req.target == ImportTarget.AUDIO
        MediaLibrary(
            kind = if (audio) LibraryKind.AUDIO else LibraryKind.VISUAL,
            title = when (req.target) {
                ImportTarget.MAIN -> "Add videos and photos"
                ImportTarget.OVERLAY -> "Add as a layer"
                ImportTarget.AUDIO -> "Add audio"
                ImportTarget.REPLACE -> "Replace clip"
            },
            multiple = req.target != ImportTarget.REPLACE,
            onDismiss = { library = null },
        ) { uris -> library = null; vm.import(uris, req.target) }
    }
    if (renaming) RenameDialog(vm.project.name, onDismiss = { renaming = false }) { vm.rename(it); renaming = false }
}

@UnstableApi
@Composable
private fun TopBar(vm: EditorViewModel, onClose: () -> Unit, onRename: () -> Unit, onExport: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        Column(Modifier.weight(1f)) {
            Text(vm.project.name, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.clickable(onClick = onRename))
            val c = vm.project.canvas
            // Tapping the format toggles the ratio, resolution and frame rate settings.
            Row(Modifier.clip(RoundedCornerShape(6.dp)).clickable {
                vm.selectedId = null
                vm.panel = if (vm.panel == Panel.CANVAS) Panel.NONE else Panel.CANVAS
            }, verticalAlignment = Alignment.CenterVertically) {
                Text("${c.aspect.label} · ${c.tier.label} · ${c.fps} fps", color = Palette.Accent, fontSize = 11.sp)
                Icon(
                    if (vm.panel == Panel.CANVAS) Icons.Default.ArrowDropUp else Icons.Default.ArrowDropDown,
                    if (vm.panel == Panel.CANVAS) "Hide project format" else "Show project format",
                    tint = Palette.Accent, modifier = Modifier.size(16.dp),
                )
            }
        }
        IconButton(onClick = vm::undo, enabled = vm.canUndo) { Icon(Icons.AutoMirrored.Filled.Undo, "Undo") }
        IconButton(onClick = vm::redo, enabled = vm.canRedo) { Icon(Icons.AutoMirrored.Filled.Redo, "Redo") }
        Button(onClick = onExport, enabled = vm.project.durationUs > 0, shape = RoundedCornerShape(10.dp), modifier = Modifier.padding(end = 6.dp)) { Text("Export") }
    }
}

@UnstableApi
@Composable
private fun TransportBar(vm: EditorViewModel) {
    Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("${formatTime(vm.playheadUs, true, vm.project.canvas.fps)} / ${formatTime(vm.project.durationUs)}", fontSize = 12.sp, color = Palette.TextDim)
            vm.renderStatus?.let { Text(it, fontSize = 10.sp, color = Palette.Teal, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        IconButton(onClick = { vm.jumpTo(0) }) { Icon(Icons.Default.SkipPrevious, "Start") }
        IconButton(onClick = vm::togglePlay, enabled = vm.project.durationUs > 0) {
            Icon(if (vm.playing) Icons.Default.Pause else Icons.Default.PlayArrow, "Play", modifier = Modifier.size(32.dp))
        }
        IconButton(onClick = { vm.jumpTo(vm.project.durationUs) }) { Icon(Icons.Default.SkipNext, "End") }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = { vm.fullscreen = !vm.fullscreen }) { Icon(if (vm.fullscreen) Icons.Default.FullscreenExit else Icons.Default.Fullscreen, "Full screen") }
        }
    }
}

@Composable
private fun ToolRow(tools: List<Tool>) {
    LazyRow(Modifier.fillMaxWidth().background(Palette.Surface).padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        items(tools, key = { it.label }) { ToolButton(it) }
    }
}

@Composable
private fun ToolGrid(tools: List<Tool>) {
    LazyVerticalGrid(GridCells.Adaptive(84.dp), Modifier.fillMaxSize().padding(8.dp)) {
        items(tools, key = { it.label }) { ToolButton(it) }
    }
}

@Composable
private fun ToolButton(tool: Tool) {
    Column(
        Modifier.width(76.dp).clip(RoundedCornerShape(10.dp)).clickable(enabled = tool.enabled, onClick = tool.onClick).padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(tool.icon, tool.label, tint = if (tool.enabled) Palette.Text else Palette.TextDim)
        Text(tool.label, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (tool.enabled) Palette.Text else Palette.TextDim)
    }
}

@UnstableApi
@Composable
private fun ExportDialog(vm: EditorViewModel, onDismiss: () -> Unit) {
    val canvas = vm.project.canvas
    var tier by remember { mutableStateOf(canvas.tier) }
    var fps by remember { mutableStateOf(canvas.fps) }
    var hevc by remember { mutableStateOf(true) }
    var quality by remember { mutableStateOf(ExportQuality.HIGH) }
    val settings = ExportSettings(tier.longSide, fps, hevc, quality)
    val size = com.framenova.app.model.CanvasSettings.sizeFor(canvas.aspect, tier.longSide)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Export") },
        text = {
            Column {
                Text("Resolution", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { ResolutionTier.highToLow.forEach { r -> FilterChip(selected = tier == r, onClick = { tier = r }, label = { Text(r.label) }) } }
                Text("Frame rate", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { FRAME_RATES.forEach { f -> FilterChip(selected = fps == f, onClick = { fps = f }, label = { Text("$f") }) } }
                Text("Codec", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow {
                    FilterChip(selected = hevc, onClick = { hevc = true }, label = { Text("HEVC (smaller)") })
                    FilterChip(selected = !hevc, onClick = { hevc = false }, label = { Text("H.264 (compatible)") })
                }
                Text("Quality", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { ExportQuality.entries.forEach { q -> FilterChip(selected = quality == q, onClick = { quality = q }, label = { Text(q.label) }) } }
                Spacer(Modifier.height(8.dp))
                Text(
                    "${size.width} × ${size.height} · ${"%.0f".format(settings.bitrate(size.width, size.height) / 1_000_000f)} Mbps · about ${"%.0f".format(ExportManager.estimateBytes(vm.project, settings) / 1_000_000f)} MB",
                    color = Palette.TextDim, fontSize = 12.sp,
                )
                if (vm.project.assets.any { it.isHdr }) Text("HDR clips are converted to SDR.", color = Palette.TextDim, fontSize = 12.sp)
            }
        },
        confirmButton = { Button(onClick = { onDismiss(); vm.export(settings) }) { Text("Export") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@UnstableApi
@Composable
private fun ExportProgressDialog(s: ExportState.Running) {
    AlertDialog(
        onDismissRequest = {},
        title = { Text("Exporting…") },
        text = {
            Column {
                Text(s.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(12.dp))
                LinearProgressIndicator(progress = { s.progress / 100f }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(6.dp))
                Text("${s.progress}% · keeps running if you leave the app", color = Palette.TextDim, fontSize = 12.sp)
            }
        },
        confirmButton = { TextButton(onClick = { ExportManager.cancel() }) { Text("Cancel") } },
    )
}

@Composable
fun RenameDialog(initial: String, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename") },
        text = { OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onRename(name.trim()) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
