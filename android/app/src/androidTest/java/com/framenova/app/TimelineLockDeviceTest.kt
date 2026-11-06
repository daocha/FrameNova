package com.framenova.app

import android.app.Application
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.SystemClock
import android.view.MotionEvent
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.media3.common.util.UnstableApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.framenova.app.data.ProjectRepository
import com.framenova.app.model.CanvasSettings
import com.framenova.app.model.MediaAsset
import com.framenova.app.model.MediaType
import com.framenova.app.model.Project
import com.framenova.app.model.ResolutionTier
import com.framenova.app.model.TrackKind
import com.framenova.app.model.addToMainAt
import com.framenova.app.model.clipForAsset
import com.framenova.app.model.newId
import com.framenova.app.model.placeOnFreeTrack
import com.framenova.app.model.withAssets
import com.framenova.app.ui.editor.Panel
import com.framenova.app.ui.editor.EditorViewModel
import com.framenova.app.ui.editor.EditorScreen
import com.framenova.app.ui.editor.TimelineView
import com.framenova.app.ui.theme.FrameNovaTheme
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@UnstableApi
@RunWith(AndroidJUnit4::class)
class TimelineLockDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun <T> onMain(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    @Test fun tappingLockClearsSelectionBlocksClipTapsAndUnlocksAgain() {
        val app = instrumentation.targetContext.applicationContext as Application
        val repo = ProjectRepository(app)
        val id = newId()
        val store = ViewModelStore()
        val activity = instrumentation.startActivitySync(app.packageManager.getLaunchIntentForPackage(app.packageName)!!) as MainActivity
        var origin = Offset.Zero
        var width = 0
        val density = app.resources.displayMetrics.density
        val vm = onMain {
            ViewModelProvider(store, EditorViewModel.Factory(app, id))[EditorViewModel::class.java].also { model ->
                model.addText()
                activity.setContent {
                    FrameNovaTheme {
                        TimelineView(
                            project = model.project, playheadUs = model.playheadUs, pxPerSecond = model.pxPerSecond,
                            selectedId = model.selectedId, selectedGapUs = model.selectedGapUs, media = model.media,
                            onScrub = model::scrubTo, onZoom = { model.pxPerSecond = it }, onSelect = { model.selectedId = it },
                            onGapTap = { model.selectedGapUs = it }, onMove = model::move, onTrim = model::trim,
                            onTransitionTap = {}, onClipDoubleTap = {}, onTrackHeaderTap = {}, onCoverTap = {},
                            onTrackLockTap = { model.toggleTrackLock(it.id) },
                            modifier = Modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInWindow(); width = it.size.width },
                        )
                    }
                }
            }
        }
        try {
            instrumentation.waitForIdleSync()
            SystemClock.sleep(300)
            val clip = onMain { vm.selectedId!! }
            val track = onMain { vm.project.trackOf(clip)!!.id }
            fun tap(x: Float, drift: Float = 0f) {
                val point = onMain { origin + Offset(x, 53 * density) }
                val time = SystemClock.uptimeMillis()
                MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, point.x, point.y, 0).also { instrumentation.sendPointerSync(it); it.recycle() }
                MotionEvent.obtain(time, time + 35, MotionEvent.ACTION_MOVE, point.x + drift, point.y, 0).also { instrumentation.sendPointerSync(it); it.recycle() }
                MotionEvent.obtain(time, time + 70, MotionEvent.ACTION_UP, point.x + drift, point.y, 0).also { instrumentation.sendPointerSync(it); it.recycle() }
                instrumentation.waitForIdleSync()
                SystemClock.sleep(100)
            }
            tap(45 * density, drift = 4 * density)
            onMain {
                assertTrue("The lock tap did not lock the track", vm.project.track(track)!!.locked)
                assertNull("Locking must clear selection", vm.selectedId)
            }
            tap(width / 2f + 30 * density)
            onMain { assertNull("A locked clip must not be selectable", vm.selectedId) }
            tap(45 * density)
            onMain { assertFalse("A second lock tap must unlock", vm.project.track(track)!!.locked) }
            tap(width / 2f + 30 * density)
            onMain { assertEquals(clip, vm.selectedId) }
        } finally {
            onMain { store.clear(); activity.finish() }
            repo.delete(id)
        }
    }

    @Test fun fullEditorLocksAnAddedMediaLayerInPortraitAndLandscape() {
        val app = instrumentation.targetContext.applicationContext as Application
        val repo = ProjectRepository(app)
        val id = newId()
        val file = java.io.File(repo.dir(id), "lock-fixture.png")
        val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.BLUE)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val asset = MediaAsset("fixture", file.toURI().toString(), MediaType.IMAGE, "Fixture", 3_000_000, 64, 64, hasVideo = true)
        repo.save(Project(id, "Layer lock regression", 0, 0, canvas = CanvasSettings(tier = ResolutionTier.HD)).addToMainAt(listOf(asset), 0))
        val store = ViewModelStore()
        val activity = instrumentation.startActivitySync(app.packageManager.getLaunchIntentForPackage(app.packageName)!!) as MainActivity
        val vm = onMain {
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            ViewModelProvider(store, EditorViewModel.Factory(app, id))[EditorViewModel::class.java].also { model ->
                activity.setContent { FrameNovaTheme { EditorScreen(model, {}) } }
            }
        }
        try {
            bounds("Lock main track")
            // Add a layer after the timeline has already been composed, matching the normal import flow.
            val clip = clipForAsset(asset, 0)
            onMain {
                vm.commit(vm.project.placeOnFreeTrack(TrackKind.OVERLAY, clip))
                vm.selectedId = clip.id
            }
            val track = onMain { vm.project.trackOf(clip.id)!!.id }
            for (orientation in listOf(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)) {
                onMain { activity.requestedOrientation = orientation }
                val expected = if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) Configuration.ORIENTATION_PORTRAIT else Configuration.ORIENTATION_LANDSCAPE
                val deadline = SystemClock.uptimeMillis() + 5_000
                while (onMain { activity.resources.configuration.orientation } != expected && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(50)
                assertEquals(expected, onMain { activity.resources.configuration.orientation })
                tap(bounds("Lock layer"))
                onMain {
                    assertTrue("Full editor lock button must lock the added layer", vm.project.track(track)!!.locked)
                    assertNotEquals(clip.id, vm.selectedId)
                }
                val header = bounds("Unlock layer")
                val timeline = bounds("Timeline")
                tap(Rect(timeline.centerX() + 50, header.top, timeline.centerX() + 70, header.bottom))
                onMain { assertNotEquals("Locked layer must reject timeline selection", clip.id, vm.selectedId) }
                tap(bounds("Unlock layer"))
                onMain { assertFalse(vm.project.track(track)!!.locked) }
                val unlocked = bounds("Lock layer")
                val afterUnlock = bounds("Timeline")
                tap(Rect(afterUnlock.centerX() + 50, unlocked.top, afterUnlock.centerX() + 70, unlocked.bottom))
                onMain { assertEquals("Unlocked layer must accept timeline selection", clip.id, vm.selectedId) }
            }
            val before = onMain { vm.project.clip(clip.id)!! }
            val previousTrack = onMain { vm.project.trackOf(clip.id)!!.id }
            tap(bounds("To new layer"))
            onMain {
                assertNotEquals(previousTrack, vm.project.trackOf(clip.id)!!.id)
                assertEquals(before, vm.project.clip(clip.id))
                assertEquals(clip.id, vm.selectedId)
            }
            val samples = 16_000
            val wave = java.nio.ByteBuffer.allocate(44 + samples * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            wave.put("RIFF".toByteArray()).putInt(36 + samples * 2).put("WAVEfmt ".toByteArray())
                .putInt(16).putShort(1).putShort(1).putInt(samples).putInt(samples * 2).putShort(2).putShort(16)
                .put("data".toByteArray()).putInt(samples * 2)
            val audioFile = java.io.File(repo.dir(id), "fade-fixture.wav").apply { writeBytes(wave.array()) }
            val audio = MediaAsset(newId(), audioFile.toURI().toString(), MediaType.AUDIO, "Audio fixture", 1_000_000, hasAudio = true)
            val sound = clipForAsset(audio, 0)
            onMain {
                vm.commit(vm.project.withAssets(listOf(audio)).placeOnFreeTrack(TrackKind.AUDIO, sound))
                vm.selectedId = sound.id
            }
            tap(bounds("Volume"))
            onMain { assertEquals(Panel.VOLUME, vm.panel) }
            bounds("Fade in")
            bounds("Fade out")
            for (label in listOf("Fade in", "Fade out")) {
                val slider = bounds(label, rangeOnly = true)
                val x = slider.left + slider.width() * 3 / 4
                tap(Rect(x - 1, slider.centerY() - 1, x + 1, slider.centerY() + 1))
            }
            onMain {
                assertTrue("Fade-in slider tap must save the duration", vm.selectedClip!!.fadeInUs > 0)
                assertTrue("Fade-out slider tap must save the duration", vm.selectedClip!!.fadeOutUs > 0)
            }
        } finally {
            onMain { store.clear(); activity.finish() }
            repo.delete(id)
        }
    }

    private fun bounds(label: String, rangeOnly: Boolean = false): Rect {
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun find(node: android.view.accessibility.AccessibilityNodeInfo?): Rect? {
            if (node == null) return null
            if ((node.contentDescription?.toString() == label || node.text?.toString() == label) && node.isVisibleToUser) {
                var target: android.view.accessibility.AccessibilityNodeInfo? = node
                if (rangeOnly) while (target != null && target.rangeInfo == null) target = target.parent
                if (target != null) return Rect().also { target.getBoundsInScreen(it) }
            }
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        while (SystemClock.uptimeMillis() < deadline) {
            if (android.os.Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.clearCache()
            find(instrumentation.uiAutomation.rootInActiveWindow)?.let { return it }
            SystemClock.sleep(50)
        }
        val tree = StringBuilder()
        fun describe(node: android.view.accessibility.AccessibilityNodeInfo?, depth: Int = 0) {
            if (node == null || depth > 15) return
            val rect = Rect(); node.getBoundsInScreen(rect)
            tree.append("\n${node.packageName} ${node.className} ${node.text} ${node.contentDescription} $rect")
            for (index in 0 until node.childCount) describe(node.getChild(index), depth + 1)
        }
        describe(instrumentation.uiAutomation.rootInActiveWindow)
        throw AssertionError("No visible editor control: $label$tree")
    }

    private fun tap(bounds: Rect) {
        val time = SystemClock.uptimeMillis()
        MotionEvent.obtain(time, time, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0).also { instrumentation.sendPointerSync(it); it.recycle() }
        MotionEvent.obtain(time, time + 70, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0).also { instrumentation.sendPointerSync(it); it.recycle() }
        instrumentation.waitForIdleSync()
        SystemClock.sleep(100)
    }
}
