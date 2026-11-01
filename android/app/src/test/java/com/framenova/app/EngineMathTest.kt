package com.framenova.app

import com.framenova.app.engine.Filters
import com.framenova.app.engine.LayerMath
import com.framenova.app.engine.TransitionMath
import com.framenova.app.model.CropRect
import com.framenova.app.model.Subtitles
import com.framenova.app.model.Transform
import com.framenova.app.model.TransitionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineMathTest {
    @Test fun fitGeometryFillsMatchingCanvas() {
        val g = LayerMath.geometry(1920, 1080, CropRect(), Transform(), 3840, 2160)
        assertEquals(3840f, g.width, 0.5f)
        assertEquals(2160f, g.height, 0.5f)
        assertEquals(1920f, g.centerX, 0.01f)
    }

    @Test fun portraitClipIsPillarboxed() {
        val g = LayerMath.geometry(1080, 1920, CropRect(), Transform(), 1920, 1080)
        assertEquals(1080f, g.height, 0.5f)
        assertEquals(607.5f, g.width, 0.5f)
    }

    @Test fun hitTestHonorsRotation() {
        val g = LayerMath.geometry(1000, 100, CropRect(), Transform(scale = 0.5f, rotation = 90f), 1000, 1000)
        assertTrue(g.contains(500f, 700f))
        assertFalse(g.contains(700f, 500f))
    }

    @Test fun fadeLooksTheSameWhicheverLayerIsOnTop() {
        // Incoming on top: it fades in. Incoming below: the outgoing one fades out.
        assertEquals(0.5f, TransitionMath.fx(TransitionType.FADE, 0.5f, incoming = true, incomingOnTop = true).alpha, 0.001f)
        assertEquals(1f, TransitionMath.fx(TransitionType.FADE, 0.5f, incoming = false, incomingOnTop = true).alpha, 0.001f)
        assertEquals(0.5f, TransitionMath.fx(TransitionType.FADE, 0.5f, incoming = false, incomingOnTop = false).alpha, 0.001f)
        assertEquals(1f, TransitionMath.fx(TransitionType.FADE, 0.5f, incoming = true, incomingOnTop = false).alpha, 0.001f)
    }

    @Test fun pushMovesBothClips() {
        val out = TransitionMath.fx(TransitionType.PUSH_LEFT, 1f, incoming = false, incomingOnTop = true)
        val inc = TransitionMath.fx(TransitionType.PUSH_LEFT, 1f, incoming = true, incomingOnTop = true)
        assertEquals(-1f, out.dx, 0.001f)
        assertEquals(0f, inc.dx, 0.001f)
        assertEquals(1f, TransitionMath.dipAlpha(0.5f), 0.001f)
        assertEquals(0f, TransitionMath.dipAlpha(0f), 0.001f)
    }

    @Test fun filterCubeIsIdentityAtZeroIntensity() {
        val def = Filters.byId("teal_orange")!!
        val cube = Filters.cube(def, 0f, 5)
        assertEquals(0xFF000000.toInt(), cube[0][0][0])
        assertEquals(0xFFFFFFFF.toInt(), cube[4][4][4])
        assertEquals(0xFFFF0000.toInt(), cube[4][0][0])
        assertEquals(0xFF0000FF.toInt(), cube[0][0][4])
    }

    @Test fun parsesSrt() {
        val cues = Subtitles.parse("1\n00:00:01,500 --> 00:00:03,000\nHello\n<i>world</i>\n\n2\n00:00:04,000 --> 00:00:05,250\n你好\n")
        assertEquals(2, cues.size)
        assertEquals(1_500_000L, cues[0].first)
        assertEquals("Hello\nworld", cues[0].third)
        assertEquals(5_250_000L, cues[1].second)
    }

    @Test fun parsesLrcLyrics() {
        val cues = Subtitles.parse("[ti:Song]\n[00:01.00]第一句\n[00:04.50]Second line\n[00:08.00]\n", "song.lrc")
        assertEquals(2, cues.size)
        assertEquals(1_000_000L, cues[0].first)
        assertEquals(4_500_000L, cues[0].second)
        assertEquals(8_000_000L, cues[1].second)
    }

    @Test fun srtRoundTrip() {
        val cues = listOf(Triple(0L, 1_200_000L, "a"), Triple(61_000_000L, 62_500_000L, "b"))
        assertEquals(cues, Subtitles.parse(Subtitles.toSrt(cues)))
    }
}
