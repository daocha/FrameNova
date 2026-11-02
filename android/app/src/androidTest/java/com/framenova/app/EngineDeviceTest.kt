package com.framenova.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.framenova.app.data.ProjectRepository
import com.framenova.app.engine.CompositionFactory
import com.framenova.app.engine.FontManager
import com.framenova.app.engine.MediaProbe
import com.framenova.app.engine.PlanMode
import com.framenova.app.engine.PreviewEngine
import com.framenova.app.model.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs

@UnstableApi
@RunWith(AndroidJUnit4::class)
class EngineDeviceTest {
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())

    @Before fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        FontManager.init(context)
    }

    private fun fixture(name: String): Uri {
        val out = File(context.cacheDir, "fixtures/$name").apply { parentFile?.mkdirs() }
        InstrumentationRegistry.getInstrumentation().context.assets.open(name).use { input -> out.outputStream().use { input.copyTo(it) } }
        return Uri.fromFile(out)
    }

    private fun solidPng(name: String, color: Int, w: Int, h: Int): Uri {
        val f = File(context.cacheDir, "fixtures/$name").apply { parentFile?.mkdirs() }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
        f.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return Uri.fromFile(f)
    }

    /** Renders speed changes first, exactly as the editor does before exporting. */
    private fun prepareSpeed(project: Project) = kotlinx.coroutines.runBlocking {
        project.tracks.flatMap { it.clips }.forEach { c ->
            val a = project.asset(c.assetId)
            if (com.framenova.app.engine.SpeedRenders.needsRender(c, a)) com.framenova.app.engine.SpeedRenders.render(context, c, a!!)
        }
    }

    private fun export(project: Project, longSide: Int, fps: Int = 30): Pair<File, ExportResult> {
        prepareSpeed(project)
        val (composition, _) = CompositionFactory.build(context, project, PlanMode.EXPORT, longSide, fps)
        val out = File(context.cacheDir, "test_${System.nanoTime()}.mp4")
        val latch = CountDownLatch(1)
        var result: ExportResult? = null
        var error: ExportException? = null
        main.post {
            val transformer = Transformer.Builder(context)
                // The emulator's software HEVC encoder is capped at 512 px; H.264 keeps the requested size.
                .setVideoMimeType(androidx.media3.common.MimeTypes.VIDEO_H264)
                // Software GL on the emulator is slow; don't let the stall watchdog fail heavy compositions.
                .setMaxDelayBetweenMuxerSamplesMs(androidx.media3.common.C.TIME_UNSET)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { result = exportResult; latch.countDown() }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) { error = exportException; latch.countDown() }
                }).build()
            transformer.start(composition, out.absolutePath)
        }
        assertTrue("export timed out", latch.await(240, TimeUnit.SECONDS))
        error?.let { throw AssertionError("export failed: ${it.errorCodeName}", it) }
        return out to result!!
    }

    private fun frameAt(file: File, us: Long): Bitmap {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.absolutePath)
            return r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST)!!
        } finally { r.release() }
    }

    private fun assertColor(expected: Int, actual: Int, label: String) {
        val d = abs(Color.red(expected) - Color.red(actual)) + abs(Color.green(expected) - Color.green(actual)) + abs(Color.blue(expected) - Color.blue(actual))
        assertTrue("$label: expected #%06x got #%06x".format(expected and 0xFFFFFF, actual and 0xFFFFFF), d < 90)
    }

    /** Checks placement against the compositor: position, y direction, stacking order and rotation. */
    @Test fun layersArePlacedWhereTheModelSays() {
        val red = MediaProbe.probe(context, solidPng("red.png", Color.RED, 640, 360), "image/png")!!
        val green = MediaProbe.probe(context, solidPng("green.png", Color.GREEN, 320, 180), "image/png")!!
        val blue = MediaProbe.probe(context, solidPng("blue.png", Color.BLUE, 400, 100), "image/png")!!
        var p = Project("t1", "t", 0, 0, canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)).addToMainAt(listOf(red), 0)
        // Green: a quarter-size layer in the top-left quadrant. Blue: a wide bar rotated 90° (becomes vertical) right of center.
        p = p.withAssets(listOf(green, blue))
            .placeOnFreeTrack(TrackKind.OVERLAY, Clip(newId(), green.id, 0, 0, 3_000_000, transform = Transform(cx = 0.25f, cy = 0.25f, scale = 0.5f)))
        p = p.placeOnFreeTrack(TrackKind.OVERLAY, Clip(newId(), blue.id, 0, 0, 3_000_000, transform = Transform(cx = 0.75f, cy = 0.5f, scale = 0.25f, rotation = 90f)))
        val (file, result) = export(p, 1280)
        val f = frameAt(file, 1_500_000)
        assertEquals("frame ${f.width}x${f.height}, export ${result.width}x${result.height} via ${result.videoEncoderName}", 1280, f.width)
        assertEquals(720, f.height)
        assertColor(Color.GREEN, f.getPixel(320, 180), "overlay center (top-left quadrant)")
        assertColor(Color.RED, f.getPixel(320, 540), "main below the overlay")
        assertColor(Color.RED, f.getPixel(960, 600), "main bottom-right")
        // The rotated bar is 320×80 before rotation: vertical after it, so it covers (960, 360±150) but not (960±150, 360).
        assertColor(Color.BLUE, f.getPixel(960, 260), "rotated bar, above center")
        assertColor(Color.RED, f.getPixel(1110, 360), "beside the rotated bar")
    }

    /** A project using most features exports with the right duration and both tracks. */
    @Test fun richProjectExports() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val port = MediaProbe.probe(context, fixture("port.mp4"), "video/mp4")!!
        val photo = MediaProbe.probe(context, solidPng("photo.png", Color.rgb(200, 120, 40), 800, 600), "image/png")!!
        assertTrue(land.hasAudio)
        var p = Project("t2", "rich", 0, 0, canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30, Background(BackgroundMode.BLUR)))
            .addToMainAt(listOf(land, photo, port), 0)
        val clips = p.mainTrack.clips
        p = p.setTransition(clips[1].id, Transition(TransitionType.FADE, 500_000))
            .setTransition(clips[2].id, Transition(TransitionType.DIP_WHITE, 400_000))
            .updateClip(clips[0].id) { it.copy(filter = FilterSetting("teal_orange", 0.8f), adjust = Adjust(contrast = 0.2f, vignette = 0.5f, sharpen = 0.3f), crop = CropRect(left = 0.1f)) }
            .setSpeed(clips[2].id, 1.5f)
            .toggleKeyframe(clips[1].id, clips[1].startUs, 33_333)
        p = p.updateClip(clips[1].id) { it.withTransformAt(clips[1].startUs + 2_000_000, Transform(scale = 1.3f), 33_333) }
        p = p.addOverlayAt(port, 500_000)
        p = p.addTextAt(TextStyle(text = "Hello 你好", animIn = TextAnim.POP, animOut = TextAnim.FADE), 0, 2_000_000)
        p = p.addTextCues(listOf(Cue(200_000, 1_200_000, "Line one 第一句"), Cue(1_300_000, 2_500_000, "Line two")), TextStyle(role = TextRole.SUBTITLE, backgroundColor = 0x99000000))
        p = p.extractAudio(clips[0].id).first
        p = p.addAudioAt(land, 1_000_000, audioOnly = true)
        val expectedUs = p.durationUs
        val (file, result) = export(p, 1280)
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.absolutePath)
            val durMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
            assertTrue("duration $durMs ms vs ${expectedUs / 1000} ms", abs(durMs - expectedUs / 1000) < 150)
            assertEquals("yes", r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
            assertEquals("1280", r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH))
        } finally { r.release() }
        assertTrue(result.fileSizeBytes > 0)
    }

    @Test fun previewMuteSurvivesPlayerRebuildsAndRestoresAudio() {
        val asset = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val project = Project("mute", "Mute preview", 0, 0).addToMainAt(listOf(asset), 0)
        val surface = drainingSurface(960, 540)
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val engine = PreviewEngine(context)
            try {
                engine.attach(surface, Size(960, 540))
                assertEquals(1f, engine.player.volume, 0f)
                engine.update(project, 0)
                engine.audioMuted = true
                assertEquals(0f, engine.player.volume, 0f)
                val previousPlayer = engine.player
                engine.update(project, 500_000, force = true)
                assertTrue("preview player should have been replaced", previousPlayer !== engine.player)
                assertEquals(0f, engine.player.volume, 0f)
                engine.audioMuted = false
                assertEquals(1f, engine.player.volume, 0f)
                engine.update(project, 0, force = true)
                assertEquals(1f, engine.player.volume, 0f)
            } finally {
                engine.release()
            }
        }
    }

    /** The preview player plays a multi-layer composition without errors and advances. */
    @Test fun previewPlays() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val port = MediaProbe.probe(context, fixture("port.mp4"), "video/mp4")!!
        var p = Project("t3", "preview", 0, 0, canvas = CanvasSettings(AspectPreset.R9_16, ResolutionTier.FHD, 30)).addToMainAt(listOf(land, port), 0)
        p = p.setTransition(p.mainTrack.clips[1].id, Transition(TransitionType.PUSH_LEFT, 400_000)).addOverlayAt(land, 0)
            .addTextAt(TextStyle(text = "Preview"), 0)
        val latch = CountDownLatch(1)
        var error: PlaybackException? = null
        var engine: PreviewEngine? = null
        var surface: Surface? = null
        main.post {
            val e = PreviewEngine(context)
            engine = e
            surface = drainingSurface(540, 960)
            e.attach(surface!!, Size(540, 960))
            // Errors the engine could not recover from.
            e.onError = { message -> error = PlaybackException(message, null, PlaybackException.ERROR_CODE_UNSPECIFIED); latch.countDown() }
            e.update(p, 0)
            e.player.play()
            main.postDelayed({ latch.countDown() }, 2500)
        }
        latch.await(20, TimeUnit.SECONDS)
        var position = 0L
        val done = CountDownLatch(1)
        main.post {
            position = engine!!.positionUs
            // A transform-only change must not rebuild the pipeline.
            engine!!.update(p.updateClip(p.tracks.first { it.kind == TrackKind.OVERLAY }.clips[0].id) { it.copy(transform = Transform(scale = 0.3f)) }, position)
            engine!!.release(); surface?.release(); done.countDown()
        }
        done.await(5, TimeUnit.SECONDS)
        assertNull("playback error: ${error?.errorCodeName} ${error?.cause}", error)
        assertTrue("position $position", position > 300_000)
    }

    /**
     * An off-screen output that consumes every frame, like a screen does. (A SurfaceTexture nobody reads fills its
     * buffers, after which the GL thread blocks and releasing the player times out, leaking GPU memory.)
     */
    private fun drainingSurface(width: Int, height: Int): Surface {
        val reader = android.media.ImageReader.newInstance(width, height, android.graphics.PixelFormat.RGBA_8888, 3,
            android.hardware.HardwareBuffer.USAGE_GPU_COLOR_OUTPUT or android.hardware.HardwareBuffer.USAGE_CPU_READ_RARELY)
        reader.setOnImageAvailableListener({ r -> r.acquireLatestImage()?.close() }, drainHandler)
        readers += reader
        return reader.surface
    }
    private val drainThread = android.os.HandlerThread("drain").apply { start() }
    private val drainHandler = Handler(drainThread.looper)
    private val readers = mutableListOf<android.media.ImageReader>()

    @org.junit.After fun closeReaders() {
        readers.forEach { runCatching { it.close() } }
        readers.clear()
    }

    private fun <T> onMain(block: () -> T): T {
        var result: Any? = null
        val done = CountDownLatch(1)
        main.post { result = block(); done.countDown() }
        assertTrue("main thread timed out", done.await(10, TimeUnit.SECONDS))
        @Suppress("UNCHECKED_CAST") return result as T
    }

    /**
     * Editing between plays (a split, adding and removing a transition, which changes the number of layers) must leave
     * the preview playable, including from a position after a layer's last clip.
     */
    @Test fun previewPlaysAfterEdits() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)
        val base = Project("t6", "edits", 0, 0, canvas = canvas).addToMainAt(listOf(land, land, land), 0)
        val split = base.splitClip(base.mainTrack.clips[0].id, 1_500_000).first
        val faded = split.setTransition(split.mainTrack.clips[1].id, Transition(TransitionType.FADE, 500_000))
        val unfaded = faded.setTransition(faded.mainTrack.clips[1].id, null)
        var error: String? = null
        var rendered = 0L
        val surface = drainingSurface(960, 540)
        val engine = onMain {
            PreviewEngine(context).also { e ->
                e.onError = { error = it }
                e.frameListener = { t -> rendered = t }
                e.attach(surface, Size(960, 540))
            }
        }
        val results = mutableListOf<String>()
        fun playFrom(project: Project, atUs: Long, name: String) {
            onMain { engine.pause(); engine.update(project, atUs); engine.seekTo(atUs, scrubbing = false) }
            Thread.sleep(1200)
            onMain { engine.play(atUs, project.durationUs) }
            Thread.sleep(1800)
            val position = onMain { engine.positionUs }
            results += "$name: position ${position / 1000} ms"
            assertNull("$name: preview error $error", error)
            assertTrue("$name did not play from ${atUs / 1000} ms: ${results.joinToString("; ")}", position > atUs + 600_000)
        }
        try {
            playFrom(base, 0, "base")
            playFrom(split, 1_500_000, "split at the cut")
            playFrom(faded, 4_000_000, "fade added, after the first layer's clips")
            playFrom(unfaded, 2_000_000, "fade removed")
        } finally {
            onMain { engine.release(); surface.release() }
        }
        android.util.Log.i("EditsTest", results.joinToString("; ") + "; rendered ${rendered / 1000} ms")
    }

    /**
     * Plays [project] until the preview has rendered past [targetUs] or [timeoutMs] passes, and returns the latest
     * presentation time it rendered. Waiting for a target instead of sleeping a fixed time keeps slow software-rendered
     * emulators from failing; a frozen preview still never reaches the target.
     */
    private fun renderedUntil(project: Project, targetUs: Long, timeoutMs: Long = 40_000): Long {
        val maxRendered = java.util.concurrent.atomic.AtomicLong(0L)
        var engine: PreviewEngine? = null
        var surface: Surface? = null
        val started = CountDownLatch(1)
        main.post {
            val e = PreviewEngine(context)
            engine = e
            surface = drainingSurface(960, 540)
            e.attach(surface!!, Size(960, 540))
            e.frameListener = { presentationTimeUs -> maxRendered.accumulateAndGet(presentationTimeUs) { a, b -> maxOf(a, b) } }
            e.update(project, 0)
            e.player.play()
            started.countDown()
        }
        started.await(5, TimeUnit.SECONDS)
        val deadline = System.currentTimeMillis() + timeoutMs
        while (maxRendered.get() <= targetUs && System.currentTimeMillis() < deadline) Thread.sleep(100)
        val done = CountDownLatch(1)
        main.post { engine?.release(); surface?.release(); done.countDown() }
        done.await(5, TimeUnit.SECONDS)
        return maxRendered.get()
    }

    /** Dragging the playhead (many quick seeks), jumping to the end and back, then playing, all work. */
    @Test fun previewPlaysAfterSeeks() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)
        val p = Project("t8", "seeks", 0, 0, canvas = canvas).addToMainAt(listOf(land, land, land), 0).addOverlayAt(land, 4_000_000)
        var error: String? = null
        var rendered = -1L
        val surface = drainingSurface(960, 540)
        val engine = onMain {
            PreviewEngine(context).also { e ->
                e.onError = { error = it }
                e.frameListener = { t -> rendered = t }
                e.attach(surface, Size(960, 540))
                e.update(p, 0)
            }
        }
        try {
            Thread.sleep(1000)
            for (i in 1..20) { onMain { engine.seekTo(i * 200_000L, scrubbing = true) }; Thread.sleep(40) }
            onMain { engine.seekTo(4_500_000, scrubbing = false) }
            Thread.sleep(1500)
            assertTrue("no frame shown at the seek target (last ${rendered / 1000} ms)", rendered in 4_300_000..4_700_000)
            onMain { engine.play(4_500_000, p.durationUs) }
            Thread.sleep(1500)
            val afterDrag = onMain { engine.positionUs }
            assertTrue("did not play after dragging: ${afterDrag / 1000} ms", afterDrag > 5_100_000)
            onMain { engine.pause(); engine.seekTo(p.durationUs, scrubbing = false) }
            Thread.sleep(1000)
            onMain { engine.seekTo(0, scrubbing = false) }
            Thread.sleep(1000)
            onMain { engine.play(0, p.durationUs) }
            Thread.sleep(1500)
            val afterJump = onMain { engine.positionUs }
            assertTrue("did not play after jumping to the end and back: ${afterJump / 1000} ms", afterJump > 600_000)
            assertNull("preview error $error", error)
        } finally {
            onMain { engine.release(); surface.release() }
        }
    }

    /** Moving and resizing a layer while paused (many live updates, as a drag or pinch makes) shows the change and does not crash. */
    @Test fun previewShowsLiveEditsWhilePaused() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)
        val p = Project("t9", "live", 0, 0, canvas = canvas).addToMainAt(listOf(land), 0).addOverlayAt(land, 0)
        val overlay = p.tracks.first { it.kind == TrackKind.OVERLAY }.clips[0].id
        var error: String? = null
        var frames = 0
        val surface = drainingSurface(960, 540)
        val engine = onMain {
            PreviewEngine(context).also { e ->
                e.onError = { error = it }
                e.frameListener = { frames++ }
                e.attach(surface, Size(960, 540))
                e.update(p, 1_000_000)
            }
        }
        try {
            Thread.sleep(1200)
            val before = frames
            for (i in 1..30) {
                val q = p.updateClip(overlay) { it.copy(transform = Transform(cx = 0.3f + i * 0.01f, cy = 0.5f, scale = 0.3f + i * 0.01f)) }
                onMain { engine.update(q, 1_000_000) }
                Thread.sleep(30)
            }
            Thread.sleep(1500)
            assertNull("preview error $error", error)
            assertTrue("no new frame after the edits ($before -> $frames)", frames > before)
            onMain { engine.play(1_000_000, p.durationUs) }
            Thread.sleep(1200)
            assertTrue("did not play after the edits", onMain { engine.positionUs } > 1_500_000)
        } finally {
            onMain { engine.release(); surface.release() }
        }
    }

    /** Cuts, gaps and text on the main track play through without the picture stopping. */
    @Test fun previewPlaysThroughCuts() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)
        var p = Project("t7", "cuts", 0, 0, canvas = canvas).addToMainAt(listOf(land, land), 0).addTextAt(TextStyle(text = "Cut"), 0)
        p = p.trimStart(p.mainTrack.clips[1].id, 500_000) // a gap from 3.0 to 3.5 s
        val rendered = renderedUntil(p, 4_200_000)
        assertTrue("rendered only to ${rendered / 1000} ms", rendered > 4_200_000)
    }

    /**
     * Layers that start, change clips or end mid-playback must not stop the preview (Media3 1.9's compositor froze
     * there; see PreviewVideoCompositor): an overlay starting and ending, a split clip moved to an overlay track, and
     * a transition.
     */
    @Test fun previewRendersThroughLayerChanges() {
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val port = MediaProbe.probe(context, fixture("port.mp4"), "video/mp4")!!
        val canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)
        val two = Project("b", "b", 0, 0, canvas = canvas).addToMainAt(listOf(land, land), 0)
        val overlayMidway = two.addOverlayAt(port, 1_000_000) // starts at 1 s, ends at 3 s, main cut at 3 s
        // A split clip's second half moved onto an overlay track at 1.5 s (it starts mid-file).
        val splitToLayer = two.splitClip(two.mainTrack.clips[1].id, 4_500_000).let { (q, second) ->
            q.moveToOverlay(second!!).let { o -> o.moveClip(second, o.tracks.first { it.kind == TrackKind.OVERLAY }.id, 1_500_000) }
        }
        val transition = two.setTransition(two.mainTrack.clips[1].id, Transition(TransitionType.FADE, 500_000)).addOverlayAt(port, 1_000_000)
        val results = mutableListOf<String>()
        for ((name, proj) in listOf("overlayMidway" to overlayMidway, "splitToLayer" to splitToLayer, "transition" to transition)) {
            results += "$name rendered=${renderedUntil(proj, 3_500_000) / 1000}ms"
        }
        android.util.Log.i("LayerTest", results.joinToString("; "))
        assertTrue(results.joinToString("; "), results.all { it.substringAfter("rendered=").removeSuffix("ms").toLong() > 3500 })
    }

    /** Projects survive a save/load cycle through the repository. */
    @Test fun repositoryRoundTrip() {
        val repo = ProjectRepository(context)
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val p = Project(newId(), "repo", 1, 2).addToMainAt(listOf(land), 0).addTextAt(TextStyle(text = "字"), 0)
        repo.save(p)
        assertEquals(p, repo.load(p.id))
        assertNotNull(repo.list().firstOrNull { it.id == p.id })
        repo.delete(p.id)
        assertNull(repo.load(p.id))
    }
}
