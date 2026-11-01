package com.framenova.app.engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.LruCache
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.exifinterface.media.ExifInterface
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.max

/**
 * Filmstrip thumbnails and audio waveforms for the timeline, loaded in the background. [version] changes whenever
 * something new is ready so the timeline redraws.
 */
class MediaCache(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val thumbs = object : LruCache<String, ImageBitmap>(48 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
    }
    private val pending = ConcurrentHashMap.newKeySet<String>()
    private val peaks = ConcurrentHashMap<String, FloatArray>()
    private val peaksPending = ConcurrentHashMap.newKeySet<String>()
    private val retrievers = ConcurrentHashMap<String, MediaMetadataRetriever>()
    private val decodeSlots = Semaphore(2)
    val version = mutableIntStateOf(0)

    /** Thumbnail of [asset] near source time [timeUs], quantized to [stepUs]; null until loaded. */
    fun thumbnail(asset: MediaAsset, timeUs: Long, stepUs: Long, heightPx: Int): ImageBitmap? {
        val t = if (asset.type == MediaType.IMAGE) 0 else (timeUs / stepUs) * stepUs
        val key = "${asset.id}@$t@$heightPx"
        thumbs.get(key)?.let { return it }
        if (pending.add(key)) scope.launch {
            decodeSlots.withPermit {
                try {
                    val bmp = if (asset.type == MediaType.IMAGE) decodeImage(asset, heightPx) else frameAt(asset, t, heightPx)
                    if (bmp != null) { thumbs.put(key, bmp.asImageBitmap()); version.intValue++ }
                } catch (_: Exception) {
                } finally { pending.remove(key) }
            }
        }
        return null
    }

    private fun frameAt(asset: MediaAsset, timeUs: Long, heightPx: Int): Bitmap? {
        val r = retrievers.getOrPut(asset.id) { MediaMetadataRetriever().apply { setDataSource(context, Uri.parse(asset.uri)) } }
        synchronized(r) {
            val w = max(1, heightPx * asset.width / max(1, asset.height))
            return r.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, w, heightPx)
        }
    }

    private fun decodeImage(asset: MediaAsset, heightPx: Int): Bitmap? {
        val uri = Uri.parse(asset.uri)
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
        var sample = 1
        while (opts.outHeight / (sample * 2) >= heightPx && opts.outWidth / (sample * 2) >= heightPx) sample *= 2
        val bmp = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = try { context.contentResolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0 } catch (_: Exception) { 0 }
        if (rotation == 0) return bmp
        val m = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
    }

    /** Peak levels (0..1) per [PEAK_US] of source audio; null until decoded. */
    fun peaks(asset: MediaAsset): FloatArray? {
        peaks[asset.id]?.let { return it }
        if (!asset.hasAudio) return null
        if (peaksPending.add(asset.id)) scope.launch {
            decodeSlots.withPermit {
                try {
                    val file = File(File(context.cacheDir, "peaks"), "${asset.id}.bin")
                    val data = readPeaks(file) ?: decodePeaks(asset)?.also { writePeaks(file, it) }
                    if (data != null) { peaks[asset.id] = data; version.intValue++ }
                } catch (_: Exception) {
                } finally { peaksPending.remove(asset.id) }
            }
        }
        return null
    }

    private fun readPeaks(file: File): FloatArray? = try {
        if (!file.isFile) null else DataInputStream(file.inputStream().buffered()).use { s -> FloatArray(s.readInt()) { s.readByte().toInt().and(0xFF) / 255f } }
    } catch (_: Exception) { null }

    private fun writePeaks(file: File, data: FloatArray) {
        file.parentFile?.mkdirs()
        DataOutputStream(file.outputStream().buffered()).use { s -> s.writeInt(data.size); data.forEach { s.writeByte((it * 255).toInt()) } }
    }

    /** Decodes the audio track to PCM and keeps the absolute peak of every [PEAK_US] window. */
    private fun decodePeaks(asset: MediaAsset): FloatArray? {
        val ex = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            ex.setDataSource(context, Uri.parse(asset.uri), null)
            val track = (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return null
            ex.selectTrack(track)
            val format = ex.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val out = FloatArray((asset.durationUs / PEAK_US + 1).toInt().coerceAtMost(200_000))
            codec = MediaCodec.createDecoderByType(mime).apply { configure(format, null, null, 0); start() }
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var samplesSeen = 0L
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(5_000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) { codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                        else { codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0); ex.advance() }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 5_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                } else if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buf.position(info.offset); buf.limit(info.offset + info.size)
                    val shorts = buf.asShortBuffer()
                    var idx = 0
                    while (idx + channels <= shorts.remaining()) {
                        val v = abs(shorts.get(idx).toInt()) / 32768f
                        val bin = (samplesSeen * 1_000_000L / rate / PEAK_US).toInt()
                        if (bin in out.indices && v > out[bin]) out[bin] = v
                        samplesSeen++
                        idx += channels
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            return out
        } catch (_: Exception) {
            return null
        } finally {
            try { codec?.stop(); codec?.release() } catch (_: Exception) {}
            ex.release()
        }
    }

    fun release() {
        retrievers.values.forEach { runCatching { it.release() } }
        retrievers.clear()
    }

    companion object { const val PEAK_US = 20_000L }
}
