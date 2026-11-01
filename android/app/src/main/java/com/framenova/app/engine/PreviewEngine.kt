package com.framenova.app.engine

import android.content.Context
import android.view.SurfaceView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MultipleInputVideoGraph
import androidx.media3.transformer.CompositionPlayer
import com.framenova.app.model.Project
import kotlin.math.abs

/**
 * Live preview of a project. Rebuilds the Media3 pipeline only when the structure changes; transforms, opacity,
 * keyframes and text are swapped in place and the current frame is redrawn.
 */
@UnstableApi
class PreviewEngine(private val context: Context, private val replayableCache: Boolean = PreviewEngine.replayableCache) {
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
    private var surface: SurfaceView? = null
    var onError: ((String) -> Unit)? = null
    var onPlayingChanged: ((Boolean) -> Unit)? = null
    var onEnded: (() -> Unit)? = null

    private fun newPlayer(): CompositionPlayer {
        val p = CompositionPlayer.Builder(context)
            // Layers are composited, so the preview needs the multi-input video graph (the default handles one input only).
            .setVideoGraphFactory(MultipleInputVideoGraph.Factory())
            .experimentalSetEnableReplayableCache(replayableCache)
            .build()
        p.setVideoFrameMetadataListener { presentationTimeUs, _, _, _ ->
            lastRenderedUs = presentationTimeUs
            renderedSinceBuild = true
            lastRenderWallMs = android.os.SystemClock.uptimeMillis()
            frameListener?.invoke(presentationTimeUs)
        }
        p.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (p === player) onError?.invoke(error.cause?.message ?: error.message ?: "Playback error")
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

    /** Swaps in a new player, keeping the surface. */
    private fun replacePlayer() {
        val old = player
        surface?.let { old.clearVideoSurfaceView(it) }
        player = newPlayer()
        playerUsed = false
        old.release()
        surface?.let { player.setVideoSurfaceView(it) }
        rawSurface?.let { (target, size) -> player.setVideoSurface(target, size) }
        onPlayingChanged?.invoke(false)
    }

    val isPlaying: Boolean get() = player.isPlaying
    val positionUs: Long get() = player.currentPosition * 1000

    fun attach(view: SurfaceView) {
        if (surface === view) return
        surface = view
        player.setVideoSurfaceView(view)
    }

    /** Renders into [target] (tests, off-screen use). Kept when the player is replaced. */
    fun attach(target: android.view.Surface, size: androidx.media3.common.util.Size) {
        rawSurface = target to size
        player.setVideoSurface(target, size)
    }
    private var rawSurface: Pair<android.view.Surface, androidx.media3.common.util.Size>? = null

    fun detach(view: SurfaceView) {
        if (surface !== view) return
        player.clearVideoSurfaceView(view)
        surface = null
    }

    /**
     * Media3 1.9's preview player can stop producing video when a layer switches to its next clip while another layer is
     * mid-clip (see EngineDeviceTest.previewRendersPastGaps); export is unaffected. When video falls behind the playback
     * clock, the composition is prepared again at the current position, where that layer starts directly.
     */
    private val watchdog: Runnable = object : Runnable {
        override fun run() {
            if (!player.isPlaying) return
            val now = android.os.SystemClock.uptimeMillis()
            val position = player.currentPosition * 1000
            // Only after this pipeline has shown a frame: a slow first frame is not a stall.
            val stalled = renderedSinceBuild && now - lastRenderWallMs > 1200 && position - lastRenderedUs > 1_200_000
            if (stalled && now - lastRecoveryMs > 3000) {
                lastRecoveryMs = now
                android.util.Log.w("PreviewEngine", "Video stalled at ${lastRenderedUs / 1000} ms (clock ${position / 1000} ms): preparing again")
                lastProject?.let { update(it, position, force = true); player.play() }
            }
            main.postDelayed(this, 300)
        }
    }

    /** Applies [project]; [positionUs] is where playback resumes after a rebuild. */
    fun update(project: Project, positionUs: Long, force: Boolean = false) {
        lastProject = project
        if (project.durationUs <= 0) { holder = null; player.stop(); player.clearMediaItems(); return }
        val out = CompositionFactory.outputSize(project.canvas, PlanMode.PREVIEW)
        val key = CompositionFactory.structureKey(CompositionFactory.resolve(context, project), PlanMode.PREVIEW, out, project.canvas.fps)
        val current = holder
        if (!force && current != null && current.plan.key == key) {
            current.hot = HotState(project)
            if (!player.isPlaying) redraw()
            return
        }
        val wasPlaying = player.playWhenReady
        renderedSinceBuild = false
        lastRenderWallMs = android.os.SystemClock.uptimeMillis()
        val (composition, newHolder) = CompositionFactory.build(context, project, PlanMode.PREVIEW)
        if (playerUsed) replacePlayer()
        playerUsed = true
        holder = newHolder
        val startMs = (positionUs / 1000).coerceIn(0, project.durationUs / 1000)
        preparedAtUs = startMs * 1000
        player.setComposition(composition, startMs)
        if (player.playbackState == Player.STATE_IDLE) player.prepare()
        player.playWhenReady = wasPlaying
    }

    private fun redraw() {
        try { player.experimentalRedrawLastFrame() } catch (_: IllegalStateException) { rebuildAt(player.currentPosition * 1000) }
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
     * player shows the right frame, so every seek prepares one at the target, at most every SEEK_INTERVAL_MS while the
     * user drags and once more at the final position.
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
        if (!scrubbing) {
            pendingSeekUs = null
            if (!isPreparedAt(us)) rebuildAt(us)
            return
        }
        pendingSeekUs = us
        val wait = SEEK_INTERVAL_MS - (android.os.SystemClock.uptimeMillis() - lastSeekBuildMs)
        if (wait <= 0) seekRunnable.run() else main.postDelayed(seekRunnable, wait)
    }

    companion object {
        @Volatile var replayableCache = true
        private const val SEEK_INTERVAL_MS = 250L
    }

    fun release() {
        main.removeCallbacks(watchdog)
        main.removeCallbacks(seekRunnable)
        player.release()
        holder = null
    }
}
