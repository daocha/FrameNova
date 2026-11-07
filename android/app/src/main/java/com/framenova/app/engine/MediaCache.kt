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

    private fun frameAt(asset: MediaAsset, timeUs: Long, heightPx: Int, option: Int = MediaMetadataRetriever.OPTION_CLOSEST_SYNC): Bitmap? {
        val r = retrievers.getOrPut(asset.id) { MediaMetadataRetriever().apply { setDataSource(context, Uri.parse(asset.uri)) } }
        synchronized(r) {
            val w = max(1, heightPx * asset.width / max(1, asset.height))
            return r.getScaledFrameAtTime(timeUs, option, w, heightPx)
        }
    }

    private data class ScrubRequest(val timeUs: Long, val heightPx: Int)
    private val scrubWanted = ConcurrentHashMap<String, ScrubRequest>()
    private val scrubRunning = ConcurrentHashMap.newKeySet<String>()
    private val scrubLast = ConcurrentHashMap<String, ImageBitmap>()

    /**
     * A frame of [asset] at source time [timeUs] for scrubbing and live layer gestures, shown instead of the player
     * (whose rebuilds are too slow to follow a finger). Only the latest request per asset is decoded, so a fast swipe
     * never queues up stale frames; until it is ready the previous frame is returned.
     */
    fun scrubFrame(asset: MediaAsset, timeUs: Long, heightPx: Int): ImageBitmap? {
        if (asset.type == MediaType.IMAGE) return thumbnail(asset, 0, 1, heightPx)
        val t = timeUs / SCRUB_STEP_US * SCRUB_STEP_US
        val key = "${asset.id}@scrub$t@$heightPx"
        thumbs.get(key)?.let { scrubLast[asset.id] = it; return it }
        scrubWanted[asset.id] = ScrubRequest(t, heightPx)
        if (scrubRunning.add(asset.id)) scope.launch {
            try {
                while (true) {
                    val want = scrubWanted[asset.id] ?: break
                    val k = "${asset.id}@scrub${want.timeUs}@${want.heightPx}"
                    if (thumbs.get(k) == null) {
                        val bmp = try { frameAt(asset, want.timeUs, want.heightPx, MediaMetadataRetriever.OPTION_CLOSEST) } catch (_: Exception) { null }
                        if (bmp != null) {
                            val image = bmp.asImageBitmap()
                            thumbs.put(k, image)
                            scrubLast[asset.id] = image
                            version.intValue++
                        }
                    }
                    if (scrubWanted.remove(asset.id, want)) break
                }
            } finally { scrubRunning.remove(asset.id) }
        }
        // Keep the last preview-quality frame while decoding catches up. Switching back to a 128px filmstrip
        // whenever a swipe moves more than a second made the entire preview visibly blurry during fast scrubs.
        // The filmstrip is only a placeholder until this asset's first scrub frame is ready.
        return scrubLast[asset.id] ?: filmstripFrame(asset, timeUs)
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

    /*
     * Filmstrips. Each video clip gets frames spread over its whole length, one per second (at least 10, at most
     * MAX_STRIP_FRAMES), taken at keyframes (fast: no long decodes of the original) and written to the cache directory,
     * so a project opens with its filmstrips at once. Missing frames are made in the background, coarse to fine: ten
     * spread over the clip first, then the gaps, so the whole clip shows something within moments. The timeline (at
     * any zoom) and the quick preview use the nearest frame.
     */
    private class Strip(val count: Int, val durationUs: Long) { val frames = arrayOfNulls<ImageBitmap>(count) }
    private val strips = ConcurrentHashMap<String, Strip>()
    private val stripJobs = ConcurrentHashMap<String, kotlinx.coroutines.Job>()
    /** Two clips at a time, each with its own decoder session. */
    private val stripSlots = Semaphore(2)

    private fun stripDir(asset: MediaAsset): File {
        val raw = "${asset.uri}|${asset.durationUs}|$STRIP_HEIGHT|v1"
        val key = java.security.MessageDigest.getInstance("SHA-1").digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }.take(24)
        return File(File(context.cacheDir, "filmstrip"), key)
    }

    /** Loads [asset]'s filmstrip from the cache and makes the missing frames in the background. */
    fun prepareFilmstrip(asset: MediaAsset) {
        if (asset.type != MediaType.VIDEO || asset.durationUs <= 0) return
        if (stripJobs[asset.id]?.isActive == true || strips[asset.id]?.frames?.all { it != null } == true) return
        val count = (asset.durationUs / 1_000_000L).toInt().coerceIn(10, MAX_STRIP_FRAMES)
        val strip = strips.getOrPut(asset.id) { Strip(count, asset.durationUs) }
        stripJobs[asset.id] = scope.launch {
            val dir = stripDir(asset).apply { mkdirs() }
            // Cached frames first: these show at once.
            val load = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.RGB_565 }
            for (i in 0 until strip.count) {
                if (strip.frames[i] != null) continue
                val f = File(dir, "$i.jpg")
                if (f.isFile) runCatching { BitmapFactory.decodeFile(f.path, load) }.getOrNull()?.let { strip.frames[i] = it.asImageBitmap() }
            }
            version.intValue++
            val missing = coarseToFine(strip.count).filter { strip.frames[it] == null }
            if (missing.isEmpty()) return@launch
            // Ten frames per turn: the first ten of every clip come before the rest of any, and clips then take turns
            // (the semaphore is fair), so no clip waits for another to finish.
            val r = MediaMetadataRetriever()
            try {
                r.setDataSource(context, Uri.parse(asset.uri))
                val h = STRIP_HEIGHT
                val w = max(1, h * asset.width / max(1, asset.height))
                val started = System.currentTimeMillis()
                var made = 0
                for (batch in missing.chunked(10)) {
                    stripSlots.withPermit {
                        for (i in batch) {
                            kotlinx.coroutines.yield() // stops here when the editor closes
                            val t = strip.durationUs * (2L * i + 1) / (2L * strip.count)
                            val frame = runCatching { r.getScaledFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, w, h) }.getOrNull() ?: continue
                            runCatching { File(dir, "$i.jpg").outputStream().use { frame.compress(Bitmap.CompressFormat.JPEG, 82, it) } }
                            strip.frames[i] = (frame.copy(Bitmap.Config.RGB_565, false) ?: frame).asImageBitmap()
                            made++
                        }
                    }
                    version.intValue++
                }
                android.util.Log.i(com.framenova.app.LOG_TAG, "Filmstrip of ${asset.name}: $made frames in ${System.currentTimeMillis() - started} ms")
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                android.util.Log.w(com.framenova.app.LOG_TAG, "Filmstrip of ${asset.name} not made", e)
            } finally { r.release() }
        }
    }

    /** The filmstrip frame nearest source time [timeUs] of [asset], or null until one is available. */
    fun filmstripFrame(asset: MediaAsset, timeUs: Long): ImageBitmap? {
        val strip = strips[asset.id] ?: run { prepareFilmstrip(asset); return null }
        val i = (timeUs * strip.count / strip.durationUs.coerceAtLeast(1)).toInt().coerceIn(0, strip.count - 1)
        for (d in 0 until strip.count) {
            strip.frames.getOrNull(i - d)?.let { return it }
            strip.frames.getOrNull(i + d)?.let { return it }
        }
        return null
    }

    /** Slot indices ordered so the first ten are spread over the clip, then the gaps between them fill in. */
    private fun coarseToFine(count: Int): List<Int> {
        val order = LinkedHashSet<Int>()
        var stride = max(1, count / 10)
        while (true) {
            for (i in 0 until count step stride) order += i
            if (stride == 1) break
            stride = max(1, stride / 2)
        }
        return order.toList()
    }

    fun release() {
        stripJobs.values.forEach { it.cancel() }
        stripJobs.clear()
        retrievers.values.forEach { runCatching { it.release() } }
        retrievers.clear()
    }

    companion object {
        const val PEAK_US = 20_000L
        private const val SCRUB_STEP_US = 1_000_000L / 30
        /** Filmstrip frame height in pixels, and the most frames per clip. */
        private const val STRIP_HEIGHT = 128
        private const val MAX_STRIP_FRAMES = 120
    }
}
