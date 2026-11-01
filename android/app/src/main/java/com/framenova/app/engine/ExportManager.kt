package com.framenova.app.engine

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaCodecInfo
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.framenova.app.model.CanvasSettings
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.Project
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

enum class ExportQuality(val label: String, val bitsPerPixel: Float) {
    STANDARD("Standard", 0.06f), HIGH("High", 0.11f), MAXIMUM("Maximum", 0.18f)
}

data class ExportSettings(
    val longSide: Int,
    val fps: Int,
    val hevc: Boolean = true,
    val quality: ExportQuality = ExportQuality.HIGH,
) {
    fun bitrate(width: Int, height: Int): Int {
        val raw = width.toLong() * height * fps * quality.bitsPerPixel * (if (hevc) 0.7f else 1f)
        return raw.toLong().coerceIn(2_000_000L, 150_000_000L).toInt()
    }
}

sealed interface ExportState {
    data object Idle : ExportState
    data class Running(val label: String, val progress: Int) : ExportState
    data class Done(val label: String, val uri: Uri, val displayName: String, val bytes: Long, val isAudio: Boolean) : ExportState
    data class Failed(val label: String, val message: String) : ExportState
}

/** Runs one export at a time on the main looper, keeping the process alive with [ExportService]. */
@UnstableApi
object ExportManager {
    private val _state = MutableStateFlow<ExportState>(ExportState.Idle)
    val state: StateFlow<ExportState> = _state
    private val main = Handler(Looper.getMainLooper())
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var transformer: Transformer? = null
    private var label = ""

    val busy: Boolean get() = _state.value is ExportState.Running

    fun estimateBytes(project: Project, settings: ExportSettings): Long {
        val size = CanvasSettings.sizeFor(project.canvas.aspect, settings.longSide)
        return (settings.bitrate(size.width, size.height) + 256_000L) / 8 * (project.durationUs / 1_000_000L).coerceAtLeast(1)
    }

    fun exportVideo(context: Context, project: Project, settings: ExportSettings) {
        if (busy || project.durationUs <= 0) return
        val app = context.applicationContext
        label = project.name
        val (composition, holder) = CompositionFactory.build(app, project, PlanMode.EXPORT, settings.longSide, settings.fps)
        val size = holder.plan
        val encoderSettings = VideoEncoderSettings.Builder()
            .setBitrate(settings.bitrate(size.outW, size.outH))
            .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
            .build()
        val mime = if (settings.hevc) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264
        val file = File(File(app.cacheDir, "export").apply { mkdirs() }, "export_${System.currentTimeMillis()}.mp4")
        val name = safeName(project.name) + "_" + System.currentTimeMillis() / 1000 + ".mp4"
        run(app, composition, file, mime, encoderSettings) { result ->
            saveToGallery(app, file, name, isAudio = false)
        }
    }

    /** Saves the audio of [asset] as an .m4a file in Music/FrameNova, without re-encoding when possible. */
    fun exportAudio(context: Context, asset: MediaAsset) {
        if (busy || !asset.hasAudio) return
        val app = context.applicationContext
        label = asset.name
        val file = File(File(app.cacheDir, "export").apply { mkdirs() }, "audio_${System.currentTimeMillis()}.m4a")
        val name = safeName(asset.name.substringBeforeLast('.')) + "_audio.m4a"
        fun composition(transmux: Boolean): Composition {
            val item = EditedMediaItem.Builder(MediaItem.fromUri(asset.uri)).setRemoveVideo(true).build()
            return Composition.Builder(EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO)).addItem(item).build()).setTransmuxAudio(transmux).build()
        }
        run(app, composition(true), file, null, null, onFailure = {
            // The source codec cannot go into an .m4a as is: encode to AAC instead.
            run(app, composition(false), file, null, null) { saveToGallery(app, file, name, isAudio = true) }
        }) { saveToGallery(app, file, name, isAudio = true) }
    }

    private fun run(
        app: Context, composition: Composition, file: File, videoMime: String?, encoder: VideoEncoderSettings?,
        onFailure: (() -> Unit)? = null, onDone: (ExportResult) -> Unit,
    ) {
        file.delete()
        // Heavy 4K compositions can pause output briefly; allow a generous stall before giving up.
        val builder = Transformer.Builder(app).setAudioMimeType(MimeTypes.AUDIO_AAC).setMaxDelayBetweenMuxerSamplesMs(60_000)
        if (videoMime != null) builder.setVideoMimeType(videoMime)
        builder.setEncoderFactory(
            DefaultEncoderFactory.Builder(app).setEnableFallback(true).apply { if (encoder != null) setRequestedVideoEncoderSettings(encoder) }.build()
        )
        builder.addListener(object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                transformer = null
                onDone(exportResult)
            }
            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                transformer = null
                file.delete()
                if (onFailure != null) onFailure()
                else finish(ExportState.Failed(label, exportException.cause?.message ?: exportException.message ?: "Export failed"))
            }
        })
        val t = builder.build()
        transformer = t
        _state.value = ExportState.Running(label, 0)
        ContextCompat.startForegroundService(app, Intent(app, ExportService::class.java))
        t.start(composition, file.absolutePath)
        pollProgress(t)
    }

    private fun pollProgress(t: Transformer) {
        val holder = ProgressHolder()
        main.postDelayed(object : Runnable {
            override fun run() {
                if (transformer !== t) return
                if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    _state.value = ExportState.Running(label, holder.progress.coerceIn(0, 99))
                }
                main.postDelayed(this, 300)
            }
        }, 300)
    }

    fun cancel() {
        transformer?.cancel()
        transformer = null
        finish(ExportState.Idle)
    }

    fun dismiss() { if (!busy) _state.value = ExportState.Idle }

    private fun finish(state: ExportState) {
        _state.value = state
    }

    private fun saveToGallery(app: Context, file: File, displayName: String, isAudio: Boolean) {
        _state.value = ExportState.Running(label, 99)
        io.launch {
            try {
                val collection = if (isAudio) MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                    put(MediaStore.MediaColumns.MIME_TYPE, if (isAudio) "audio/mp4" else "video/mp4")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, (if (isAudio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES) + "/FrameNova")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = app.contentResolver
                val uri = resolver.insert(collection, values) ?: error("Could not create the output file")
                resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out, 1 shl 20) } } ?: error("Could not write the output file")
                resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                val bytes = file.length()
                file.delete()
                main.post { finish(ExportState.Done(label, uri, displayName, bytes, isAudio)) }
            } catch (e: Exception) {
                file.delete()
                main.post { finish(ExportState.Failed(label, e.message ?: "Could not save")) }
            }
        }
    }

    private fun safeName(s: String): String = s.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "FrameNova" }.take(60)
}
