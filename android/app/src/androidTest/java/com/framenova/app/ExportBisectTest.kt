package com.framenova.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.framenova.app.engine.CompositionFactory
import com.framenova.app.engine.FontManager
import com.framenova.app.engine.MediaProbe
import com.framenova.app.engine.PlanMode
import com.framenova.app.model.*
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Exports one feature at a time, so a failing combination points at its cause. */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class ExportBisectTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val main = Handler(Looper.getMainLooper())

    private fun fixture(name: String): Uri {
        val out = File(context.cacheDir, "fixtures/$name").apply { parentFile?.mkdirs() }
        InstrumentationRegistry.getInstrumentation().context.assets.open(name).use { i -> out.outputStream().use { i.copyTo(it) } }
        return Uri.fromFile(out)
    }

    /** Renders speed changes first, exactly as the editor does before exporting. */
    private fun prepareSpeed(project: Project) = kotlinx.coroutines.runBlocking {
        project.tracks.flatMap { it.clips }.forEach { c ->
            val a = project.asset(c.assetId)
            if (com.framenova.app.engine.SpeedRenders.needsRender(c, a)) com.framenova.app.engine.SpeedRenders.render(context, c, a!!)
        }
    }

    private fun run(project: Project): String {
        prepareSpeed(project)
        val (composition, _) = CompositionFactory.build(context, project, PlanMode.EXPORT, 640, 30)
        val out = File(context.cacheDir, "bisect_${System.nanoTime()}.mp4")
        val latch = CountDownLatch(1)
        var outcome = "timeout"
        var transformer: Transformer? = null
        main.post {
            transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { outcome = "ok ${exportResult.durationMs}ms"; latch.countDown() }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        outcome = "error ${exportException.errorCodeName}: ${exportException.cause}"; latch.countDown()
                    }
                }).build().also { it.start(composition, out.absolutePath) }
        }
        if (!latch.await(45, TimeUnit.SECONDS)) {
            androidx.media3.effect.DebugTraceUtil.generateTraceSummary().chunked(3000).forEach { Log.i("ExportBisectTrace", it) }
            main.post { transformer?.cancel() }
        }
        out.delete()
        return outcome
    }

    @Test fun bisect() {
        FontManager.init(context)
        androidx.media3.effect.DebugTraceUtil.enableTracing = true
        val land = MediaProbe.probe(context, fixture("land.mp4"), "video/mp4")!!
        val port = MediaProbe.probe(context, fixture("port.mp4"), "video/mp4")!!
        val photoFile = File(context.cacheDir, "fixtures/bisect.png").apply {
            outputStream().use { Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.YELLOW) }.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        val photo = MediaProbe.probe(context, Uri.fromFile(photoFile), "image/png")!!
        val base = Project("b", "b", 0, 0, canvas = CanvasSettings(AspectPreset.R16_9, ResolutionTier.HD, 30)).addToMainAt(listOf(land, photo, port), 0)
        val c = base.mainTrack.clips
        // Cumulative: each step adds one feature to the previous project, mirroring EngineDeviceTest.richProjectExports.
        val steps = listOf<Pair<String, (Project) -> Project>>(
            "transitions" to { p -> p.setTransition(c[1].id, Transition(TransitionType.FADE, 500_000)).setTransition(c[2].id, Transition(TransitionType.DIP_WHITE, 400_000)) },
            "color" to { p -> p.updateClip(c[0].id) { it.copy(filter = FilterSetting("teal_orange", 0.8f), adjust = Adjust(contrast = 0.2f, vignette = 0.5f, sharpen = 0.3f), crop = CropRect(left = 0.1f)) } },
            "speed" to { p -> p.setSpeed(c[2].id, 1.5f) },
            "keyframes" to { p -> p.toggleKeyframe(c[1].id, p.clip(c[1].id)!!.startUs, 33_333).let { q -> q.updateClip(c[1].id) { it.withTransformAt(it.startUs + 2_000_000, Transform(scale = 1.3f), 33_333) } } },
            "blur" to { p -> p.copy(canvas = p.canvas.copy(background = Background(BackgroundMode.BLUR))) },
            "overlay" to { p -> p.addOverlayAt(port, 500_000) },
            "text" to { p -> p.addTextAt(TextStyle(text = "Hello 你好", animIn = TextAnim.POP, animOut = TextAnim.FADE), 0, 2_000_000) },
            "subtitles" to { p -> p.addTextCues(listOf(Cue(200_000, 1_200_000, "Line one"), Cue(1_300_000, 2_500_000, "Line two")), TextStyle(role = TextRole.SUBTITLE)) },
            "extract" to { p -> p.extractAudio(c[0].id).first },
            "audioTrack" to { p -> p.addAudioAt(land, 1_000_000, audioOnly = true) },
        )
        val blurBase = base.copy(canvas = base.canvas.copy(background = Background(BackgroundMode.BLUR)))
        val variants = linkedMapOf(
            "blur+speed+all" to blurBase.setSpeed(c[2].id, 1.5f).setSpeed(c[0].id, 0.5f).setTransition(c[1].id, Transition(TransitionType.FADE)),
            "blur+speed" to blurBase.setSpeed(c[2].id, 1.5f),
            "blur+speed#2" to blurBase.setSpeed(c[2].id, 1.5f).copy(name = "2"),
            "blur+speed#3" to blurBase.setSpeed(c[2].id, 1.5f).copy(name = "3"),
            "blur+speedMiddle" to blurBase.setSpeed(c[1].id, 1.5f).setSpeed(c[0].id, 2f),
            "speed+overlaySameStart" to base.setSpeed(c[2].id, 1.5f).addOverlayAt(land, 6_000_000),
            "speed+overlaySpanning" to base.setSpeed(c[2].id, 1.5f).addOverlayAt(land, 5_000_000),
            "speed+sameFileOverlay" to base.setSpeed(c[2].id, 1.5f).addOverlayAt(port, 6_000_000),
            "spedOverlay+main" to base.addOverlayAt(port, 3_000_000).let { q -> q.setSpeed(q.tracks.first { it.kind == TrackKind.OVERLAY }.clips[0].id, 2f) },
        )
        val results = variants.map { (name, p) -> "$name: ${run(p)}".also { Log.i("ExportBisect", it) } }
        assertTrue(results.joinToString("\n"), results.all { it.contains(": ok") })
    }
}
