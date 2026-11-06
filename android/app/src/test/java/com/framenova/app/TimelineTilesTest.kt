package com.framenova.app

import com.framenova.app.ui.editor.visibleTimelineTiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TimelineTilesTest {
    @Test fun longZoomedClipVisitsOnlyVisibleTiles() {
        val tiles = visibleTimelineTiles(-5_760_000f, 5_760_000f, 100f, 1080f)
        assertEquals(57600..57610, tiles)
        assertTrue(tiles.count() <= 12)
    }
    @Test fun partialTilesKeepTheirSourceAlignment() {
        assertEquals(1..4, visibleTimelineTiles(-125f, 500f, 100f, 300f))
        assertEquals(0..1, visibleTimelineTiles(125f, 300f, 100f, 500f))
        assertTrue(visibleTimelineTiles(-500f, 0f, 100f, 300f).isEmpty())
        assertTrue(visibleTimelineTiles(300f, 500f, 100f, 300f).isEmpty())
    }
}
