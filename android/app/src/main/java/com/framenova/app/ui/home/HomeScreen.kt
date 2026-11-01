package com.framenova.app.ui.home

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import com.framenova.app.BuildConfig
import com.framenova.app.data.ProjectRepository
import com.framenova.app.data.ProjectSummary
import com.framenova.app.engine.MediaProbe
import com.framenova.app.model.AspectPreset
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
    val repo = remember { ProjectRepository(context) }
    val scope = rememberCoroutineScope()
    var refresh by remember { mutableIntStateOf(0) }
    val projects by produceState(initialValue = emptyList<ProjectSummary>(), refresh) { value = withContext(Dispatchers.IO) { repo.list() } }
    var pending by remember { mutableStateOf<List<MediaAsset>?>(null) }
    var importing by remember { mutableStateOf(false) }
    var settings by remember { mutableStateOf(false) }
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
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) startProject(uris) }
    if (library) MediaLibrary(
        kind = LibraryKind.VISUAL, title = "New project", multiple = true,
        onDismiss = { library = false }, onBrowseFiles = { files.launch(arrayOf("video/*", "image/*")) },
    ) { uris -> startProject(uris) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("FrameNova", fontSize = 26.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            IconButton(onClick = { settings = true }) {
                Box {
                    Icon(Icons.Default.Settings, "Settings")
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
                        Text("Version ${updates.ui.version} is available", modifier = Modifier.weight(1f))
                        TextButton(onClick = { updates.update() }) { Text("Update") }
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
                            Text("New project", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                            Text("Pick videos and photos to start", color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
                        }
                    }
                }
            }
            if (projects.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                Text("Your projects appear here. Everything stays on this device.", color = Palette.TextDim, modifier = Modifier.padding(8.dp))
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
            val name = "Project " + DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(now))
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
            title = { Text("Delete \"${p.name}\"?") },
            text = { Text("The project is removed. Your original videos and photos are not touched.") },
            confirmButton = { TextButton(onClick = { scope.launch { withContext(Dispatchers.IO) { repo.delete(p.id) }; deleting = null; refresh++ } }) { Text("Delete", color = Palette.Danger) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel") } },
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
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "More") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Rename") }, onClick = { menu = false; onRename() })
                    DropdownMenuItem(text = { Text("Duplicate") }, onClick = { menu = false; onDuplicate() })
                    DropdownMenuItem(text = { Text("Delete", color = Palette.Danger) }, onClick = { menu = false; onDelete() })
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

@Composable
private fun NewProjectDialog(assets: List<MediaAsset>, onDismiss: () -> Unit, onCreate: (CanvasSettings) -> Unit) {
    var canvas by remember { mutableStateOf(suggestCanvas(assets)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New project") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("${assets.size} item(s) selected. Settings are suggested from your first clip.", color = Palette.TextDim, fontSize = 12.sp)
                Spacer(Modifier.height(8.dp))
                Text("Ratio", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { AspectPreset.entries.forEach { a -> FilterChip(selected = canvas.aspect == a, onClick = { canvas = canvas.copy(aspect = a) }, label = { Text(a.label) }) } }
                Text("Resolution", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { ResolutionTier.entries.forEach { r -> FilterChip(selected = canvas.tier == r, onClick = { canvas = canvas.copy(tier = r) }, label = { Text(r.label) }) } }
                Text("Frame rate", color = Palette.TextDim, fontSize = 12.sp)
                ChipRow { listOf(24, 25, 30, 50, 60).forEach { f -> FilterChip(selected = canvas.fps == f, onClick = { canvas = canvas.copy(fps = f) }, label = { Text("$f fps") }) } }
                Text("${canvas.size.width} × ${canvas.size.height}", color = Palette.TextDim, fontSize = 12.sp)
            }
        },
        confirmButton = { Button(onClick = { onCreate(canvas) }) { Text("Create") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun SettingsDialog(updates: AppUpdates, onDismiss: () -> Unit) {
    val ui = updates.ui
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("FrameNova") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", color = Palette.TextDim, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                if (updates.enabled) {
                    Text("Updates · " + when (ui.source) { UpdateSource.LAN -> "local network"; UpdateSource.PLAY -> "Google Play"; UpdateSource.GITHUB -> "GitHub releases"; UpdateSource.NONE -> "" }, fontWeight = FontWeight.Medium)
                    Text(
                        when (ui.phase) {
                            UpdatePhase.IDLE -> "Check for a newer version"
                            UpdatePhase.CHECKING -> "Checking for updates…"
                            UpdatePhase.CURRENT -> "You're up to date"
                            UpdatePhase.AVAILABLE -> "Version ${ui.version} is available"
                            UpdatePhase.DOWNLOADING -> "Downloading update… ${ui.percent}%"
                            UpdatePhase.PERMISSION -> "Allow installs from FrameNova, then return here."
                            UpdatePhase.INSTALLING -> "Confirm the installation in Android."
                            UpdatePhase.ERROR -> "Could not check or install the update: ${ui.error ?: "unknown error"}"
                        },
                        color = Palette.TextDim, fontSize = 13.sp,
                    )
                    if (ui.phase == UpdatePhase.DOWNLOADING) LinearProgressIndicator(progress = { ui.percent / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                    Spacer(Modifier.height(8.dp))
                    Row {
                        if (ui.hasUpdate) Button(onClick = { updates.update() }, enabled = ui.phase != UpdatePhase.DOWNLOADING) {
                            Text(if (ui.phase == UpdatePhase.PERMISSION || ui.phase == UpdatePhase.INSTALLING) "Continue installation" else "Update now")
                        }
                        else TextButton(onClick = { updates.check(true) }, enabled = ui.phase != UpdatePhase.CHECKING) { Text("Check for updates") }
                    }
                } else {
                    Text("This build doesn't update itself. Debug builds update over the local network when built with a LAN update host.", color = Palette.TextDim, fontSize = 13.sp)
                }
                Spacer(Modifier.height(16.dp))
                Text("Licenses", fontWeight = FontWeight.Medium)
                Text(
                    "FrameNova is source-available under the PolyForm Strict License 1.0.0.\n" +
                        "Uses AndroidX Media3, Jetpack Compose and Kotlin libraries (Apache License 2.0).\n" +
                        "Fonts: Inter, Montserrat, Oswald, Bebas Neue, Playfair Display, Roboto Mono, Pacifico, Lobster, Dancing Script, Caveat, " +
                        "Noto Sans/Serif TC, Chiron Hei/Sung HK, LXGW WenKai TC, Iansui and Huninn, all under the SIL Open Font License 1.1.",
                    color = Palette.TextDim, fontSize = 12.sp,
                )
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}
