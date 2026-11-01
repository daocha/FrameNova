package com.framenova.app.data

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.net.Uri
import com.framenova.app.engine.MediaProbe
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import com.framenova.app.model.Project
import com.framenova.app.model.newId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream

data class ProjectSummary(val id: String, val name: String, val modifiedAt: Long, val durationUs: Long, val aspect: String, val cover: File?)

/** Projects live in files/projects/<id>/ as project.json plus a cover and any captured stills or voiceovers. */
class ProjectRepository(context: Context) {
    private val app = context.applicationContext
    private val root = File(app.filesDir, "projects").apply { mkdirs() }

    companion object {
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = false; prettyPrint = false }
    }

    fun dir(id: String): File = File(root, id).apply { mkdirs() }

    fun list(): List<ProjectSummary> = root.listFiles()?.mapNotNull { d ->
        val p = load(d.name) ?: return@mapNotNull null
        ProjectSummary(p.id, p.name, p.modifiedAt, p.durationUs, p.canvas.aspect.label, File(d, "cover.jpg").takeIf { it.isFile })
    }?.sortedByDescending { it.modifiedAt } ?: emptyList()

    fun load(id: String): Project? = try {
        File(File(root, id), "project.json").takeIf { it.isFile }?.readText()?.let { json.decodeFromString(Project.serializer(), it) }
    } catch (_: Exception) { null }

    /** Writes atomically so a crash mid-save never corrupts the project. */
    fun save(project: Project) {
        val d = dir(project.id)
        val tmp = File(d, "project.json.tmp")
        FileOutputStream(tmp).use { out ->
            out.write(json.encodeToString(Project.serializer(), project).toByteArray())
            out.fd.sync()
        }
        if (!tmp.renameTo(File(d, "project.json"))) error("Could not save project")
    }

    fun delete(id: String) { File(root, id).deleteRecursively() }

    fun duplicate(id: String, now: Long): Project? {
        val p = load(id) ?: return null
        val copy = p.copy(id = newId(), name = p.name + " copy", createdAt = now, modifiedAt = now)
        File(root, id).copyRecursively(dir(copy.id), overwrite = true)
        // Internal files (stills, voiceovers) moved with the folder: point their URIs at the copy.
        val fixed = copy.copy(assets = copy.assets.map { a ->
            if (a.uri.startsWith("file:") && a.uri.contains("/projects/$id/")) a.copy(uri = a.uri.replace("/projects/$id/", "/projects/${copy.id}/")) else a
        })
        save(fixed)
        return fixed
    }

    fun rename(id: String, name: String) { load(id)?.let { save(it.copy(name = name)) } }

    suspend fun writeCover(project: Project) = withContext(Dispatchers.IO) {
        val clip = project.mainTrack.clips.firstOrNull() ?: project.tracks.flatMap { it.clips }.firstOrNull { it.assetId != null } ?: return@withContext
        val asset = project.asset(clip.assetId) ?: return@withContext
        val bmp = try { frame(asset, clip.srcInUs, 360) } catch (_: Exception) { null } ?: return@withContext
        FileOutputStream(File(dir(project.id), "cover.jpg")).use { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }
    }

    private fun frame(asset: MediaAsset, timeUs: Long, height: Int): Bitmap? = when (asset.type) {
        MediaType.IMAGE -> app.contentResolver.openInputStream(Uri.parse(asset.uri))?.use { android.graphics.BitmapFactory.decodeStream(it) }
            ?.let { Bitmap.createScaledBitmap(it, (it.width * height / it.height.coerceAtLeast(1)).coerceAtLeast(1), height, true) }
        MediaType.VIDEO -> MediaMetadataRetriever().run {
            try {
                setDataSource(app, Uri.parse(asset.uri))
                getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, height * asset.width / asset.height.coerceAtLeast(1), height)
            } finally { release() }
        }
        MediaType.AUDIO -> null
    }

    /** Captures the full-resolution frame at [sourceUs] as a PNG still inside the project. */
    suspend fun captureStill(projectId: String, asset: MediaAsset, sourceUs: Long): MediaAsset? = withContext(Dispatchers.IO) {
        val bmp = when (asset.type) {
            MediaType.VIDEO -> MediaMetadataRetriever().run {
                try { setDataSource(app, Uri.parse(asset.uri)); getFrameAtTime(sourceUs, MediaMetadataRetriever.OPTION_CLOSEST) } finally { release() }
            }
            MediaType.IMAGE -> return@withContext asset
            else -> null
        } ?: return@withContext null
        val file = File(File(dir(projectId), "stills").apply { mkdirs() }, "still_${newId()}.png")
        FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        MediaProbe.probe(app, Uri.fromFile(file), "image/png")?.copy(name = "Freeze frame")
    }

    fun voiceFile(projectId: String): File = File(File(dir(projectId), "voice").apply { mkdirs() }, "voice_${newId()}.m4a")
}

/** Records the microphone to AAC for voiceovers. */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    var file: File? = null
        private set

    fun start(target: File) {
        file = target
        @Suppress("DEPRECATION")
        val r = if (android.os.Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
        recorder = r.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(48_000)
            setAudioEncodingBitRate(192_000)
            setAudioChannels(1)
            setOutputFile(target.absolutePath)
            prepare()
            start()
        }
    }

    fun stop(): File? {
        val r = recorder ?: return null
        recorder = null
        return try { r.stop(); file } catch (_: Exception) { file?.delete(); null } finally { r.release() }
    }

    val maxAmplitude: Int get() = try { recorder?.maxAmplitude ?: 0 } catch (_: Exception) { 0 }
}
