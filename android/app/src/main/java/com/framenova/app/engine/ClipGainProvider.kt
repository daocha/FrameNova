package com.framenova.app.engine

import androidx.media3.common.C
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import kotlin.math.min

/** Clip volume multiplied by its fade envelope, including muted clips and seeks into a fade. */
@UnstableApi
internal class ClipGainProvider(
    durationUs: Long,
    private val volume: Float,
    fadeInUs: Long,
    fadeOutUs: Long,
) : GainProcessor.GainProvider {
    private val duration = durationUs.coerceAtLeast(1)
    private val fadeIn = fadeInUs.coerceIn(0, duration)
    private val fadeOut = fadeOutUs.coerceIn(0, duration)

    override fun getGainFactorAtSamplePosition(samplePosition: Long, sampleRate: Int): Float {
        val timeUs = samplePosition * 1_000_000L / sampleRate
        val incoming = if (fadeIn > 0) (timeUs.toDouble() / fadeIn).coerceIn(0.0, 1.0) else 1.0
        val outgoing = if (fadeOut > 0) ((duration - timeUs).toDouble() / fadeOut).coerceIn(0.0, 1.0) else 1.0
        return volume * min(incoming, outgoing).toFloat()
    }

    override fun isUnityUntil(samplePosition: Long, sampleRate: Int): Long {
        if (getGainFactorAtSamplePosition(samplePosition, sampleRate) != 1f) return C.TIME_UNSET
        val timeUs = samplePosition * 1_000_000L / sampleRate
        if (volume != 1f || timeUs < fadeIn || (fadeOut > 0 && timeUs >= duration - fadeOut)) return samplePosition + 1
        return if (fadeOut == 0L) C.TIME_END_OF_SOURCE else maxOf(samplePosition + 1, (duration - fadeOut) * sampleRate / 1_000_000L)
    }
}
