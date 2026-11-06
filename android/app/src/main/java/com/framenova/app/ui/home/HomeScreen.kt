package com.framenova.app.ui.home

import androidx.compose.ui.res.stringResource
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.runtime.saveable.rememberSaveable
import com.framenova.app.AppLanguage
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.res.painterResource
import com.framenova.app.R
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import com.framenova.app.BuildConfig
import com.framenova.app.DevLogPanel
import com.framenova.app.DevTools
import com.framenova.app.saveLogToast
import com.framenova.app.data.ProjectRepository
import com.framenova.app.data.ProjectSummary
import com.framenova.app.engine.MediaProbe
import com.framenova.app.model.AspectPreset
import com.framenova.app.model.FRAME_RATES
import com.framenova.app.model.CanvasSettings
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import com.framenova.app.model.Project
import com.framenova.app.model.ResolutionTier
import com.framenova.app.model.addToMainAt
import com.framenova.app.model.newId
import com.framenova.app.ui.editor.RenameDialog
import com.framenova.app.ui.editor.ChipRow
import com.framenova.app.ui.editor.formatTime
import com.framenova.app.ui.media.LibraryKind
import com.framenova.app.ui.media.MediaLibrary
import com.framenova.app.ui.theme.Palette
import com.framenova.app.update.AppUpdates
import com.framenova.app.update.UpdatePhase
import com.framenova.app.update.UpdateSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs

@UnstableApi
@Composable
fun HomeScreen(updates: AppUpdates, onOpen: (String) -> Unit) {
    val context = LocalContext.current
    val resources = androidx.compose.ui.platform.LocalResources.current
    val repo = remember { ProjectRepository(context) }
    val scope = rememberCoroutineScope()
    var refresh by remember { mutableIntStateOf(0) }
    val projects by produceState(initialValue = emptyList<ProjectSummary>(), refresh) { value = withContext(Dispatchers.IO) { repo.list() } }
    var pending by remember { mutableStateOf<List<MediaAsset>?>(null) }
    var importing by remember { mutableStateOf(false) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<ProjectSummary?>(null) }
    var deleting by remember { mutableStateOf<ProjectSummary?>(null) }

    var library by remember { mutableStateOf(false) }
    fun startProject(uris: List<Uri>) {
        library = false
        if (uris.isEmpty()) return
        importing = true
        scope.launch {
            val assets = withContext(Dispatchers.IO) {
                uris.mapNotNull { uri ->
                    runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                    MediaProbe.probe(context, uri)
                }
            }
            importing = false
            pending = assets.takeIf { it.isNotEmpty() }
        }
    }
    if (library) MediaLibrary(
        kind = LibraryKind.VISUAL, title = stringResource(R.string.home_new_project), multiple = true,
        onDismiss = { library = false },
    ) { uris -> startProject(uris) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            BrandMark(Modifier.weight(1f))
            IconButton(onClick = { settings = true }) {
                Box {
                    Icon(Icons.Default.Settings, stringResource(R.string.home_settings))
                    if (updates.ui.hasUpdate) Box(Modifier.size(8.dp).clip(RoundedCornerShape(4.dp)).background(Palette.Danger).align(Alignment.TopEnd))
                }
            }
        }
        LazyVerticalGrid(GridCells.Adaptive(170.dp), Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (updates.ui.hasUpdate && updates.ui.phase == UpdatePhase.AVAILABLE) item(span = { GridItemSpan(maxLineSpan) }) {
                Card(colors = CardDefaults.cardColors(containerColor = Palette.AccentSoft), modifier = Modifier.clickable { settings = true }) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.SystemUpdate, null, tint = Palette.Accent)
                        Spacer(Modifier.width(10.dp))
                        Text(stringResource(R.string.update_version_available, updates.ui.version.orEmpty()), modifier = Modifier.weight(1f))
                        TextButton(onClick = { updates.update() }) { Text(stringResource(R.string.update_action)) }
                    }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Box(
                    Modifier.fillMaxWidth().height(120.dp).clip(RoundedCornerShape(18.dp))
                        .background(Brush.linearGradient(listOf(Palette.Accent, Color(0xFF4F7CFF), Palette.Teal)))
                        .clickable(enabled = !importing) { library = true },
                    contentAlignment = Alignment.Center,
                ) {
                    if (importing) CircularProgressIndicator(color = Color.White)
                    else Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Add, null, tint = Color.White, modifier = Modifier.size(34.dp))
                        Spacer(Modifier.width(8.dp))
                        Column {
                            Text(stringResource(R.string.home_new_project), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                            Text(stringResource(R.string.home_pick_to_start), color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
                        }
                    }
                }
            }
            if (projects.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                Text(stringResource(R.string.home_empty), color = Palette.TextDim, modifier = Modifier.padding(8.dp))
            }
            items(projects, key = { it.id }) { p ->
                ProjectCard(p, onOpen = { onOpen(p.id) }, onRename = { renaming = p }, onDuplicate = {
                    scope.launch { withContext(Dispatchers.IO) { repo.duplicate(p.id, System.currentTimeMillis()) }; refresh++ }
                }, onDelete = { deleting = p })
            }
        }
    }

    pending?.let { assets ->
        NewProjectDialog(assets, onDismiss = { pending = null }) { canvas ->
            pending = null
            val now = System.currentTimeMillis()
            val name = resources.getString(R.string.home_default_project_name, DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(now)))
            val project = Project(id = newId(), name = name, createdAt = now, modifiedAt = now, canvas = canvas).addToMainAt(assets, 0)
            scope.launch {
                withContext(Dispatchers.IO) { repo.save(project); repo.writeCover(project) }
                onOpen(project.id)
            }
        }
    }
    renaming?.let { p -> RenameDialog(p.name, onDismiss = { renaming = null }) { name -> scope.launch { withContext(Dispatchers.IO) { repo.rename(p.id, name) }; renaming = null; refresh++ } } }
    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.home_delete_title, p.name)) },
            text = { Text(stringResource(R.string.home_delete_message)) },
            confirmButton = { TextButton(onClick = { scope.launch { withContext(Dispatchers.IO) { repo.delete(p.id) }; deleting = null; refresh++ } }) { Text(stringResource(R.string.common_delete), color = Palette.Danger) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.common_cancel)) } },
        )
    }
    if (settings) SettingsDialog(updates, onDismiss = { settings = false })
    LaunchedEffect(Unit) { refresh++ }
}

@Composable
private fun ProjectCard(p: ProjectSummary, onOpen: () -> Unit, onRename: () -> Unit, onDuplicate: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val cover by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, p.cover, p.modifiedAt) {
        value = withContext(Dispatchers.IO) { p.cover?.let { runCatching { BitmapFactory.decodeFile(it.path)?.asImageBitmap() }.getOrNull() } }
    }
    Column(Modifier.clip(RoundedCornerShape(14.dp)).background(Palette.Surface).clickable(onClick = onOpen)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 10f).background(Palette.Surface2), contentAlignment = Alignment.Center) {
            val c = cover
            if (c != null) Image(c, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            else Icon(Icons.Default.Movie, null, tint = Palette.TextDim)
            Text(formatTime(p.durationUs), fontSize = 11.sp, modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp))
        }
        Row(Modifier.padding(start = 10.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(p.name, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
                Text("${p.aspect} · ${DateFormat.getDateInstance(DateFormat.SHORT).format(Date(p.modifiedAt))}", color = Palette.TextDim, fontSize = 11.sp)
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, stringResource(R.string.home_more)) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.common_rename)) }, onClick = { menu = false; onRename() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.home_duplicate)) }, onClick = { menu = false; onDuplicate() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.common_delete), color = Palette.Danger) }, onClick = { menu = false; onDelete() })
                }
            }
        }
    }
}

/** Suggests canvas settings from the first clip: its orientation, resolution and frame rate. */
private fun suggestCanvas(assets: List<MediaAsset>): CanvasSettings {
    val first = assets.firstOrNull { it.type == MediaType.VIDEO } ?: assets.firstOrNull() ?: return CanvasSettings()
    val ratio = first.width.toFloat() / first.height.coerceAtLeast(1)
    val aspect = AspectPreset.entries.minBy { abs(it.ratio - ratio) }
    val long = maxOf(first.width, first.height)
    val tier = ResolutionTier.entries.lastOrNull { it.longSide <= long + 64 } ?: ResolutionTier.FHD
    val fps = when { first.frameRate >= 50f -> 60; first.frameRate in 23f..24.5f -> 24; first.frameRate in 24.5f..26f -> 25; else -> 30 }
    return CanvasSettings(aspect = aspect, tier = tier, fps = fps)
}

/** A bottom sheet like iPhone's: Cancel and Create in the header, then the canvas controls, suggested from the first clip. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun NewProjectDialog(assets: List<MediaAsset>, onDismiss: () -> Unit, onCreate: (CanvasSettings) -> Unit) {
    var canvas by remember { mutableStateOf(suggestCanvas(assets)) }
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Palette.Surface,
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
            Text(stringResource(R.string.home_new_project), Modifier.weight(1f), fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextButton(onClick = { onCreate(canvas) }) { Text(stringResource(R.string.home_create), fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            com.framenova.app.ui.editor.CanvasControls(canvas) { change -> canvas = change(canvas) }
        }
    }
}

@Composable
private fun SettingsDialog(updates: AppUpdates, onDismiss: () -> Unit) {
    val ui = updates.ui
    val context = LocalContext.current
    val devEnabledMessage = stringResource(R.string.home_dev_enabled)
    var devTools by remember { mutableStateOf(DevTools.enabled(context)) }
    var versionTaps by remember { mutableIntStateOf(0) }
    var showLog by remember { mutableStateOf(false) }
    var licensesExpanded by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // Like Android's build number: ten taps on the version unlock the developer tools.
    val versionModifier = Modifier.clickable(interactionSource = null, indication = null) {
        if (devTools) return@clickable
        if (++versionTaps >= DevTools.UNLOCK_TAPS) {
            DevTools.enable(context)
            devTools = true
            android.widget.Toast.makeText(context, devEnabledMessage, android.widget.Toast.LENGTH_SHORT).show()
        }
    }
    if (showLog) DevLogPanel { showLog = false }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("FrameNova") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(stringResource(R.string.home_version, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE), versionModifier, color = Palette.TextDim, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.language_title), fontWeight = FontWeight.Medium)
                var language by remember { mutableStateOf(AppLanguage.get(context)) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AppLanguage.all.forEach { tag ->
                        FilterChip(
                            selected = language == tag,
                            onClick = { language = tag; AppLanguage.set(context, tag) },
                            label = { Text(stringResource(when (tag) { AppLanguage.ENGLISH -> R.string.language_english; AppLanguage.TRADITIONAL_CHINESE -> R.string.language_chinese; else -> R.string.language_system })) },
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                if (updates.enabled) {
                    Text(stringResource(R.string.update_heading, when (ui.source) { UpdateSource.LAN -> stringResource(R.string.update_source_lan); UpdateSource.PLAY -> stringResource(R.string.update_source_play); UpdateSource.GITHUB -> stringResource(R.string.update_source_github); UpdateSource.NONE -> "" }), fontWeight = FontWeight.Medium)
                    Text(
                        when (ui.phase) {
                            UpdatePhase.IDLE -> stringResource(R.string.update_idle)
                            UpdatePhase.CHECKING -> stringResource(R.string.update_checking)
                            UpdatePhase.CURRENT -> stringResource(R.string.update_current)
                            UpdatePhase.AVAILABLE -> stringResource(R.string.update_version_available, ui.version.orEmpty())
                            UpdatePhase.DOWNLOADING -> stringResource(R.string.update_downloading, ui.percent)
                            UpdatePhase.PERMISSION -> stringResource(R.string.update_permission)
                            UpdatePhase.INSTALLING -> stringResource(R.string.update_installing)
                            UpdatePhase.ERROR -> stringResource(R.string.update_error, ui.error ?: stringResource(R.string.update_unknown_error))
                        },
                        color = Palette.TextDim, fontSize = 13.sp,
                    )
                    if (ui.phase == UpdatePhase.DOWNLOADING) LinearProgressIndicator(progress = { ui.percent / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                    Spacer(Modifier.height(8.dp))
                    Row {
                        if (ui.hasUpdate) Button(onClick = { updates.update() }, enabled = ui.phase != UpdatePhase.DOWNLOADING) {
                            Text(stringResource(if (ui.phase == UpdatePhase.PERMISSION || ui.phase == UpdatePhase.INSTALLING) R.string.update_continue_install else R.string.update_now))
                        }
                        else TextButton(onClick = { updates.check(true) }, enabled = ui.phase != UpdatePhase.CHECKING) { Text(stringResource(R.string.update_check)) }
                    }
                } else {
                    Text(stringResource(R.string.update_unsupported), color = Palette.TextDim, fontSize = 13.sp)
                }
                if (devTools) {
                    Spacer(Modifier.height(16.dp))
                    HorizontalDivider()
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.home_dev_tools), Modifier.weight(1f), fontWeight = FontWeight.Medium)
                        // Turning them off locks them again; ten taps on the version unlock them.
                        Switch(true, { DevTools.disable(context); devTools = false; versionTaps = 0 })
                    }
                    OutlinedButton(onClick = { showLog = true }) { Text(stringResource(R.string.home_dev_logs)) }
                    OutlinedButton(onClick = { scope.launch { saveLogToast(context) } }) { Text(stringResource(R.string.home_save_logs)) }
                }
                Spacer(Modifier.height(16.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable { licensesExpanded = !licensesExpanded },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.home_licenses), Modifier.weight(1f), fontWeight = FontWeight.Medium)
                    Icon(
                        if (licensesExpanded) Icons.Default.ArrowDropUp else Icons.Default.ArrowDropDown,
                        stringResource(if (licensesExpanded) R.string.home_licenses_hide else R.string.home_licenses_show),
                    )
                }
                Text(
                    stringResource(R.string.home_license_summary),
                    color = Palette.TextDim, fontSize = 12.sp,
                )
                if (licensesExpanded) {
                    Text(
                        stringResource(R.string.home_license_libraries) + "\n" +
                            stringResource(
                                R.string.home_license_fonts,
                                com.framenova.app.engine.FontCatalog.all.filter { it.group != com.framenova.app.engine.FontGroup.SYSTEM }
                                    .joinToString(", ") { it.name },
                            ),
                        color = Palette.TextDim, fontSize = 12.sp,
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_close)) } },
    )
}

/** The app icon followed by the FrameNova wordmark: heavy, tightly spaced letters, with "Nova" in the icon's gradient. */
@Composable
fun BrandMark(modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Image(
            painterResource(R.drawable.brand_icon), null,
            Modifier.size(34.dp).clip(RoundedCornerShape(8.dp)),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            buildAnnotatedString {
                append("Frame")
                withStyle(SpanStyle(brush = Brush.linearGradient(listOf(Palette.Accent, Color(0xFF4F7CFF), Palette.Teal)))) { append("Nova") }
            },
            fontSize = 27.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.8).sp,
            modifier = Modifier.semantics { contentDescription = "FrameNova" },
        )
    }
}
