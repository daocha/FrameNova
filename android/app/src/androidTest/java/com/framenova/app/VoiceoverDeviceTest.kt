package com.framenova.app

import android.Manifest
import android.app.Activity
import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.media3.common.util.UnstableApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.framenova.app.data.ProjectRepository
import com.framenova.app.model.MediaType
import com.framenova.app.model.newId
import com.framenova.app.ui.editor.EditorViewModel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@UnstableApi
@RunWith(AndroidJUnit4::class)
class VoiceoverDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as Application
    private val projectId = newId()
    private val store = ViewModelStore()
    private lateinit var activity: Activity
    private lateinit var vm: EditorViewModel
    private lateinit var repo: ProjectRepository

    @Before fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, Manifest.permission.RECORD_AUDIO)
        // Keep the app in the foreground so microphone access follows the normal recording flow.
        activity = instrumentation.startActivitySync(app.packageManager.getLaunchIntentForPackage(app.packageName)!!)
        repo = ProjectRepository(app)
        vm = onMain { ViewModelProvider(store, EditorViewModel.Factory(app, projectId))[EditorViewModel::class.java] }
    }

    @After fun tearDown() {
        onMain {
            store.clear()
            if (::activity.isInitialized) activity.finish()
        }
        if (::repo.isInitialized) repo.delete(projectId)
    }

    @Test fun recordingMutesPlaybackAndStoppingRestoresAudioAndImportsVoiceover() {
        onMain {
            assertEquals(1f, vm.engine.player.volume, 0f)
            val originalProject = vm.project
            vm.startRecording()
            assertTrue("recording failed: ${vm.message}", vm.recording)
            assertTrue(vm.engine.audioMuted)
            assertEquals(0f, vm.engine.player.volume, 0f)
            assertEquals(originalProject, vm.project)
            // Repeated starts must keep the same recording rather than open a second microphone session.
            vm.startRecording()
            assertEquals(1, File(repo.dir(projectId), "voice").listFiles()!!.size)
        }
        // Allow the encoder to produce a valid audio file before stopping the microphone.
        SystemClock.sleep(1200)
        onMain {
            vm.stopRecording()
            assertFalse(vm.recording)
            assertFalse(vm.engine.audioMuted)
            assertEquals(1f, vm.engine.player.volume, 0f)
        }
        val deadline = SystemClock.uptimeMillis() + 10_000
        while (onMain { vm.project.assets.isEmpty() } && SystemClock.uptimeMillis() < deadline) {
            SystemClock.sleep(50)
        }
        onMain {
            assertEquals("voice-over was not imported: ${vm.message}", 1, vm.project.assets.size)
            val asset = vm.project.assets.single()
            assertEquals(MediaType.AUDIO, asset.type)
            assertTrue(asset.durationUs > 0)
            val clip = vm.project.tracks.flatMap { it.clips }.single()
            assertEquals(asset.id, clip.assetId)
            assertEquals(vm.recordingStartUs, clip.startUs)
            assertTrue(vm.project.tracks.none { it.muted })
        }
    }

    @Test fun recordingStartupFailureRestoresPlaybackAudio() {
        // A file occupying the recording directory forces a real output-file failure.
        File(repo.dir(projectId), "voice").writeText("Recording directory unavailable")
        onMain {
            val originalProject = vm.project
            vm.startRecording()
            assertFalse(vm.recording)
            assertFalse(vm.engine.audioMuted)
            assertEquals(1f, vm.engine.player.volume, 0f)
            assertTrue(vm.message.orEmpty().startsWith("Couldn't start recording:"))
            assertEquals(originalProject, vm.project)
        }
    }

    @Test fun stoppingWithoutAnActiveRecordingLeavesPlaybackAndProjectUnchanged() {
        onMain {
            val originalProject = vm.project
            vm.stopRecording()
            assertFalse(vm.recording)
            assertFalse(vm.engine.audioMuted)
            assertEquals(1f, vm.engine.player.volume, 0f)
            assertEquals(originalProject, vm.project)
        }
    }

    private fun <T> onMain(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }
}
