package com.framenova.app.ui.editor

/** Keeps pointer and animation updates independent of when the timeline next recomposes. */
internal class TimelineScrubPosition(startUs: Long) {
    var positionUs: Long = startUs
        private set

    fun moveBy(deltaPx: Float, pxPerSecond: Float, durationUs: Long): Long {
        positionUs = (positionUs - (deltaPx / pxPerSecond * 1_000_000f).toLong())
            .coerceIn(0L, durationUs.coerceAtLeast(0L))
        return positionUs
    }
}
