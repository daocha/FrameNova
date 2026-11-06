package com.framenova.app

import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.framenova.app.ui.theme.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** The log tag of FrameNova's own lines, which the developer log shows in full. */
const val LOG_TAG = "FrameNova"

/**
 * Hidden developer tools, unlocked by tapping the version in Settings ten times: this app's own recent log,
 * to read, copy or share when reporting a problem. Nothing leaves the device unless the user shares it.
 * Unlocking lasts until the next update.
 */
object DevTools {
    const val UNLOCK_TAPS = 10
    private const val KEY = "dev_tools_install"
    /** Sharing and the clipboard pass text through a binder transaction, which fails above about 1 MB. */
    private const val SHARE_LIMIT = 400_000

    private fun prefs(context: Context) = context.getSharedPreferences("preferences", 0)
    /** Changes with every install or update, including debug builds, whose BuildConfig version code stays fixed. */
    private fun installed(context: Context) = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    fun enabled(context: Context) = runCatching { prefs(context).getLong(KEY, -1L) == installed(context) }.getOrDefault(false)
    fun enable(context: Context) = prefs(context).edit().putLong(KEY, installed(context)).apply()
    fun disable(context: Context) = prefs(context).edit().remove(KEY).apply()

    /** Where saved logs go, so they can be copied off the phone. */
    const val FOLDER = "FrameNova"

    /**
     * Writes a file to Download/[FOLDER]/[subfolder], replacing one this app saved there under the same name,
     * and returns its path as the Files app shows it.
     */
    fun saveDownload(context: Context, subfolder: String, name: String, mime: String, write: (java.io.OutputStream) -> Unit): String {
        val resolver = context.contentResolver
        val folder = "${android.os.Environment.DIRECTORY_DOWNLOADS}/$FOLDER/$subfolder/"
        val collection = android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI
        runCatching {
            resolver.delete(collection, "${android.provider.MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                "${android.provider.MediaStore.MediaColumns.RELATIVE_PATH} = ?", arrayOf(name, folder))
        }
        val uri = resolver.insert(collection, android.content.ContentValues().apply {
            put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
            put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, folder)
        }) ?: error("no Downloads entry for $name")
        resolver.openOutputStream(uri)?.use(write) ?: error("cannot write $uri")
        return folder + name
    }

    /** Writes the whole log since it was last cleared (no share limit) to the document the user chose; true on success. */
    suspend fun saveLogTo(context: Context, uri: android.net.Uri, text: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write((header() + text).toByteArray()) } ?: error("cannot write $uri")
        }.onFailure { android.util.Log.w(LOG_TAG, "Log not saved", it) }.isSuccess
    }

    private fun header() = "FrameNova ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} · " +
        "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})${chipset()}\n\n"

    /** The chipset, which decides the hardware decoders (Android 12 and later). */
    private fun chipset(): String = if (android.os.Build.VERSION.SDK_INT >= 31) " · ${android.os.Build.SOC_MANUFACTURER} ${android.os.Build.SOC_MODEL}" else ""

    /** When the log was last cleared, in epoch milliseconds; lines before it are left out. */
    private var clearedAt = 0L

    /** An app cannot erase the system log, so clearing hides everything written before now. */
    fun clear(context: Context) {
        clearedAt = System.currentTimeMillis()
        crashFile(context).delete()
    }

    /**
     * The app's own log lines since it last started: every FrameNova line, plus warnings and errors from the libraries
     * and Android's media framework in this process (decoder and preview errors are logged there). A crash ends the
     * process, and with it that log, so the last crash is kept in a file ([recordCrashes]) and shown first.
     * An app may read its own log without any permission.
     */
    suspend fun log(context: Context): String = withContext(Dispatchers.IO) {
        val crash = runCatching { crashFile(context).takeIf { it.isFile }?.readText() }.getOrNull()
        val lines = runCatching {
            val since = if (clearedAt > 0) listOf("-T", "%d.%03d".format(java.util.Locale.ROOT, clearedAt / 1000, clearedAt % 1000)) else listOf("-t", "3000")
            val process = ProcessBuilder(listOf("logcat", "-d", "-v", "time", "--pid=${android.os.Process.myPid()}") + since + listOf("$LOG_TAG:V", "*:W"))
                .redirectErrorStream(true).start()
            process.inputStream.bufferedReader().use { it.readText() }.also { process.waitFor() }
        }.getOrElse { "Could not read the log: $it" }
        if (crash != null) "----- Last crash -----\n$crash\n----- Log since the app started -----\n$lines" else lines
    }

    /** The end of [log], short enough to share or copy. */
    fun shareable(log: String): String = header() + log.takeLast(SHARE_LIMIT)

    private fun crashFile(context: Context) = File(context.filesDir, "last_crash.txt")

    /** Keeps the stack trace of an uncaught exception, which the log of the next start cannot show. */
    fun recordCrashes(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val stamp = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())
                crashFile(app).writeText("$stamp on thread ${thread.name}\n${android.util.Log.getStackTraceString(error)}")
            }
            previous?.uncaughtException(thread, error)
        }
    }
}

/** Returns a function that asks where to save the log (the system save dialog), then writes it there. */
@Composable
fun rememberLogSaver(): (String?) -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<String?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        val text = pending
        pending = null
        if (uri != null && text != null) scope.launch {
            val saved = DevTools.saveLogTo(context, uri, text)
            android.widget.Toast.makeText(context, if (saved) "Log saved" else "Could not save the log", android.widget.Toast.LENGTH_LONG).show()
        }
    }
    return { log ->
        scope.launch {
            pending = log ?: DevTools.log(context)
            val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.ROOT).format(java.util.Date())
            launcher.launch("FrameNova-log-$stamp.txt")
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DevLogPanel(dismiss: () -> Unit) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val saveLog = rememberLogSaver()
    var log by remember { mutableStateOf<String?>(null) }
    val vertical = rememberScrollState()
    suspend fun refresh() {
        log = DevTools.log(context)
        vertical.scrollTo(Int.MAX_VALUE)
    }
    LaunchedEffect(Unit) { refresh() }
    Dialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = Palette.Bg, contentColor = Palette.Text) {
            Column(Modifier.fillMaxSize().systemBarsPadding().padding(12.dp)) {
                Text("Developer logs", fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                Text("FrameNova ${BuildConfig.VERSION_NAME} · ${android.os.Build.MODEL} · Android ${android.os.Build.VERSION.RELEASE}",
                    fontSize = 11.sp, color = Palette.TextDim)
                Spacer(Modifier.height(8.dp))
                Surface(Modifier.weight(1f).fillMaxWidth(), color = Palette.Surface, shape = MaterialTheme.shapes.small) {
                    SelectionContainer {
                        Text(log?.takeIf { it.lines().any { line -> line.isNotBlank() && !line.startsWith("-----") } }
                            ?: if (log == null) "Reading…" else "No log lines yet.",
                            Modifier.verticalScroll(vertical).horizontalScroll(rememberScrollState()).padding(8.dp),
                            fontFamily = FontFamily.Monospace, fontSize = 9.sp, lineHeight = 11.sp, softWrap = false)
                    }
                }
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { scope.launch { refresh() } }) { Text("Refresh") }
                    TextButton(onClick = { DevTools.clear(context); scope.launch { refresh() } }) { Text("Clear") }
                    TextButton(onClick = { log?.let { scope.launch { clipboard.setClipEntry(ClipEntry(android.content.ClipData.newPlainText("FrameNova log", DevTools.shareable(it)))) } } }, enabled = log != null) {
                        Text("Copy")
                    }
                    TextButton(onClick = {
                        val text = log ?: return@TextButton
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, "FrameNova log")
                            .putExtra(Intent.EXTRA_TEXT, DevTools.shareable(text)), null))
                    }, enabled = log != null) { Text("Share") }
                    TextButton(onClick = { log?.let { saveLog(it) } }, enabled = log != null) {
                        Text("Save")
                    }
                    TextButton(onClick = dismiss) { Text("Close") }
                }
            }
        }
    }
}
