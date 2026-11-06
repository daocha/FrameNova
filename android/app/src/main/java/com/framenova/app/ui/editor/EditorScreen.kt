package com.framenova.app.ui.editor

import androidx.compose.ui.res.stringResource
import com.framenova.app.R
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
import kotlin.math.roundToInt
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.draw.shadow
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.gestures.detectTapGestures
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
    val shareTitle = stringResource(R.string.editor_share)

    fun pickMedia(target: ImportTarget) {
        library = LibraryRequest(target)
    }

    val tools: List<Tool> = run {
        val clip = vm.selectedClip
        val category = vm.selectedCategory
        val track = vm.selectedTrack
        when {
            clip == null && vm.selectedGapUs != null -> listOf(
                Tool(stringResource(R.string.tool_delete_gap), Icons.Default.Delete) { vm.deleteGap() },
                Tool(stringResource(R.string.tool_media), Icons.Default.AddPhotoAlternate) { pickMedia(ImportTarget.MAIN) },
            )
            clip == null -> listOf(
                Tool(stringResource(R.string.tool_media), Icons.Default.AddPhotoAlternate) { pickMedia(ImportTarget.MAIN) },
                Tool(stringResource(R.string.tool_add_layer), Icons.Default.Layers) { pickMedia(ImportTarget.OVERLAY) },
                Tool(stringResource(R.string.panel_text), Icons.Default.TextFields) { vm.addText(TextRole.TITLE) },
                Tool(stringResource(R.string.tool_subtitle), Icons.Default.Subtitles) { vm.addText(TextRole.SUBTITLE) },
                Tool(stringResource(R.string.tool_import_srt_lrc), Icons.Default.Subtitles) { pickSubs.launch(arrayOf("*/*")) },
                Tool(stringResource(R.string.panel_stickers), Icons.Default.EmojiEmotions) { vm.panel = Panel.STICKER },
                Tool(stringResource(R.string.tool_audio), Icons.Default.LibraryMusic) { pickMedia(ImportTarget.AUDIO) },
                Tool(stringResource(R.string.panel_voiceover), Icons.Default.Mic) { vm.panel = Panel.VOICEOVER },
                Tool(stringResource(R.string.panel_layout), Icons.Default.GridView) { vm.panel = Panel.LAYOUT },
                Tool(stringResource(R.string.home_ratio), Icons.Default.AspectRatio) { vm.panel = Panel.CANVAS },
                Tool(stringResource(R.string.tool_split), Icons.Default.ContentCut) { vm.split() },
                Tool(stringResource(R.string.tool_freeze), Icons.Default.AcUnit) { vm.freezeFrame() },
            )
            category == ClipCategory.TEXT -> listOf(
                Tool(stringResource(R.string.tool_edit), Icons.Default.Edit) { vm.panel = Panel.TEXT_EDIT },
                Tool(stringResource(R.string.panel_font), Icons.Default.FontDownload) { vm.panel = Panel.TEXT_FONT },
                Tool(stringResource(R.string.panel_style), Icons.Default.FormatColorText) { vm.panel = Panel.TEXT_STYLE },
                Tool(stringResource(R.string.panel_animation), Icons.Default.Animation) { vm.panel = Panel.TEXT_ANIM },
                Tool(stringResource(R.string.tool_position), Icons.Default.OpenWith) { vm.panel = Panel.TRANSFORM },
                Tool(stringResource(R.string.tool_keyframe), Icons.Default.Diamond) { vm.toggleKeyframe() },
                Tool(stringResource(R.string.tool_split), Icons.Default.ContentCut) { vm.split() },
                Tool(stringResource(R.string.tool_to_new_layer), Icons.Default.Layers) { vm.toNewLayer() },
                Tool(stringResource(R.string.home_duplicate), Icons.Default.ContentCopy) { vm.duplicateSelected() },
                Tool(stringResource(R.string.common_delete), Icons.Default.Delete) { vm.deleteSelected() },
            )
            category == ClipCategory.AUDIO -> listOf(
                Tool(stringResource(R.string.panel_volume), Icons.AutoMirrored.Filled.VolumeUp) { vm.panel = Panel.VOLUME },
                Tool(stringResource(R.string.panel_speed), Icons.Default.Speed) { vm.panel = Panel.SPEED },
                Tool(stringResource(R.string.tool_split), Icons.Default.ContentCut) { vm.split() },
                Tool(stringResource(R.string.tool_to_new_layer), Icons.Default.Layers) { vm.toNewLayer() },
                Tool(stringResource(R.string.home_duplicate), Icons.Default.ContentCopy) { vm.duplicateSelected() },
                Tool(stringResource(R.string.tool_save_audio), Icons.Default.SaveAlt) { vm.saveAudio() },
                Tool(stringResource(R.string.common_delete), Icons.Default.Delete) { vm.deleteSelected() },
            )
            else -> {
                val asset = vm.project.asset(clip.assetId)
                val isVideo = asset?.type == MediaType.VIDEO
                buildList {
                    add(Tool(stringResource(R.string.tool_split), Icons.Default.ContentCut) { vm.split() })
                    add(Tool(stringResource(R.string.tool_to_new_layer), Icons.Default.Layers) { vm.toNewLayer() })
                    if (isVideo) add(Tool(stringResource(R.string.panel_speed), Icons.Default.Speed) { vm.panel = Panel.SPEED })
                    if (isVideo) add(Tool(stringResource(R.string.panel_volume), Icons.AutoMirrored.Filled.VolumeUp) { vm.panel = Panel.VOLUME })
                    add(Tool(stringResource(R.string.tool_position), Icons.Default.OpenWith) { vm.panel = Panel.TRANSFORM })
                    add(Tool(stringResource(R.string.panel_layout), Icons.Default.GridView) { vm.panel = Panel.LAYOUT })
                    add(Tool(stringResource(R.string.tool_keyframe), Icons.Default.Diamond) { vm.toggleKeyframe() })
                    add(Tool(stringResource(R.string.panel_adjust), Icons.Default.Tune) { vm.panel = Panel.ADJUST })
                    add(Tool(stringResource(R.string.panel_filters), Icons.Default.PhotoFilter) { vm.panel = Panel.FILTER })
                    add(Tool(stringResource(R.string.panel_crop), Icons.Default.Crop) { vm.panel = Panel.CROP })
                    if (track?.kind == TrackKind.OVERLAY) add(Tool(stringResource(R.string.tool_to_main), Icons.Default.VerticalAlignBottom) { vm.toMain() })
                    if (isVideo) add(Tool(stringResource(R.string.tool_freeze), Icons.Default.AcUnit) { vm.freezeFrame() })
                    if (isVideo && asset?.hasAudio == true) add(Tool(stringResource(R.string.tool_extract_audio), Icons.Default.MusicNote) { vm.extractAudio() })
                    if (isVideo && asset?.hasAudio == true) add(Tool(stringResource(R.string.tool_save_audio), Icons.Default.SaveAlt) { vm.saveAudio() })
                    add(Tool(stringResource(R.string.tool_replace), Icons.Default.SwapHoriz) { pickMedia(ImportTarget.REPLACE) })
                    add(Tool(stringResource(R.string.home_duplicate), Icons.Default.ContentCopy) { vm.duplicateSelected() })
                    add(Tool(stringResource(R.string.common_delete), Icons.Default.Delete) { vm.deleteSelected() })
                }
            }
        }
    }

    val panelContent: @Composable (Panel) -> Unit = { shown ->
        when (shown) {
            Panel.COVER -> CoverPanel(vm) { pickMedia(ImportTarget.COVER) }
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
    // Every panel slides up over the editor instead of sharing the screen with it, so the preview keeps its size.
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
                onCoverTap = { vm.selectedId = null; vm.selectedGapUs = null; vm.panel = Panel.COVER },
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
            if (vm.fullscreen) {
                preview(Modifier.fillMaxWidth().weight(1f))
                TransportBar(vm)
            } else if (landscape) {
                Row(Modifier.fillMaxWidth().weight(0.56f)) {
                    preview(Modifier.weight(1f).fillMaxHeight())
                    Box(Modifier.width(380.dp).fillMaxHeight().background(Palette.Surface)) { ToolGrid(tools) }
                }
                TransportBar(vm)
                timeline(Modifier.fillMaxWidth().weight(0.44f))
            } else {
                preview(Modifier.fillMaxWidth().weight(1f))
                TransportBar(vm)
                timeline(Modifier.fillMaxWidth().height((screenH * 0.3f).coerceIn(180.dp, 320.dp)))
                Box(Modifier.fillMaxWidth().heightIn(min = 76.dp, max = screenH * 0.34f)) { ToolRow(tools) }
            }
        }

        // How far the panel has been dragged down; it starts at rest each time a panel opens.
        var coverDrag by remember { mutableFloatStateOf(0f) }
        // The panel last shown, kept while it slides away.
        var shownPanel by remember { mutableStateOf(Panel.COVER) }
        LaunchedEffect(vm.panel) { if (vm.panel != Panel.NONE && vm.panel != Panel.EXPORT) shownPanel = vm.panel }
        LaunchedEffect(showPanel) { if (showPanel) coverDrag = 0f }
        AnimatedVisibility(
            visible = showPanel && !vm.fullscreen,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(tween(260)) { it } + fadeIn(tween(200)),
            exit = slideOutVertically(tween(220)) { it } + fadeOut(tween(180)),
        ) {
            // Swiping down from the handle or header hides the panel; letting go early lets it spring back.
            val hideThreshold = with(LocalDensity.current) { (screenH * 0.12f).toPx() }
            val swipeDown = Modifier.pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragEnd = {
                        if (coverDrag > hideThreshold) { if (vm.recording) vm.stopRecording(); vm.endGesture(); vm.panel = Panel.NONE } else coverDrag = 0f
                    },
                    onDragCancel = { coverDrag = 0f },
                ) { change, amount -> change.consume(); coverDrag = (coverDrag + amount).coerceAtLeast(0f) }
            }
            Column(
                Modifier.fillMaxWidth().height(screenH * 0.6f).offset { IntOffset(0, coverDrag.roundToInt()) }
                    .shadow(16.dp, RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
                    .clip(RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp)).background(Palette.Surface)
                    // Takes every touch on the panel, so a drag here never reaches the preview or timeline underneath.
                    .pointerInput(Unit) { detectTapGestures { } },
            ) {
                // The handle and the header both swipe the panel down; the handle's area is generous, so the top is easy to grab.
                Box(swipeDown.fillMaxWidth().height(28.dp), contentAlignment = Alignment.TopCenter) {
                    Box(Modifier.padding(top = 8.dp).width(36.dp).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Palette.TextDim.copy(alpha = 0.5f)))
                }
                CompositionLocalProvider(LocalPanelHeaderModifier provides swipeDown) {
                    if (shownPanel == Panel.COVER) CoverPanel(vm, swipeDown) { pickMedia(ImportTarget.COVER) } else panelContent(shownPanel)
                }
            }
        }

        vm.message?.let { msg ->
            LaunchedEffect(msg) { delay(3500); if (vm.message == msg) vm.message = null }
            Snackbar(Modifier.align(Alignment.BottomCenter).padding(16.dp), action = { TextButton(onClick = { vm.message = null }) { Text(stringResource(R.string.editor_ok)) } }) { Text(msg) }
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
            title = { Text(stringResource(if (s.isAudio) R.string.editor_audio_saved else R.string.editor_video_saved)) },
            text = { Text("${s.displayName}\n${"%.1f".format(s.bytes / 1_000_000f)} MB · ${if (s.isAudio) "Music" else "Movies"}/FrameNova") },
            confirmButton = {
                TextButton(onClick = {
                    val share = Intent(Intent.ACTION_SEND).setType(if (s.isAudio) "audio/mp4" else "video/mp4").putExtra(Intent.EXTRA_STREAM, s.uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    context.startActivity(Intent.createChooser(share, shareTitle))
                }) { Text(stringResource(R.string.editor_share)) }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(s.uri, if (s.isAudio) "audio/mp4" else "video/mp4").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    }) { Text(stringResource(R.string.editor_open)) }
                    TextButton(onClick = { ExportManager.dismiss() }) { Text(stringResource(R.string.panel_done)) }
                }
            },
        )
        is ExportState.Failed -> AlertDialog(
            onDismissRequest = { ExportManager.dismiss() },
            title = { Text(stringResource(R.string.editor_export_failed)) },
            text = { Text(s.message) },
            confirmButton = { TextButton(onClick = { ExportManager.dismiss() }) { Text(stringResource(R.string.editor_ok)) } },
        )
        ExportState.Idle -> {}
    }
    library?.let { req ->
        val audio = req.target == ImportTarget.AUDIO
        MediaLibrary(
            kind = if (audio) LibraryKind.AUDIO else LibraryKind.VISUAL,
            title = when (req.target) {
                ImportTarget.MAIN -> stringResource(R.string.editor_add_videos_photos)
                ImportTarget.OVERLAY -> stringResource(R.string.editor_add_as_layer)
                ImportTarget.AUDIO -> stringResource(R.string.editor_add_audio)
                ImportTarget.REPLACE -> stringResource(R.string.editor_replace_clip)
                ImportTarget.COVER -> stringResource(R.string.editor_choose_cover)
            },
            multiple = req.target != ImportTarget.REPLACE && req.target != ImportTarget.COVER,
            photosOnly = req.target == ImportTarget.COVER,
            onDismiss = { library = null },
        ) { uris -> library = null; vm.import(uris, req.target) }
    }
    if (renaming) RenameDialog(vm.project.name, onDismiss = { renaming = false }) { vm.rename(it); renaming = false }
}

@UnstableApi
@Composable
private fun TopBar(vm: EditorViewModel, onClose: () -> Unit, onRename: () -> Unit, onExport: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.editor_back)) }
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
                    stringResource(if (vm.panel == Panel.CANVAS) R.string.editor_hide_format else R.string.editor_show_format),
                    tint = Palette.Accent, modifier = Modifier.size(16.dp),
                )
            }
        }
        IconButton(onClick = vm::undo, enabled = vm.canUndo) { Icon(Icons.AutoMirrored.Filled.Undo, stringResource(R.string.editor_undo)) }
        IconButton(onClick = vm::redo, enabled = vm.canRedo) { Icon(Icons.AutoMirrored.Filled.Redo, stringResource(R.string.editor_redo)) }
        Button(onClick = onExport, enabled = vm.project.durationUs > 0, shape = RoundedCornerShape(10.dp), modifier = Modifier.padding(end = 6.dp)) { Text(stringResource(R.string.editor_export)) }
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
        IconButton(onClick = { vm.jumpTo(0) }) { Icon(Icons.Default.SkipPrevious, stringResource(R.string.editor_start)) }
        IconButton(onClick = vm::togglePlay, enabled = vm.project.durationUs > 0) {
            Icon(if (vm.playing) Icons.Default.Pause else Icons.Default.PlayArrow, stringResource(R.string.editor_play), modifier = Modifier.size(32.dp))
        }
        IconButton(onClick = { vm.jumpTo(vm.project.durationUs) }) { Icon(Icons.Default.SkipNext, stringResource(R.string.editor_end)) }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = { vm.fullscreen = !vm.fullscreen }) { Icon(if (vm.fullscreen) Icons.Default.FullscreenExit else Icons.Default.Fullscreen, stringResource(R.string.editor_full_screen)) }
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
        title = { Text(stringResource(R.string.editor_export)) },
        text = {
            Column {
                Text(stringResource(R.string.home_resolution), color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { ResolutionTier.highToLow.forEach { r -> FilterChip(selected = tier == r, onClick = { tier = r }, label = { Text(r.label) }) } }
                Text(stringResource(R.string.home_frame_rate), color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { FRAME_RATES.forEach { f -> FilterChip(selected = fps == f, onClick = { fps = f }, label = { Text("$f") }) } }
                Text(stringResource(R.string.editor_codec), color = Palette.TextDim, fontSize = 12.sp)
                ChipRow {
                    FilterChip(selected = hevc, onClick = { hevc = true }, label = { Text(stringResource(R.string.editor_hevc_smaller)) })
                    FilterChip(selected = !hevc, onClick = { hevc = false }, label = { Text(stringResource(R.string.editor_h_264_compatible)) })
                }
                Text(stringResource(R.string.editor_quality), color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { ExportQuality.entries.forEach { q -> FilterChip(selected = quality == q, onClick = { quality = q }, label = { Text(q.displayName()) }) } }
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(
                        R.string.editor_export_summary, size.width, size.height,
                        "%.0f".format(settings.bitrate(size.width, size.height) / 1_000_000f),
                        "%.0f".format(ExportManager.estimateBytes(vm.project, settings) / 1_000_000f),
                    ),
                    color = Palette.TextDim, fontSize = 12.sp,
                )
                if (vm.project.assets.any { it.isHdr }) Text(stringResource(R.string.editor_hdr_clips_are_converted), color = Palette.TextDim, fontSize = 12.sp)
            }
        },
        confirmButton = { Button(onClick = { onDismiss(); vm.export(settings) }) { Text(stringResource(R.string.editor_export)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@UnstableApi
@Composable
private fun ExportProgressDialog(s: ExportState.Running) {
    AlertDialog(
        onDismissRequest = {},
        title = { Text(stringResource(R.string.editor_exporting)) },
        text = {
            Column {
                Text(s.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(12.dp))
                LinearProgressIndicator(progress = { s.progress / 100f }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.editor_export_progress, s.progress), color = Palette.TextDim, fontSize = 12.sp)
            }
        },
        confirmButton = { TextButton(onClick = { ExportManager.cancel() }) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@Composable
fun RenameDialog(initial: String, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.common_rename)) },
        text = { OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onRename(name.trim()) }) { Text(stringResource(R.string.editor_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}
