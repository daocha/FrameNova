package com.framenova.app.ui.editor

import com.framenova.app.LOG_TAG
import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.media3.common.util.UnstableApi
import com.framenova.app.data.ProjectRepository
import com.framenova.app.data.VoiceRecorder
import com.framenova.app.engine.ExportManager
import com.framenova.app.engine.ExportSettings
import com.framenova.app.engine.MediaCache
import com.framenova.app.engine.MediaProbe
import com.framenova.app.engine.PreviewEngine
import com.framenova.app.engine.SpeedRenders
import com.framenova.app.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlin.math.max

enum class Panel {
    NONE, SPEED, VOLUME, ADJUST, FILTER, CROP, TRANSFORM, TRANSITION, LAYOUT, CANVAS,
    TEXT_EDIT, TEXT_FONT, TEXT_STYLE, TEXT_ANIM, STICKER, VOICEOVER, EXPORT,
}

enum class ImportTarget { MAIN, OVERLAY, AUDIO, REPLACE }

@UnstableApi
class EditorViewModel(app: Application, val projectId: String) : AndroidViewModel(app) {
    private val repo = ProjectRepository(app)
    val engine = PreviewEngine(app)
    val media = MediaCache(app)
    private val recorder = VoiceRecorder(app)

    var project by mutableStateOf(repo.load(projectId) ?: Project(projectId, "Untitled", System.currentTimeMillis(), System.currentTimeMillis()))
        private set
    private val undoStack = ArrayDeque<Project>()
    private val redoStack = ArrayDeque<Project>()
    var canUndo by mutableStateOf(false); private set
    var canRedo by mutableStateOf(false); private set
    private var selection by mutableStateOf<String?>(null)
    var selectedId: String?
        get() = selection
        set(value) { selection = project.selectableClipId(value) }
    /** A time inside the selected main-track gap, or null. */
    var selectedGapUs by mutableStateOf<Long?>(null)
    var playheadUs by mutableLongStateOf(0L); private set
    var playing by mutableStateOf(false); private set
    var panel by mutableStateOf(Panel.NONE)
    var transitionTargetId by mutableStateOf<String?>(null)
    var pxPerSecond by mutableFloatStateOf(app.resources.displayMetrics.density * 56f)
    /** A short notice for the user; every one is also written to the log (developer tools). */
    private var messageState by mutableStateOf<String?>(null)
    var message: String?
        get() = messageState
        set(value) {
            if (value != null) android.util.Log.w(LOG_TAG, "Shown: $value")
            messageState = value
        }
    var busy by mutableStateOf<String?>(null)
    var recording by mutableStateOf(false); private set
    var recordingStartUs by mutableLongStateOf(0L); private set
    var fullscreen by mutableStateOf(false)
    var renderStatus by mutableStateOf<String?>(null); private set
    private var renderJob: Job? = null
    private var gestureStart: Project? = null
    private var saveJob: Job? = null
    private var tickJob: Job? = null

    init {
        engine.onError = { message = "Preview: $it" }
        engine.onPlayingChanged = { p -> playing = p; if (p) startTicker() }
        engine.onEnded = { playing = false }
        engine.update(project, 0)
        scheduleSpeedRenders()
        logProject()
        // Filmstrips for every video, from the cache or made in the background, before the timeline needs them.
        project.assets.forEach { media.prepareFilmstrip(it) }
    }

    /** Writes the project's canvas and media (with their track formats) to the log, for the developer tools. */
    private fun logProject() {
        val p = project
        viewModelScope.launch(Dispatchers.IO) {
            val c = p.canvas
            val lines = p.assets.joinToString("") { a ->
                "\n  ${a.type} ${a.name}: ${a.width}x${a.height} ${a.durationUs / 1000} ms" +
                    (if (a.type == MediaType.IMAGE) "" else " · " + MediaProbe.describeTracks(getApplication(), Uri.parse(a.uri)))
            }
            android.util.Log.i(LOG_TAG, "Opened project ${c.aspect.label} ${c.tier.label} ${c.fps} fps, " +
                "${p.tracks.size} tracks, ${p.tracks.sumOf { it.clips.size }} clips:$lines")
        }
    }

    /** Speed-changed clips that still need their normal-speed render. */
    private fun pendingRenders(p: Project): List<Pair<Clip, MediaAsset>> =
        p.tracks.filter { it.kind == TrackKind.MAIN || it.kind == TrackKind.OVERLAY }.flatMap { it.clips }
            .mapNotNull { c -> p.asset(c.assetId)?.let { a -> (c to a).takeIf { SpeedRenders.needsRender(c, a) && SpeedRenders.ready(getApplication(), c, a) == null } } }

    /** Renders speed changes one at a time in the background; the preview switches to each render when it is ready. */
    private fun scheduleSpeedRenders() {
        if (renderJob?.isActive == true) return
        renderJob = viewModelScope.launch {
            while (isActive) {
                val todo = pendingRenders(project)
                if (todo.isEmpty()) break
                val (clip, asset) = todo.first()
                renderStatus = "Rendering speed change… (${todo.size} left)"
                try {
                    SpeedRenders.render(getApplication(), clip, asset)
                    engine.update(project, playheadUs)
                } catch (e: Exception) {
                    android.util.Log.w(LOG_TAG, "Speed render failed", e)
                    message = e.message ?: "Speed render failed"
                    break
                }
            }
            renderStatus = null
        }
    }

    val selectedClip: Clip? get() = selectedId?.let { project.clip(it) }
    val selectedTrack: Track? get() = selectedId?.let { project.trackOf(it) }
    val selectedCategory: ClipCategory? get() = selectedClip?.let { project.categoryOf(it) }
    val frameUs: Long get() = 1_000_000L / project.canvas.fps.coerceAtLeast(1)

    // -----------------------------------------------------------------------------------------------------------
    // History

    fun commit(p: Project) {
        if (p == project || !project.preservesLockedClips(p)) return
        undoStack.addLast(project)
        if (undoStack.size > 120) undoStack.removeFirst()
        redoStack.clear()
        apply(p)
    }

    private fun apply(p: Project) {
        project = p.copy(modifiedAt = System.currentTimeMillis())
        selectedId?.let { if (project.trackOf(it)?.locked != false) selectedId = null }
        transitionTargetId?.let {
            if (project.trackOf(it)?.locked != false) {
                transitionTargetId = null
                if (panel == Panel.TRANSITION) panel = Panel.NONE
            }
        }
        selectedGapUs?.let { if (project.mainTrack.locked || project.mainGapAt(it) == null) selectedGapUs = null }
        playheadUs = playheadUs.coerceIn(0, max(0L, project.durationUs))
        canUndo = undoStack.isNotEmpty(); canRedo = redoStack.isNotEmpty()
        engine.update(project, playheadUs)
        scheduleSave()
        scheduleSpeedRenders()
    }

    fun undo() {
        val prev = undoStack.removeLastOrNull() ?: return
        redoStack.addLast(project)
        apply(prev)
    }

    fun redo() {
        val next = redoStack.removeLastOrNull() ?: return
        undoStack.addLast(project)
        apply(next)
    }

    /** Live edits (dragging on the preview, sliders) update the view immediately and become one undo step. */
    fun beginGesture() { if (gestureStart == null) gestureStart = project }

    fun live(p: Project) {
        if (!project.preservesLockedClips(p)) return
        project = p
        // During a layer gesture the editor draws quick frames; the player is rebuilt once the gesture ends.
        engine.update(p, playheadUs, redraw = !layerGesture)
    }

    /** The timeline is being dragged: the preview shows quick frames instead of the player. */
    var scrubbing by mutableStateOf(false); private set
    /** A layer is being moved, resized or rotated on the preview: the preview shows quick frames instead of the player. */
    var layerGesture by mutableStateOf(false)
    /**
     * After a scrub or a layer gesture, the quick preview stays until the rebuilt player's frame is on screen: the
     * player's last frame (from before the gesture) would otherwise show the old position or size for a moment.
     */
    private var holdQuick by mutableStateOf(false)
    val quickPreview: Boolean get() = scrubbing || layerGesture || (holdQuick && engine.updating)

    private fun holdQuickPreview() { holdQuick = engine.updating }

    init {
        // The quick preview held after a gesture goes once the rebuilt frame is on screen.
        viewModelScope.launch {
            androidx.compose.runtime.snapshotFlow { engine.waitingForFrame.value }.collect { waiting ->
                if (!waiting && !engine.updating) holdQuick = false
            }
        }
    }

    fun endGesture() {
        val wasLayerGesture = layerGesture
        layerGesture = false
        val start = gestureStart ?: run { if (wasLayerGesture) { engine.update(project, playheadUs); holdQuickPreview() }; return }
        gestureStart = null
        if (start != project) {
            undoStack.addLast(start); redoStack.clear()
            canUndo = true; canRedo = false
            project = project.copy(modifiedAt = System.currentTimeMillis())
            engine.update(project, playheadUs)
            scheduleSave()
        }
        if (wasLayerGesture) holdQuickPreview()
    }

    private fun scheduleSave() {
        saveJob?.cancel()
        saveJob = viewModelScope.launch {
            delay(400)
            val snapshot = project
            withContext(Dispatchers.IO) { runCatching { repo.save(snapshot) } }
        }
    }

    // -----------------------------------------------------------------------------------------------------------
    // Playback

    private fun startTicker() {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            while (isActive && engine.isPlaying) {
                playheadUs = engine.positionUs.coerceIn(0, project.durationUs)
                if (recording && playheadUs >= project.durationUs - frameUs) { /* keep recording past the end */ }
                delay(16)
            }
            playheadUs = engine.positionUs.coerceIn(0, project.durationUs)
        }
    }

    fun togglePlay() {
        if (playing) engine.pause() else engine.play(playheadUs, project.durationUs)
    }

    fun scrubTo(us: Long, ended: Boolean) {
        if (playing) engine.pause()
        playheadUs = us.coerceIn(0, max(0L, project.durationUs))
        val wasScrubbing = scrubbing
        scrubbing = !ended
        engine.seekTo(playheadUs, scrubbing = !ended)
        if (ended && wasScrubbing) holdQuickPreview()
    }

    fun jumpTo(us: Long) = scrubTo(us, true)

    // -----------------------------------------------------------------------------------------------------------
    // Import

    private fun persist(uri: Uri) {
        try {
            getApplication<Application>().contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
    }

    fun import(uris: List<Uri>, target: ImportTarget) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            busy = "Importing…"
            val assets = withContext(Dispatchers.IO) {
                uris.mapNotNull { persist(it); MediaProbe.probe(getApplication(), it) }
            }
            busy = null
            if (assets.isEmpty()) { message = "Couldn't read the selected media"; return@launch }
            val before = allClipIds()
            when (target) {
                ImportTarget.MAIN -> commit(project.addToMainAt(assets.filter { it.type != MediaType.AUDIO }, playheadUs))
                ImportTarget.OVERLAY -> {
                    var p = project
                    assets.filter { it.type != MediaType.AUDIO }.forEach { p = p.addOverlayAt(it, playheadUs) }
                    commit(p)
                }
                ImportTarget.AUDIO -> {
                    var p = project
                    var at = playheadUs
                    assets.filter { it.hasAudio }.forEach { a -> p = p.addAudioAt(a, at); at += a.durationUs }
                    commit(p)
                }
                ImportTarget.REPLACE -> replaceSelected(assets.first())
            }
            (allClipIds() - before).firstOrNull()?.let { selectedId = it }
        }
    }

    private fun replaceSelected(asset: MediaAsset) {
        val clip = selectedClip ?: return
        if (asset.type == MediaType.AUDIO) return
        val dur = clip.srcOutUs - clip.srcInUs
        val newOut = if (asset.type == MediaType.IMAGE) dur else minOf(asset.durationUs, dur)
        commit(project.withAssets(listOf(asset)).updateClip(clip.id) { it.copy(assetId = asset.id, srcInUs = 0, srcOutUs = newOut, crop = CropRect()) })
    }

    private fun allClipIds(): Set<String> = project.tracks.flatMap { t -> t.clips.map { it.id } }.toSet()

    fun importSubtitles(uri: Uri) {
        viewModelScope.launch {
            val app = getApplication<Application>()
            val name = MediaProbe.displayName(app, uri)
            val text = withContext(Dispatchers.IO) { runCatching { app.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } }.getOrNull() }
            val cues = text?.let { Subtitles.parse(it, name) }.orEmpty()
            if (cues.isEmpty()) { message = "No subtitles found in $name"; return@launch }
            commit(project.addTextCues(cues, TextStyle(text = "", size = 0.055f, role = TextRole.SUBTITLE, shadow = true, strokeWidth = 0.08f, bold = true)))
            message = "Added ${cues.size} lines"
        }
    }

    fun subtitlesSrt(trackId: String): String {
        val track = project.track(trackId) ?: return ""
        return Subtitles.toSrt(track.clips.mapNotNull { c -> c.text?.let { Cue(c.startUs, c.endUs, it.text) } })
    }

    // -----------------------------------------------------------------------------------------------------------
    // Adding text and stickers

    fun addText(role: TextRole = TextRole.TITLE) {
        val style = when (role) {
            TextRole.TITLE -> TextStyle(text = "Your title", size = 0.09f, role = role)
            TextRole.SUBTITLE -> TextStyle(text = "Subtitle", size = 0.055f, role = role, strokeWidth = 0.08f)
            TextRole.STICKER -> TextStyle(text = "⭐", size = 0.18f, shadow = false, bold = false, role = role)
        }
        val before = allClipIds()
        commit(project.addTextAt(style, playheadUs))
        selectedId = (allClipIds() - before).firstOrNull()
        panel = if (role == TextRole.STICKER) Panel.NONE else Panel.TEXT_EDIT
    }

    fun addSticker(emoji: String) {
        val before = allClipIds()
        commit(project.addTextAt(TextStyle(text = emoji, size = 0.2f, shadow = false, bold = false, role = TextRole.STICKER), playheadUs))
        selectedId = (allClipIds() - before).firstOrNull()
    }

    // -----------------------------------------------------------------------------------------------------------
    // Clip edits

    fun updateSelected(f: (Clip) -> Clip) {
        val id = selectedId ?: return
        commit(project.updateClip(id, f))
    }

    fun liveSelected(f: (Clip) -> Clip) {
        val id = selectedId ?: return
        beginGesture()
        live(project.updateClip(id, f))
    }

    /** Selects text clip [id] and opens its editor (double tap on the preview or timeline). */
    fun openTextEditor(id: String) {
        if (project.clip(id)?.isText != true) return
        selectedId = id
        panel = Panel.TEXT_EDIT
    }

    fun updateText(f: (TextStyle) -> TextStyle) = updateSelected { c -> c.text?.let { c.copy(text = f(it)) } ?: c }

    fun liveText(f: (TextStyle) -> TextStyle) = liveSelected { c -> c.text?.let { c.copy(text = f(it)) } ?: c }

    /** Splits the selected clip, or the main clip under the playhead, at the playhead. */
    fun split() {
        val id = selectedId?.takeIf { project.clip(it)?.contains(playheadUs) == true }
            ?: project.mainTrack.clips.firstOrNull { it.contains(playheadUs) }?.id ?: run { message = "Move the playhead over a clip to split it"; return }
        val (p, second) = project.splitClip(id, playheadUs)
        if (second == null) { message = "Too close to the clip's edge"; return }
        commit(p)
        selectedId = second
    }

    /** Closes the selected gap on the main track: the clips after it move left. */
    fun deleteGap() {
        val t = selectedGapUs ?: return
        commit(project.deleteMainGap(t))
        selectedGapUs = null
    }

    fun deleteSelected() {
        val id = selectedId ?: return
        commit(project.deleteClip(id))
        selectedId = null
        panel = Panel.NONE
    }

    fun duplicateSelected() {
        val id = selectedId ?: return
        val (p, copy) = project.duplicateClip(id)
        commit(p)
        selectedId = copy
    }

    fun setSpeed(speed: Float) { selectedId?.let { commit(project.setSpeed(it, speed)) } }

    fun trim(clipId: String, start: Boolean, deltaUs: Long) {
        commit(if (start) project.trimStart(clipId, deltaUs) else project.trimEnd(clipId, deltaUs))
    }

    fun move(clipId: String, trackId: String, startUs: Long, newTrack: Boolean) {
        commit(project.moveClip(clipId, trackId, startUs, newTrack))
        selectedId = clipId
    }

    fun setTransition(clipId: String, transition: Transition?) = commit(project.setTransition(clipId, transition))

    fun setTransitionForAll(transition: Transition?) {
        var p = project
        project.mainTrack.clips.drop(1).forEach { p = p.setTransition(it.id, transition) }
        commit(p)
    }

    fun toggleKeyframe() {
        val id = selectedId ?: return
        commit(project.toggleKeyframe(id, playheadUs, frameUs))
    }

    fun extractAudio() {
        val id = selectedId ?: return
        val (p, audio) = project.extractAudio(id)
        if (audio == null) { message = "This clip has no audio"; return }
        commit(p)
        selectedId = audio
    }

    fun toOverlay() { selectedId?.let { commit(project.moveToOverlay(it)) } }
    fun toMain() { selectedId?.let { commit(project.moveToMain(it)) } }

    fun freezeFrame() {
        val clip = selectedClip?.takeIf { it.contains(playheadUs) }
            ?: project.mainTrack.clips.firstOrNull { it.contains(playheadUs) } ?: run { message = "Move the playhead over a video"; return }
        val asset = project.asset(clip.assetId) ?: return
        if (asset.type != MediaType.VIDEO) { message = "Freeze frame needs a video clip"; return }
        viewModelScope.launch {
            busy = "Capturing frame…"
            val still = repo.captureStill(projectId, asset, clip.sourceTimeAt(playheadUs))
            busy = null
            if (still == null) { message = "Couldn't capture the frame"; return@launch }
            commit(project.insertFreezeFrame(clip.id, playheadUs, still))
        }
    }

    fun applyLayout(preset: LayoutPreset, gap: Float) = commit(project.applyLayout(preset, playheadUs, gap))

    fun updateCanvas(f: (CanvasSettings) -> CanvasSettings) = commit(project.copy(canvas = f(project.canvas)))

    fun rename(name: String) = commit(project.copy(name = name.ifBlank { project.name }))

    fun applyFilterToAll(filter: FilterSetting?) {
        var p = project
        project.tracks.filter { it.kind == TrackKind.MAIN || it.kind == TrackKind.OVERLAY }.flatMap { it.clips }.forEach { c ->
            p = p.updateClip(c.id) { it.copy(filter = filter) }
        }
        commit(p)
    }

    fun applyAdjustToAll(adjust: Adjust) {
        var p = project
        project.tracks.filter { it.kind == TrackKind.MAIN || it.kind == TrackKind.OVERLAY }.flatMap { it.clips }.forEach { c ->
            p = p.updateClip(c.id) { it.copy(adjust = adjust) }
        }
        commit(p)
    }

    fun toggleTrackLock(trackId: String) = commit(project.updateTrack(trackId) { it.copy(locked = !it.locked) })
    fun toggleTrackMute(trackId: String) = commit(project.updateTrack(trackId) { it.copy(muted = !it.muted) })
    fun toggleTrackHidden(trackId: String) = commit(project.updateTrack(trackId) { it.copy(hidden = !it.hidden) })

    fun saveAudio() {
        val asset = project.asset(selectedClip?.assetId) ?: return
        ExportManager.exportAudio(getApplication(), asset)
    }

    fun export(settings: ExportSettings) {
        if (playing) engine.pause()
        viewModelScope.launch {
            withContext(Dispatchers.IO) { runCatching { repo.save(project) } }
            // Every speed change must be rendered before the export can use it.
            renderJob?.cancel()
            val todo = pendingRenders(project)
            try {
                todo.forEachIndexed { i, (clip, asset) ->
                    busy = "Preparing speed changes ${i + 1}/${todo.size}…"
                    SpeedRenders.render(getApplication(), clip, asset)
                }
            } catch (e: Exception) {
                android.util.Log.w(LOG_TAG, "Speed render failed", e)
                busy = null
                message = e.message ?: "Speed render failed"
                return@launch
            }
            busy = null
            ExportManager.exportVideo(getApplication(), project, settings)
        }
    }

    // -----------------------------------------------------------------------------------------------------------
    // Voiceover

    fun startRecording() {
        if (recording) return
        try {
            engine.audioMuted = true
            recorder.start(repo.voiceFile(projectId))
            recordingStartUs = playheadUs
            recording = true
            if (project.durationUs > 0 && playheadUs < project.durationUs - frameUs) engine.play(playheadUs, project.durationUs)
        } catch (e: Exception) {
            recording = false
            engine.pause()
            try { recorder.stop() } finally { engine.audioMuted = false }
            android.util.Log.w(LOG_TAG, "Recording failed", e)
            message = "Couldn't start recording: ${e.message}"
        }
    }

    fun stopRecording() {
        if (!recording) return
        recording = false
        engine.pause()
        val file = try { recorder.stop() } finally { engine.audioMuted = false }
            ?: run { message = "Recording failed"; return }
        viewModelScope.launch {
            val asset = withContext(Dispatchers.IO) { MediaProbe.probe(getApplication(), Uri.fromFile(file), "audio/mp4") }
            if (asset == null) { message = "Recording was too short"; return@launch }
            val before = allClipIds()
            commit(project.addAudioAt(asset.copy(name = "Voiceover"), recordingStartUs, audioOnly = false))
            selectedId = (allClipIds() - before).firstOrNull()
        }
    }

    val recorderLevel: Int get() = recorder.maxAmplitude

    override fun onCleared() {
        if (recording) recorder.stop()
        val snapshot = project
        runBlocking(Dispatchers.IO + NonCancellable) {
            runCatching { repo.save(snapshot) }
            runCatching { repo.writeCover(snapshot) }
        }
        engine.release()
        media.release()
        super.onCleared()
    }

    class Factory(private val app: Application, private val id: String) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = EditorViewModel(app, id) as T
    }
}
