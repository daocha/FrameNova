package com.framenova.app

import com.framenova.app.ui.editor.TimelineScrubPosition
import org.junit.Assert.assertEquals
import org.junit.Test

class TimelineScrubPositionTest {
    private val durationUs = 20_000_000L
    private val pps = 100f

    @Test fun rapidReversalUsesEveryPointerDeltaWithoutWaitingForRedraw() {
        val scrub = TimelineScrubPosition(10_000_000L)
        assertEquals(11_000_000L, scrub.moveBy(-100f, pps, durationUs))
        assertEquals(12_000_000L, scrub.moveBy(-100f, pps, durationUs))
        assertEquals(11_500_000L, scrub.moveBy(50f, pps, durationUs))
        assertEquals(11_000_000L, scrub.moveBy(50f, pps, durationUs))
        repeat(10) {
            assertEquals(12_000_000L, scrub.moveBy(-100f, pps, durationUs))
            assertEquals(11_000_000L, scrub.moveBy(100f, pps, durationUs))
        }
    }

    @Test fun reversingAtEitherBoundaryMovesImmediately() {
        val scrub = TimelineScrubPosition(1_000_000L)
        assertEquals(0L, scrub.moveBy(500f, pps, durationUs))
        assertEquals(500_000L, scrub.moveBy(-50f, pps, durationUs))
        assertEquals(durationUs, scrub.moveBy(-3000f, pps, durationUs))
        assertEquals(durationUs - 500_000L, scrub.moveBy(50f, pps, durationUs))
    }

    @Test fun flingContinuesFromLastDragPositionBeforeRedraw() {
        val scrub = TimelineScrubPosition(10_000_000L)
        scrub.moveBy(-100f, pps, durationUs)
        assertEquals(11_200_000L, scrub.moveBy(-20f, pps, durationUs))
        assertEquals(11_300_000L, scrub.moveBy(-10f, pps, durationUs))
        assertEquals(11_350_000L, scrub.moveBy(-5f, pps, durationUs))
        assertEquals(11_350_000L, scrub.positionUs)
    }

    @Test fun emptyProjectStaysAtZero() {
        val scrub = TimelineScrubPosition(0L)
        assertEquals(0L, scrub.moveBy(-100f, pps, 0L))
        assertEquals(0L, scrub.moveBy(100f, pps, 0L))
    }
}
