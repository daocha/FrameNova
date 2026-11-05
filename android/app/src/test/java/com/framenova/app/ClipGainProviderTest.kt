package com.framenova.app

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import com.framenova.app.engine.ClipGainProvider
import org.junit.Assert.assertEquals
import org.junit.Test

@UnstableApi
class ClipGainProviderTest {
    @Test fun fadesMultiplyVolumeAtEveryPositionIncludingSeeks() {
        val gain = ClipGainProvider(4_000_000, 0.4f, 1_000_000, 1_000_000)
        fun at(seconds: Double) = gain.getGainFactorAtSamplePosition((seconds * 48_000).toLong(), 48_000)
        assertEquals(0f, at(0.0), 0.0001f)
        assertEquals(0.2f, at(0.5), 0.0001f)
        assertEquals(0.4f, at(2.0), 0.0001f)
        assertEquals(0.2f, at(3.5), 0.0001f)
        assertEquals(0f, at(4.0), 0.0001f)
    }

    @Test fun mutedFadesNeverLeakAudio() {
        val gain = ClipGainProvider(4_000_000, 0f, 2_000_000, 2_000_000)
        for (frame in listOf(0L, 24_000, 48_000, 96_000, 168_000)) {
            assertEquals(0f, gain.getGainFactorAtSamplePosition(frame, 48_000), 0f)
        }
    }

    @Test fun unityBypassStopsBeforeFadeOutAndIsDisabledInsideFades() {
        val gain = ClipGainProvider(4_000_000, 1f, 1_000_000, 1_000_000)
        assertEquals(C.TIME_UNSET, gain.isUnityUntil(0, 48_000))
        assertEquals(144_000L, gain.isUnityUntil(96_000, 48_000))
        assertEquals(144_001L, gain.isUnityUntil(144_000, 48_000))
        assertEquals(C.TIME_UNSET, gain.isUnityUntil(168_000, 48_000))
        assertEquals(C.TIME_END_OF_SOURCE, ClipGainProvider(4_000_000, 1f, 0, 0).isUnityUntil(0, 48_000))
        assertEquals(24_001L, ClipGainProvider(4_000_000, 2f, 1_000_000, 0).isUnityUntil(24_000, 48_000))
    }
}
