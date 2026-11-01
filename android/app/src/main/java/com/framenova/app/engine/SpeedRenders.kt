package com.framenova.app.engine

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.framenova.app.model.Clip
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Speed-changed video clips are rendered once, on their own, at source resolution and a high bitrate. Compositions then
 * use the render at normal speed: in Media3 1.9 a speed change inside a multi-layer composition can stall the pipeline
 * (see ExportBisectTest), while a single clip renders reliably.
 */
@UnstableApi
object SpeedRenders {
    fun needsRender(clip: Clip, asset: MediaAsset?): Boolean =
        asset != null && asset.type == MediaType.VIDEO && clip.speed != 1f && !clip.audioOnly

    private fun key(clip: Clip, asset: MediaAsset): String {
        val raw = "${asset.uri}|${clip.srcInUs}|${clip.srcOutUs}|${clip.speed}|v1"
        return MessageDigest.getInstance("SHA-1").digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }.take(24)
    }

    private fun dir(context: Context) = File(context.cacheDir, "speed").apply { mkdirs() }

    fun file(context: Context, clip: Clip, asset: MediaAsset): File = File(dir(context), key(clip, asset) + ".mp4")

    /** The finished render for [clip], or null. */
    fun ready(context: Context, clip: Clip, asset: MediaAsset): File? = file(context, clip, asset).takeIf { it.isFile && it.length() > 0 }

    /** Swaps a speed-changed clip for its render at normal speed, keeping the clip's id and timeline position. */
    fun substitute(context: Context, clip: Clip, asset: MediaAsset): Pair<Clip, MediaAsset>? {
        if (!needsRender(clip, asset)) return null
        val f = ready(context, clip, asset) ?: return null
        val durUs = durationUs(f) ?: return null
        val renderedAsset = asset.copy(id = asset.id + "@" + f.nameWithoutExtension, uri = Uri.fromFile(f).toString(), durationUs = durUs, isHdr = false)
        val end = minOf(durUs, clip.durationUs)
        return clip.copy(srcInUs = 0, srcOutUs = end, speed = 1f, keyframes = clip.keyframes) to renderedAsset
    }

    private val durations = java.util.concurrent.ConcurrentHashMap<String, Long>()

    private fun durationUs(f: File): Long? = durations[f.path] ?: run {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(f.path)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.times(1000)?.also { durations[f.path] = it }
        } catch (_: Exception) { null } finally { r.release() }
    }

    /** Renders [clip] (source range and speed only) to its cache file. Safe to call again: returns the existing file. */
    suspend fun render(context: Context, clip: Clip, asset: MediaAsset): File {
        ready(context, clip, asset)?.let { return it }
        val target = file(context, clip, asset)
        val part = File(target.parentFile, target.name + ".part.mp4")
        part.delete()
        val app = context.applicationContext
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { cont ->
                val item = MediaItem.Builder().setUri(Uri.parse(asset.uri)).setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder().setStartPositionUs(clip.srcInUs).setEndPositionUs(clip.srcOutUs).build()
                ).build()
                @Suppress("DEPRECATION")
                val speedPair = Effects.createExperimentalSpeedChangingEffect(Constant(clip.speed))
                val audioSpeed = speedPair.first
                val videoSpeed = speedPair.second
                val edited = EditedMediaItem.Builder(item)
                    .setDurationUs(asset.durationUs)
                    .setRemoveAudio(!asset.hasAudio)
                    .setEffects(Effects(if (asset.hasAudio) listOf(audioSpeed) else emptyList(), listOf(videoSpeed)))
                    .build()
                val types = if (asset.hasAudio) setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO) else setOf(C.TRACK_TYPE_VIDEO)
                val composition = Composition.Builder(EditedMediaItemSequence.Builder(types).addItem(edited).build())
                    .setHdrMode(if (asset.isHdr) Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL else Composition.HDR_MODE_KEEP_HDR)
                    .build()
                val fps = (if (asset.frameRate > 0) asset.frameRate else 30f).coerceAtMost(60f)
                // Visually lossless intermediate: about 0.3 bits per pixel at the source size.
                val bitrate = (asset.width.toLong() * asset.height * fps * 0.3f).toLong().coerceIn(8_000_000L, 200_000_000L).toInt()
                val transformer = Transformer.Builder(app)
                    .setVideoMimeType(MimeTypes.VIDEO_H265)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setEncoderFactory(
                        DefaultEncoderFactory.Builder(app).setEnableFallback(true).setRequestedVideoEncoderSettings(
                            VideoEncoderSettings.Builder().setBitrate(bitrate).setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR).build()
                        ).build()
                    )
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) { if (cont.isActive) cont.resume(Unit) }
                        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                            if (cont.isActive) cont.resumeWithException(IOException("Speed render failed: ${exportException.errorCodeName}", exportException))
                        }
                    }).build()
                transformer.start(composition, part.absolutePath)
                cont.invokeOnCancellation { Handler(Looper.getMainLooper()).post { transformer.cancel() } }
            }
        }
        if (!part.renameTo(target)) throw IOException("Could not save the speed render")
        return target
    }

    private class Constant(private val speed: Float) : SpeedProvider {
        override fun getSpeed(timeUs: Long): Float = speed
        override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
    }
}
