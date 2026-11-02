package com.framenova.app.engine

import android.content.Context
import android.view.TextureView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.CompositionPlayer
import androidx.compose.ui.graphics.asImageBitmap
import com.framenova.app.LOG_TAG
import com.framenova.app.model.Project
import kotlin.math.abs

/**
 * Live preview of a project. Rebuilds the Media3 pipeline only when the structure changes; transforms, opacity,
 * keyframes and text are swapped in place and the current frame is redrawn.
 */
@UnstableApi
class PreviewEngine(private val context: Context) {
    /** Silences preview output without changing clip or track audio settings. */
    var audioMuted: Boolean = false
        set(value) {
            field = value
            player.volume = if (value) 0f else 1f
        }

    /**
     * The current player. Media3 1.9 keeps a player's video graph across setComposition calls; a new composition on a
     * used player can fail to start (or crash when the number of layers changes), so every rebuild gets a new player.
     */
    var player: CompositionPlayer = newPlayer()
        private set
    /** Whether the current player has been given a composition. */
    private var playerUsed = false
    private var holder: PlanHolder? = null
    private var lastProject: Project? = null
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    @Volatile private var lastRenderedUs = 0L
    @Volatile private var lastRenderWallMs = 0L
    @Volatile private var renderedSinceBuild = false
    private var lastRecoveryMs = 0L
    /** Extra listener for rendered frames (tests). */
    var frameListener: ((Long) -> Unit)? = null
    private var textureView: TextureView? = null
    var onError: ((String) -> Unit)? = null
    var onPlayingChanged: ((Boolean) -> Unit)? = null
    var onEnded: (() -> Unit)? = null
    private val errorTimes = ArrayList<Long>()

    private fun newPlayer(): CompositionPlayer {
        val p = CompositionPlayer.Builder(context)
            // Layers are composited, so the preview needs the multi-input video graph (the default handles one input only).
            .setVideoGraphFactory(androidx.media3.effect.PreviewMultipleInputVideoGraph.Factory())
            .build()
        p.volume = if (audioMuted) 0f else 1f
        p.setVideoFrameMetadataListener { presentationTimeUs, _, _, _ ->
            lastRenderedUs = presentationTimeUs
            renderedSinceBuild = true
            if (p === player) renderedBuild = activeBuild
            lastRenderWallMs = android.os.SystemClock.uptimeMillis()
            frameListener?.invoke(presentationTimeUs)
        }
        p.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (p !== player) return
                // A failed pipeline (for example the GPU briefly out of memory) is prepared again where it was, twice at
                // most within a few seconds; only then is the error shown.
                val now = android.os.SystemClock.uptimeMillis()
                errorTimes.removeAll { now - it > 5000 }
                if (errorTimes.size < 2) {
                    errorTimes += now
                    val at = p.currentPosition * 1000
                    val resume = p.playWhenReady
                    android.util.Log.w(LOG_TAG, "Preview error at ${at / 1000} ms, preparing again", error)
                    main.postDelayed({ if (p === player) { rebuildAt(at); if (resume) player.play() } }, 300)
                } else {
                    android.util.Log.e(LOG_TAG, "Preview error, not recovered", error)
                    onError?.invoke(error.cause?.message ?: error.message ?: "Playback error")
                }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (p !== player) return
                if (isPlaying) preparedAtUs = -1
                onPlayingChanged?.invoke(isPlaying)
                if (isPlaying) { lastRenderWallMs = android.os.SystemClock.uptimeMillis(); main.removeCallbacks(watchdog); main.postDelayed(watchdog, 500) }
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (p === player && playbackState == Player.STATE_ENDED) onEnded?.invoke()
            }
        })
        return p
    }

    /**
     * Releases [p] completely. In Media3 1.9 CompositionTrackSelector does not pass release() on to its
     * DefaultTrackSelector, whose audio spatializer listener then keeps the whole released player (GL objects,
     * buffers) reachable; with a new player for every seek this leaked memory quickly. After the player is released,
     * that listener is removed (reached by reflection; kept in proguard-rules.pro). Releasing the selector itself
     * earlier made the player, still preparing, fail on it.
     */
    private fun releasePlayer(p: CompositionPlayer) {
        val selectors = runCatching {
            val holders = CompositionPlayer::class.java.getDeclaredField("playerHolders").apply { isAccessible = true }.get(p) as List<*>
            holders.mapNotNull { holder ->
                val selector = holder?.javaClass?.getDeclaredField("trackSelector")?.apply { isAccessible = true }?.get(holder)
                selector?.javaClass?.getDeclaredField("trackSelectorInternal")?.apply { isAccessible = true }?.get(selector)
            }
        }.onFailure { android.util.Log.w(LOG_TAG, "Could not reach the track selectors", it) }.getOrDefault(emptyList())
        p.release()
        for (selector in selectors) {
            try {
                val field = androidx.media3.exoplayer.trackselection.DefaultTrackSelector::class.java.getDeclaredField("spatializer").apply { isAccessible = true }
                val wrapper = field.get(selector) ?: continue
                wrapper.javaClass.getDeclaredMethod("release").apply { isAccessible = true }.invoke(wrapper)
                field.set(selector, null)
            } catch (e: Exception) {
                android.util.Log.w(LOG_TAG, "Could not release a track selector's spatializer listener", e)
            }
        }
    }

    /** Swaps in a new player, keeping the surface. */
    private fun replacePlayer() {
        val old = player
        captureCover()
        clearOutput()
        player = newPlayer()
        playerUsed = false
        releasePlayer(old)
        outputSurface()?.let { (target, size) -> setOutput(target, size) }
        onPlayingChanged?.invoke(false)
    }

    val isPlaying: Boolean get() = player.isPlaying
    val positionUs: Long get() = player.currentPosition * 1000

    /*
     * The preview draws into a TextureView, which keeps showing its last frame (scaled) when it is resized, where a
     * SurfaceView went black until the next frame (a panel or the keyboard opening). The output surface and its size are
     * managed here rather than with setVideoSurfaceView, so every new player gets the current size; a player that read
     * a stale size drew the picture shrunk into a corner.
     */
    private var viewSurface: Pair<android.view.Surface, androidx.media3.common.util.Size>? = null
    private var viewTexture: android.graphics.SurfaceTexture? = null
    private val textureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(texture: android.graphics.SurfaceTexture, width: Int, height: Int) {
            useTexture(texture, width, height)
        }
        override fun onSurfaceTextureSizeChanged(texture: android.graphics.SurfaceTexture, width: Int, height: Int) {
            useTexture(texture, width, height)
        }
        override fun onSurfaceTextureDestroyed(texture: android.graphics.SurfaceTexture): Boolean {
            clearOutput()
            viewSurface?.first?.release()
            viewSurface = null
            viewTexture = null
            return true
        }
        override fun onSurfaceTextureUpdated(texture: android.graphics.SurfaceTexture) {
            // The new player's first frame is on screen: drop the snapshot that covered the rebuild.
            if (cover.value != null && renderedBuild >= coverClearFrom) clearCover.run()
            if (waitingForFrame.value && renderedBuild >= activeBuild) waitingForFrame.value = false
            // Keep a snapshot of what is shown while paused, to cover the next resize or rebuild.
            if (!player.isPlaying && renderedSinceBuild) { main.removeCallbacks(snapshot); main.post(snapshot) }
        }
    }

    /** The last frame shown while paused (half size), used as [cover]. */
    private var lastFrame: androidx.compose.ui.graphics.ImageBitmap? = null
    private val snapshot = Runnable {
        val view = textureView ?: return@Runnable
        if (!view.isAvailable || view.width <= 0 || view.height <= 0) return@Runnable
        runCatching { view.getBitmap(view.width / 2, view.height / 2) }.getOrNull()?.let { lastFrame = it.asImageBitmapCompat() }
    }

    private fun useTexture(texture: android.graphics.SurfaceTexture, width: Int, height: Int) {
        val size = androidx.media3.common.util.Size(width, height)
        val surface = viewSurface?.first?.takeIf { viewTexture === texture } ?: android.view.Surface(texture)
        val changed = viewTexture !== texture || viewSurface?.second != size
        viewTexture = texture
        viewSurface = surface to size
        if (changed && holder != null && !player.isPlaying && playerUsed) {
            // A new or resized texture is blank until something draws into it, and nothing draws while paused: show the
            // last frame over it at once and prepare the frame again at the new size (the rebuild gets the new size).
            showCover(lastFrame, clearFrom = builds + 1)
            redraw()
            return
        }
        setOutput(surface, size)
    }

    /**
     * A snapshot of the last frame, shown over the preview while a rebuilt player prepares its first frame, so a seek,
     * an edit or a layout change does not flash black. Cleared when the new frame is on screen (or after 3 s).
     */
    val cover = androidx.compose.runtime.mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null)
    /** True from a rebuild until its first frame is on screen. */
    val waitingForFrame = androidx.compose.runtime.mutableStateOf(false)
    /** Whether a new frame is on its way (a rebuild running or about to run). */
    val updating: Boolean get() = waitingForFrame.value || pendingSeekUs != null
    /** Rebuild count, the rebuild the current player shows, the rebuild whose frame was last drawn, and the first
     *  rebuild whose frame may remove the cover. */
    private var builds = 0
    @Volatile private var activeBuild = 0
    @Volatile private var renderedBuild = -1
    private var coverClearFrom = 0
    private val clearCover = Runnable { cover.value = null }
    private val stopWaiting = Runnable { waitingForFrame.value = false }

    private fun captureCover() {
        // Keep an earlier snapshot while the frame it covers has not been replaced yet.
        if (cover.value != null && !renderedSinceBuild) { showCover(cover.value); return }
        val view = textureView ?: return
        val current = if (view.isAvailable && view.width > 0 && view.height > 0)
            runCatching { view.getBitmap(view.width / 2, view.height / 2) }.getOrNull()?.asImageBitmapCompat() else null
        showCover(if (player.isPlaying) current ?: lastFrame else lastFrame ?: current)
    }

    /** Shows [frame] until a frame of rebuild [clearFrom] or later is on screen. */
    private fun showCover(frame: androidx.compose.ui.graphics.ImageBitmap?, clearFrom: Int = builds) {
        if (frame == null) return
        coverClearFrom = if (cover.value == null) clearFrom else maxOf(coverClearFrom, clearFrom)
        cover.value = frame
        main.removeCallbacks(clearCover)
        main.postDelayed(clearCover, 3000)
    }

    private fun android.graphics.Bitmap.asImageBitmapCompat() = asImageBitmap()

    /** The surface the current player draws into; the player only accepts clearing that exact surface. */
    private var playerOutput: android.view.Surface? = null

    private fun setOutput(target: android.view.Surface, size: androidx.media3.common.util.Size) {
        player.setVideoSurface(target, size)
        playerOutput = target
    }

    private fun clearOutput() {
        playerOutput?.let { runCatching { player.clearVideoSurface(it) } }
        playerOutput = null
    }

    private fun outputSurface(): Pair<android.view.Surface, androidx.media3.common.util.Size>? = viewSurface ?: rawSurface

    fun attach(view: TextureView) {
        if (textureView === view) return
        textureView?.surfaceTextureListener = null
        textureView = view
        view.surfaceTextureListener = textureListener
        val texture = view.surfaceTexture
        if (view.isAvailable && texture != null) useTexture(texture, view.width, view.height)
    }

    /** Renders into [target] (tests, off-screen use). Kept when the player is replaced. */
    fun attach(target: android.view.Surface, size: androidx.media3.common.util.Size) {
        rawSurface = target to size
        setOutput(target, size)
    }
    private var rawSurface: Pair<android.view.Surface, androidx.media3.common.util.Size>? = null

    fun detach(view: TextureView) {
        if (textureView !== view) return
        view.surfaceTextureListener = null
        textureView = null
    }

    /**
     * Safety net: if the picture stops while playback runs (or the first frame never comes), the composition is prepared
     * again at the current position. The known causes are fixed (PreviewVideoCompositor, the filler video in
     * CompositionFactory), so this should not normally trigger.
     */
    private val watchdog: Runnable = object : Runnable {
        override fun run() {
            if (!player.isPlaying) return
            val now = android.os.SystemClock.uptimeMillis()
            val position = player.currentPosition * 1000
            val stalled = if (renderedSinceBuild) now - lastRenderWallMs > 1200 && position - lastRenderedUs > 1_200_000
            else now - lastRenderWallMs > 2500 // no first frame at all
            if (stalled && now - lastRecoveryMs > 3000) {
                lastRecoveryMs = now
                android.util.Log.w(LOG_TAG, "Video stalled at ${lastRenderedUs / 1000} ms (clock ${position / 1000} ms): preparing again")
                lastProject?.let { update(it, position, force = true); player.play() }
            }
            main.postDelayed(this, 300)
        }
    }

    /** One line per sequence: its track types and items (file name or gap, and length), for the log. */
    private fun describe(composition: androidx.media3.transformer.Composition): String =
        composition.sequences.mapIndexed { i, seq ->
            val types = seq.trackTypes.joinToString("+") { androidx.media3.common.util.Util.getTrackTypeString(it) }
            val items = seq.editedMediaItems.joinToString(", ") { item ->
                val name = item.mediaItem.localConfiguration?.uri?.lastPathSegment ?: "gap"
                val clip = item.mediaItem.clippingConfiguration
                val end = if (clip.endPositionUs == androidx.media3.common.C.TIME_END_OF_SOURCE) item.durationUs else clip.endPositionUs
                "$name ${(end - clip.startPositionUs) / 1000}ms"
            }
            "\n  #$i [$types] $items"
        }.joinToString("")

    /** Applies [project]; [positionUs] is where playback resumes after a rebuild. */
    fun update(project: Project, positionUs: Long, force: Boolean = false, redraw: Boolean = true) {
        lastProject = project
        if (project.durationUs <= 0) { holder = null; player.stop(); player.clearMediaItems(); return }
        val out = CompositionFactory.outputSize(project.canvas, PlanMode.PREVIEW)
        val key = CompositionFactory.structureKey(CompositionFactory.resolve(context, project), PlanMode.PREVIEW, out, project.canvas.fps)
        val current = holder
        if (!force && current != null && current.plan.key == key) {
            current.hot = HotState(project)
            if (!player.isPlaying && redraw) redraw()
            return
        }
        val wasPlaying = player.playWhenReady
        renderedSinceBuild = false
        builds++
        lastRenderWallMs = android.os.SystemClock.uptimeMillis()
        val (composition, newHolder) = CompositionFactory.build(context, project, PlanMode.PREVIEW)
        if (holder?.plan?.key != key) android.util.Log.i(LOG_TAG, "Preview layout at ${positionUs / 1000} ms: ${describe(composition)}")
        if (playerUsed) replacePlayer()
        playerUsed = true
        holder = newHolder
        val startMs = (positionUs / 1000).coerceIn(0, project.durationUs / 1000)
        preparedAtUs = startMs * 1000
        activeBuild = builds
        waitingForFrame.value = true
        main.removeCallbacks(stopWaiting)
        main.postDelayed(stopWaiting, 3000)
        player.setComposition(composition, startMs)
        if (player.playbackState == Player.STATE_IDLE) player.prepare()
        player.playWhenReady = wasPlaying
    }

    /**
     * Shows a changed frame while paused. Media3 1.9's multi-input video graph cannot redraw (experimentalRedrawLastFrame
     * throws on the playback thread) or seek reliably, so the composition is prepared again at the current position,
     * throttled like a drag.
     */
    private fun redraw() {
        val at = if (preparedAtUs >= 0) preparedAtUs else player.currentPosition * 1000
        throttledRebuild(at)
    }


    /** Plays from [fromUs] (from the start when at the end), preparing a new player if this one is not there. */
    fun play(fromUs: Long, durationUs: Long) {
        if (holder == null) return
        main.removeCallbacks(seekRunnable)
        pendingSeekUs = null
        val target = if (fromUs >= durationUs - 50_000) 0L else fromUs
        val state = player.playbackState
        if (state == Player.STATE_ENDED || state == Player.STATE_IDLE || abs(player.currentPosition * 1000 - target) > 50_000) {
            rebuildAt(target)
        }
        player.play()
    }

    fun pause() = player.pause()

    /*
     * Seeking. Media3 1.9's multi-input video graph does not clear its compositor on a seek: frames from before the seek
     * stay queued (the player then waits forever, or the compositor throws once a layer has ended). A newly prepared
     * player shows the right frame, so a seek prepares one at the target. While the user drags the timeline nothing is
     * rebuilt (the editor shows quick frames instead, see PreviewPane); the final position is prepared once.
     */
    private var pendingSeekUs: Long? = null
    private var lastSeekBuildMs = 0L
    /** Where the current player was prepared, while it has not played since; -1 otherwise. */
    private var preparedAtUs = -1L
    private val seekRunnable = Runnable { pendingSeekUs?.let { pendingSeekUs = null; rebuildAt(it) } }

    private fun rebuildAt(us: Long) {
        val project = lastProject ?: return
        lastSeekBuildMs = android.os.SystemClock.uptimeMillis()
        update(project, us, force = true)
    }

    private fun isPreparedAt(us: Long): Boolean =
        preparedAtUs >= 0 && abs(preparedAtUs - us) < 20_000 && player.playerError == null && player.playbackState != Player.STATE_ENDED

    fun seekTo(us: Long, scrubbing: Boolean) {
        if (holder == null) return
        main.removeCallbacks(seekRunnable)
        pendingSeekUs = null
        if (!scrubbing && !isPreparedAt(us)) rebuildAt(us)
    }

    /** Prepares the composition again at [us], at most every SEEK_INTERVAL_MS (the last request always runs). */
    private fun throttledRebuild(us: Long) {
        main.removeCallbacks(seekRunnable)
        pendingSeekUs = us
        val wait = SEEK_INTERVAL_MS - (android.os.SystemClock.uptimeMillis() - lastSeekBuildMs)
        if (wait <= 0) seekRunnable.run() else main.postDelayed(seekRunnable, wait)
    }

    companion object {
        private const val SEEK_INTERVAL_MS = 250L
    }

    fun release() {
        main.removeCallbacks(watchdog)
        main.removeCallbacks(seekRunnable)
        releasePlayer(player)
        holder = null
    }
}
