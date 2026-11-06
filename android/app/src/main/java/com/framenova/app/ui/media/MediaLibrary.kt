package com.framenova.app.ui.media

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.framenova.app.R
import android.Manifest
import android.content.ContentUris
import androidx.annotation.StringRes
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import com.framenova.app.ui.theme.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What the library shows: videos and photos, or audio files. */
enum class LibraryKind { VISUAL, AUDIO }

private enum class VisualFilter(@StringRes val label: Int) {
    LIBRARY(R.string.library_filter_library), VIDEOS(R.string.library_filter_videos), PHOTOS(R.string.library_filter_photos)
}

/** [date] is when a photo or video was taken, or when the file was added if that is unknown, in milliseconds. */
internal data class LibraryItem(
    val uri: Uri, val name: String, val video: Boolean, val audio: Boolean,
    val albumId: String, val albumName: String, val date: Long, val durationMs: Long,
)

private data class LibraryAlbum(val id: String, val name: String, val cover: LibraryItem, val count: Int, val newest: Long, val oldest: Long)

internal enum class LibrarySort(@StringRes val label: Int) {
    NEWEST(R.string.library_sort_newest), OLDEST(R.string.library_sort_oldest), NAME_AZ(R.string.library_sort_name_az), NAME_ZA(R.string.library_sort_name_za)
}

/** Sorts files or albums; equal names fall back to the newest first, equal dates to the name. */
internal fun <T> librarySorted(entries: List<T>, sort: LibrarySort, name: (T) -> String, date: (T) -> Long): List<T> {
    val byName = compareBy(String.CASE_INSENSITIVE_ORDER, name)
    val byDate = compareByDescending(date)
    return entries.sortedWith(when (sort) {
        LibrarySort.NEWEST -> byDate.then(byName)
        LibrarySort.OLDEST -> byDate.reversed().then(byName)
        LibrarySort.NAME_AZ -> byName.then(byDate)
        LibrarySort.NAME_ZA -> byName.reversed().then(byDate)
    })
}

internal fun mediaPermissions(kind: LibraryKind, sdk: Int = Build.VERSION.SDK_INT): Array<String> = when {
    kind == LibraryKind.AUDIO && sdk >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
    sdk >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    sdk >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

internal data class LibraryAccess(val allowed: Boolean, val full: Boolean, val limited: Boolean = false) {
    val requestOnOpen: Boolean get() = !full && !limited
}

/** Selected files remain browsable, but access to one media type does not cover another. */
internal fun libraryAccess(permissions: Array<String>, granted: Set<String>): LibraryAccess {
    val selected = Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
    val full = permissions.filter { it != selected }.all { it in granted }
    return LibraryAccess(allowed = permissions.any { it in granted }, full = full, limited = !full && selected in permissions && selected in granted)
}

private fun libraryAccess(context: Context, permissions: Array<String>): LibraryAccess = libraryAccess(
    permissions, permissions.filter { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }.toSet(),
)

private fun loadLibrary(context: Context, kind: LibraryKind): List<LibraryItem> {
    val collection = MediaStore.Files.getContentUri("external")
    val id = MediaStore.Files.FileColumns._ID
    val type = MediaStore.Files.FileColumns.MEDIA_TYPE
    val name = MediaStore.MediaColumns.DISPLAY_NAME
    val path = MediaStore.MediaColumns.RELATIVE_PATH
    val taken = MediaStore.MediaColumns.DATE_TAKEN
    val added = MediaStore.MediaColumns.DATE_ADDED
    val duration = MediaStore.MediaColumns.DURATION
    val image = MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
    val video = MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
    val audio = MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO
    val (selection, args) = if (kind == LibraryKind.AUDIO) "$type=?" to arrayOf(audio.toString())
    else "($type=? OR $type=?)" to arrayOf(image.toString(), video.toString())
    val result = mutableListOf<LibraryItem>()
    context.contentResolver.query(collection, arrayOf(id, type, name, path, taken, added, duration), selection, args, "$added DESC")?.use { cursor ->
        val idColumn = cursor.getColumnIndexOrThrow(id)
        val typeColumn = cursor.getColumnIndexOrThrow(type)
        val nameColumn = cursor.getColumnIndexOrThrow(name)
        val pathColumn = cursor.getColumnIndexOrThrow(path)
        val takenColumn = cursor.getColumnIndexOrThrow(taken)
        val addedColumn = cursor.getColumnIndexOrThrow(added)
        val durationColumn = cursor.getColumnIndexOrThrow(duration)
        while (cursor.moveToNext()) {
            val mediaType = cursor.getInt(typeColumn)
            // Type-specific content URIs carry the right MIME type for probing and decoding.
            val base = when (mediaType) {
                video -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                audio -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val albumId = cursor.getString(pathColumn)?.trim('/')?.ifEmpty { "Other" } ?: "Other"
            val albumName = if (albumId == "Other") context.getString(R.string.library_other_folder) else albumId.substringAfterLast('/')
            // Copied-in camera clips are added long after they were taken; audio has no date taken.
            val date = cursor.getLong(takenColumn).takeIf { it > 0 } ?: (cursor.getLong(addedColumn) * 1000)
            result += LibraryItem(
                ContentUris.withAppendedId(base, cursor.getLong(idColumn)), cursor.getString(nameColumn).orEmpty(),
                mediaType == video, mediaType == audio, albumId, albumName, date, cursor.getLong(durationColumn),
            )
        }
    }
    return result
}

private fun durationLabel(ms: Long): String {
    val s = (ms + 500) / 1000
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

/**
 * Full-screen picker over the device's media library, with Recent and Albums (Folders for audio), sorting, and
 * multi-select by tapping or by holding an item and dragging across others. Videos and photos are returned in the
 * order they were selected.
 */
@Composable
fun MediaLibrary(
    kind: LibraryKind,
    title: String,
    multiple: Boolean,
    limit: Int = 50,
    photosOnly: Boolean = false,
    onDismiss: () -> Unit,
    onChoose: (List<Uri>) -> Unit,
) {
    val context = LocalContext.current
    val audioOnly = kind == LibraryKind.AUDIO
    var visualFilter by rememberSaveable(kind) { mutableStateOf(if (photosOnly) VisualFilter.PHOTOS else VisualFilter.LIBRARY) }
    var chosen by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
    val permissions = remember(kind) { mediaPermissions(kind) }
    var access by remember(kind) { mutableStateOf(libraryAccess(context, permissions)) }
    // Save the request attempt, not the permission grant: recreating the picker must not prompt again.
    var requestedOnOpen by rememberSaveable(kind) { mutableStateOf(false) }
    var libraryRevision by remember { mutableIntStateOf(0) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        access = libraryAccess(context, permissions)
        // Adding selected files may leave the permission flags unchanged, but the library must be queried again.
        libraryRevision++
    }
    LaunchedEffect(kind) {
        if (!requestedOnOpen) {
            requestedOnOpen = true
            if (access.requestOnOpen) permission.launch(permissions)
        }
    }
    val items by produceState<List<LibraryItem>?>(null, access.allowed, libraryRevision, kind) {
        value = if (access.allowed) withContext(Dispatchers.IO) { runCatching { loadLibrary(context, kind) }.getOrDefault(emptyList()) }
        else emptyList()
    }
    // Opens where it was last left, separately for media and audio.
    val prefs = remember { context.getSharedPreferences("preferences", 0) }
    val key = if (audioOnly) "library_audio_" else "library_media_"
    var section by rememberSaveable(kind) { mutableStateOf(prefs.getString(key + "section", null) ?: "recent") }
    var selectedAlbum by rememberSaveable(kind) { mutableStateOf(prefs.getString(key + "album", null)) }
    var sort by rememberSaveable(kind) {
        mutableStateOf(runCatching { LibrarySort.valueOf(prefs.getString(key + "sort", null)!!) }.getOrDefault(LibrarySort.NEWEST))
    }
    LaunchedEffect(section, selectedAlbum, sort) {
        prefs.edit().putString(key + "section", section).putString(key + "album", selectedAlbum).putString(key + "sort", sort.name).apply()
    }
    var menuExpanded by remember { mutableStateOf(false) }
    var sortExpanded by remember { mutableStateOf(false) }
    val filteredItems = remember(items, visualFilter, audioOnly) {
        items.orEmpty().filter {
            audioOnly || when (visualFilter) {
                VisualFilter.LIBRARY -> true
                VisualFilter.VIDEOS -> it.video
                VisualFilter.PHOTOS -> !it.video && !it.audio
            }
        }
    }
    val albums = remember(filteredItems, sort) {
        val grouped = filteredItems.groupBy { it.albumId }.map { (id, members) ->
            LibraryAlbum(id, members.first().albumName, members.first(), members.size, members.maxOf { it.date }, members.minOf { it.date })
        }
        librarySorted(grouped, sort, { it.name }, { if (sort == LibrarySort.OLDEST) it.oldest else it.newest })
    }
    val shown = remember(filteredItems, sort, section, selectedAlbum) {
        librarySorted(filteredItems.filter { section == "recent" || it.albumId == selectedAlbum }, sort, { it.name }, { it.date })
    }
    val grid = key(section, selectedAlbum, sort, visualFilter) { rememberLazyGridState() }
    val gridKeys = remember(shown) { shown.map { it.uri.toString() } }
    // A remembered album that is gone falls back to Recent.
    LaunchedEffect(items, selectedAlbum) {
        if (items != null && selectedAlbum != null && items.orEmpty().none { it.albumId == selectedAlbum }) {
            section = "recent"
            selectedAlbum = null
        }
    }
    fun toggle(uri: String) {
        if (uri in chosen) chosen = ArrayList(chosen - uri) else if (chosen.size < limit) chosen = ArrayList(chosen + uri)
    }
    val albumsLabel = stringResource(if (audioOnly) R.string.library_folders else R.string.library_albums)
    val allAlbumsLabel = stringResource(if (audioOnly) R.string.library_all_folders else R.string.library_all_albums)
    val chooseAlbumsLabel = stringResource(if (audioOnly) R.string.library_choose_folders else R.string.library_choose_albums)

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = Palette.Bg, contentColor = Palette.Text) {
            Column(Modifier.systemBarsPadding()) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (audioOnly || photosOnly) {
                        Text(title, Modifier.weight(1f), fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    } else Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        VisualFilter.entries.forEach { filter ->
                            FilterChip(
                                selected = visualFilter == filter,
                                onClick = { visualFilter = filter },
                                label = { Text(stringResource(filter.label)) },
                            )
                        }
                    }
                    IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, stringResource(R.string.common_close)) }
                }
                if (access.allowed && !access.full) TextButton(onClick = { permission.launch(permissions) }, modifier = Modifier.padding(horizontal = 8.dp)) {
                    Text(stringResource(R.string.library_manage_access))
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (section == "albums" && selectedAlbum != null) {
                        IconButton(onClick = { selectedAlbum = null }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, allAlbumsLabel) }
                    }
                    Box(Modifier.weight(1f)) {
                        TextButton(onClick = { menuExpanded = true }) {
                            Text(
                                if (section == "recent") stringResource(R.string.library_recent)
                                else if (selectedAlbum == null) albumsLabel
                                else items.orEmpty().firstOrNull { it.albumId == selectedAlbum }?.albumName.orEmpty(),
                                modifier = Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                            Icon(Icons.Default.ArrowDropDown, chooseAlbumsLabel)
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(text = { Text(stringResource(R.string.library_recent)) }, onClick = { section = "recent"; selectedAlbum = null; menuExpanded = false })
                            DropdownMenuItem(text = { Text(albumsLabel) }, onClick = { section = "albums"; selectedAlbum = null; menuExpanded = false })
                        }
                    }
                    if (multiple && chosen.isNotEmpty()) TextButton(onClick = { chosen = arrayListOf() }) { Text(stringResource(R.string.library_clear)) }
                    Box {
                        IconButton(onClick = { sortExpanded = true }) { Icon(Icons.AutoMirrored.Filled.Sort, stringResource(R.string.library_sort)) }
                        DropdownMenu(expanded = sortExpanded, onDismissRequest = { sortExpanded = false }) {
                            LibrarySort.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(option.label)) }, onClick = { sort = option; sortExpanded = false },
                                    leadingIcon = { if (option == sort) Icon(Icons.Default.Check, null) else Spacer(Modifier.size(24.dp)) },
                                )
                            }
                        }
                    }
                }
                Box(Modifier.weight(1f)) {
                    when {
                        !access.allowed -> Column(
                            Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                        ) {
                            Text(stringResource(if (audioOnly) R.string.library_allow_audio else R.string.library_allow_visual))
                            Spacer(Modifier.height(16.dp))
                            Button(onClick = { permission.launch(permissions) }) { Text(stringResource(R.string.library_allow_access)) }
                        }
                        items == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                        filteredItems.isEmpty() || (section == "albums" && selectedAlbum != null && shown.isEmpty()) -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text(
                                stringResource(if (audioOnly) R.string.library_none_audio else when (visualFilter) {
                                    VisualFilter.LIBRARY -> R.string.library_none_any
                                    VisualFilter.VIDEOS -> R.string.library_none_videos
                                    VisualFilter.PHOTOS -> R.string.library_none_photos
                                }),
                                color = Palette.TextDim,
                            )
                        }
                        audioOnly -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp)) {
                            if (section == "albums" && selectedAlbum == null) {
                                items(albums.size, key = { albums[it].id }) { i ->
                                    val folder = albums[i]
                                    ListItem(
                                        headlineContent = { Text(folder.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                        supportingContent = { Text(pluralStringResource(R.plurals.library_files, folder.count, folder.count)) },
                                        leadingContent = { Icon(Icons.Default.Folder, null) },
                                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                        modifier = Modifier.clickable { selectedAlbum = folder.id },
                                    )
                                }
                            } else {
                                items(shown.size, key = { shown[it].uri.toString() }) { i ->
                                    val item = shown[i]
                                    val uri = item.uri.toString()
                                    val order = chosen.indexOf(uri)
                                    ListItem(
                                        headlineContent = { Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                        supportingContent = {
                                            Text(listOf(durationLabel(item.durationMs).takeIf { item.durationMs > 0 }, item.albumName).filterNotNull().joinToString(" · "),
                                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        },
                                        leadingContent = { Icon(Icons.Default.MusicNote, null) },
                                        trailingContent = { if (multiple) SelectionBadge(order) },
                                        colors = ListItemDefaults.colors(containerColor = if (order >= 0) Palette.AccentSoft else Color.Transparent),
                                        modifier = Modifier.semantics { if (multiple) selected = order >= 0 }
                                            .clickable { if (multiple) toggle(uri) else onChoose(listOf(item.uri)) },
                                    )
                                }
                            }
                        }
                        section == "albums" && selectedAlbum == null -> LazyVerticalGrid(
                            GridCells.Adaptive(110.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(albums, key = { it.id }) { album -> LibraryCell(album.cover, stringResource(R.string.library_album_label, album.name, album.count)) { selectedAlbum = album.id } }
                        }
                        else -> LazyVerticalGrid(
                            GridCells.Adaptive(110.dp),
                            Modifier.fillMaxSize().then(
                                if (multiple) Modifier.dragSelection(grid, gridKeys, chosen, GRID_PADDING, limit) { chosen = it } else Modifier
                            ),
                            state = grid, contentPadding = PaddingValues(GRID_PADDING),
                            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(shown, key = { it.uri.toString() }) { item ->
                                val uri = item.uri.toString()
                                val order = chosen.indexOf(uri)
                                LibraryCell(item, showName = false, order = if (multiple) order else null, enabled = !multiple || order >= 0 || chosen.size < limit) {
                                    if (multiple) toggle(uri) else onChoose(listOf(item.uri))
                                }
                            }
                        }
                    }
                }
                if (multiple) Row(
                    Modifier.fillMaxWidth().background(Palette.Surface).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.library_selected, chosen.size, limit), fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        Text(
                            stringResource(if (audioOnly) R.string.library_tap_hint_audio else R.string.library_tap_hint),
                            fontSize = 12.sp, color = Palette.TextDim,
                        )
                    }
                    Button(onClick = { onChoose(chosen.map(Uri::parse)) }, enabled = chosen.isNotEmpty()) { Text(stringResource(R.string.library_add, chosen.size)) }
                }
            }
        }
    }
}

@Composable
private fun SelectionBadge(order: Int) {
    Box(
        Modifier.size(24.dp).clip(CircleShape)
            .background(if (order >= 0) Palette.Accent else Color.Black.copy(alpha = 0.3f))
            .border(1.5.dp, Color.White, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (order >= 0) Text("${order + 1}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun LibraryCell(item: LibraryItem, label: String = item.name, showName: Boolean = true, order: Int? = null, enabled: Boolean = true, onClick: () -> Unit) {
    val context = LocalContext.current
    val thumbnail by produceState<Bitmap?>(null, item.uri) {
        value = if (item.audio) null else withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.loadThumbnail(item.uri, Size(260, 260), null) }.getOrNull()
        }
    }
    val picked = order != null && order >= 0
    Column(
        Modifier.clip(RoundedCornerShape(8.dp)).clickable(enabled = enabled, onClick = onClick).semantics { if (order != null) selected = picked },
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).background(Palette.Surface), contentAlignment = Alignment.Center) {
            if (item.audio) Icon(Icons.Default.MusicNote, null, Modifier.size(48.dp))
            else thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            if (picked) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)).border(3.dp, Palette.Accent, RoundedCornerShape(8.dp)))
            if (!enabled) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)))
            if (item.video && item.durationMs > 0) Text(
                durationLabel(item.durationMs), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 1.dp),
            )
            if (order != null) Box(Modifier.align(Alignment.TopEnd).padding(5.dp)) { SelectionBadge(order) }
        }
        if (showName) Text(label, Modifier.padding(horizontal = 4.dp, vertical = 3.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 11.sp)
    }
}
