package com.framenova.app.engine

import com.framenova.app.LOG_TAG
import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import com.framenova.app.model.newId

object MediaProbe {
    fun probe(context: Context, uri: Uri, mimeHint: String? = null): MediaAsset? = try {
        val mime = mimeHint ?: context.contentResolver.getType(uri) ?: ""
        val name = displayName(context, uri)
        when {
            mime.startsWith("image/") -> probeImage(context, uri, name)
            else -> probeAv(context, uri, name, mime)
        }
    } catch (e: Exception) {
        android.util.Log.w(LOG_TAG, "Could not read $uri", e)
        null
    }

    /** The tracks of a media file as the decoders see them (codec, size, frame rate, profile, colour), for the log. */
    fun describeTracks(context: Context, uri: Uri): String = try {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(context, uri, null)
            (0 until ex.trackCount).joinToString("; ") { i ->
                val f = ex.getTrackFormat(i)
                fun int(k: String) = if (f.containsKey(k)) f.getInteger(k).toString() else null
                listOfNotNull(
                    f.getString(MediaFormat.KEY_MIME),
                    int(MediaFormat.KEY_WIDTH)?.let { "${it}x${int(MediaFormat.KEY_HEIGHT)}" },
                    int(MediaFormat.KEY_FRAME_RATE)?.let { "${it}fps" },
                    int(MediaFormat.KEY_PROFILE)?.let { "profile $it" },
                    int(MediaFormat.KEY_LEVEL)?.let { "level $it" },
                    int(MediaFormat.KEY_COLOR_TRANSFER)?.let { "transfer $it" },
                    int(MediaFormat.KEY_COLOR_STANDARD)?.let { "standard $it" },
                    int("rotation-degrees")?.let { "rotation $it" },
                    int(MediaFormat.KEY_SAMPLE_RATE)?.let { "${it}Hz" },
                    int(MediaFormat.KEY_CHANNEL_COUNT)?.let { "${it}ch" },
                ).joinToString(" ")
            }
        } finally { ex.release() }
    } catch (e: Exception) { "unreadable ($e)" }

    fun displayName(context: Context, uri: Uri): String {
        if (uri.scheme == "file") return uri.lastPathSegment ?: "media"
        return try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            } ?: uri.lastPathSegment ?: "media"
        } catch (_: Exception) { uri.lastPathSegment ?: "media" }
    }

    private fun probeImage(context: Context, uri: Uri, name: String): MediaAsset? {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null
        val rotation = try {
            context.contentResolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0
        } catch (_: Exception) { 0 }
        val (w, h) = if (rotation % 180 != 0) opts.outHeight to opts.outWidth else opts.outWidth to opts.outHeight
        return MediaAsset(id = newId(), uri = uri.toString(), type = MediaType.IMAGE, name = name, durationUs = 0, width = w, height = h, hasVideo = true)
    }

    private fun probeAv(context: Context, uri: Uri, name: String, mime: String): MediaAsset? {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            val hasVideo = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val hasAudio = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes" || mime.startsWith("audio/")
            val durationMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            if (durationMs <= 0) return null
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation % 180 != 0) { val t = w; w = h; h = t }
            var hdr = false
            var fps = 0f
            if (hasVideo) {
                val ex = MediaExtractor()
                try {
                    ex.setDataSource(context, uri, null)
                    for (i in 0 until ex.trackCount) {
                        val f = ex.getTrackFormat(i)
                        if (f.getString(MediaFormat.KEY_MIME)?.startsWith("video/") != true) continue
                        if (f.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) {
                            val transfer = f.getInteger(MediaFormat.KEY_COLOR_TRANSFER)
                            hdr = transfer == MediaFormat.COLOR_TRANSFER_ST2084 || transfer == MediaFormat.COLOR_TRANSFER_HLG
                        }
                        if (f.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                            fps = try { f.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat() } catch (_: Exception) { f.getFloat(MediaFormat.KEY_FRAME_RATE) }
                        }
                        break
                    }
                } catch (_: Exception) {
                } finally { ex.release() }
            }
            return MediaAsset(
                id = newId(), uri = uri.toString(), type = if (hasVideo) MediaType.VIDEO else MediaType.AUDIO, name = name,
                durationUs = durationMs * 1000, width = if (hasVideo) w else 0, height = if (hasVideo) h else 0,
                hasAudio = hasAudio, hasVideo = hasVideo, isHdr = hdr, frameRate = fps,
            )
        } finally { r.release() }
    }
}
