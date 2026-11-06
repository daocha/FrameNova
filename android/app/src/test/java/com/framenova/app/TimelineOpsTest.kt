package com.framenova.app

import com.framenova.app.data.ProjectRepository
import com.framenova.app.model.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TimelineOpsTest {
    private val video = MediaAsset("v", "content://v", MediaType.VIDEO, "v.mp4", 10_000_000, 3840, 2160, hasAudio = true, hasVideo = true)
    private val video2 = video.copy(id = "v2", uri = "content://v2")
    private val photo = MediaAsset("p", "content://p", MediaType.IMAGE, "p.jpg", 0, 4000, 3000, hasVideo = true)
    private val song = MediaAsset("a", "content://a", MediaType.AUDIO, "a.m4a", 60_000_000, hasAudio = true)

    @Test fun trimStartRetainsAnimatedPoseBetweenAndAfterKeys() {
        val original = Clip(id = "animated", assetId = video.id, startUs = 0, srcOutUs = 10_000_000,
            keyframes = listOf(Keyframe(0, Transform(cx = 0.2f)), Keyframe(4_000_000, Transform(cx = 0.8f), easing = Easing.LINEAR)))
        val project = Project("trim", "Trim", 0, 0, assets = listOf(video), tracks = listOf(Track("main", TrackKind.MAIN, listOf(original))))
        for (delta in listOf(2_000_000L, 4_000_000L, 6_000_000L)) {
            val trimmed = project.trimStart(original.id, delta).clip(original.id)!!
            assertEquals(original.endUs, trimmed.endUs)
            assertEquals(original.transformAt(delta), trimmed.transformAt(trimmed.startUs))
            assertEquals(1, trimmed.keyframes.count { it.offsetUs == 0L })
        }
        val trimmed = project.trimStart(original.id, 2_000_000).clip(original.id)!!
        assertEquals(original.transformAt(3_000_000).cx, trimmed.transformAt(3_000_000).cx, 0.0001f)
    }

    private fun base() = Project("id", "Test", 0, 0).addToMainAt(listOf(video, photo, video2), 0)

    @Test fun openingCoverShiftsAllTracksAndRespectsLocks() {
        val p = base().addAudioAt(song, 500_000).copy(coverAssetId = photo.id)
        val covered = p.prependCover()
        assertEquals(photo.id, covered.mainTrack.clips.first().assetId)
        assertEquals(0L, covered.mainTrack.clips.first().startUs)
        assertEquals(3_000_000L, covered.mainTrack.clips.first().durationUs)
        for (track in p.tracks) for (clip in track.clips) {
            val shifted = covered.clip(clip.id)!!
            assertEquals(clip.startUs + 3_000_000L, shifted.startUs)
            assertEquals(clip.srcInUs, shifted.srcInUs)
            assertEquals(clip.srcOutUs, shifted.srcOutUs)
        }
        val locked = p.updateTrack(p.mainTrack.id) { it.copy(locked = true) }
        assertEquals(locked, locked.prependCover())
        assertEquals(p.copy(coverAssetId = song.id), p.copy(coverAssetId = song.id).prependCover())
    }

    @Test fun trackLockDisablesSelectionUntilUnlocked() {
        val p = base()
        val id = p.mainTrack.clips.first().id
        assertEquals(id, p.selectableClipId(id))
        val locked = p.updateTrack(p.mainTrack.id) { it.copy(locked = true) }
        assertNull(locked.selectableClipId(id))
        assertNull(locked.selectableClipId("missing"))
        val unlocked = locked.updateTrack(p.mainTrack.id) { it.copy(locked = false) }
        assertEquals(id, unlocked.selectableClipId(id))
        assertEquals(p.mainTrack.clips, unlocked.mainTrack.clips)
    }

    @Test fun addingLayerSkipsLockedTrackEvenWhenItsTimeRangeIsFree() {
        val existing = clipForAsset(photo, 0)
        val layer = Track("locked-layer", TrackKind.OVERLAY, listOf(existing), locked = true)
        val p = base().let { it.copy(tracks = listOf(layer) + it.tracks) }
        val added = clipForAsset(photo, 5_000_000)
        val next = p.placeOnFreeTrack(TrackKind.OVERLAY, added, preferTrackId = layer.id)
        assertTrue(p.preservesLockedClips(next))
        assertTrue(next.trackOf(added.id)?.id != layer.id)
        assertNotNull(next.clip(added.id))
    }

    @Test fun lockedTrackRejectsClipEditsButAllowsUnlockAndMute() {
        val p = base().let { it.copy(tracks = it.tracks.map { t -> t.copy(locked = true) }) }
        assertTrue(!p.preservesLockedClips(p.copy(tracks = emptyList())))
        assertTrue(!p.preservesLockedClips(p.copy(tracks = p.tracks.map { it.copy(clips = emptyList()) })))
        assertTrue(p.preservesLockedClips(p.copy(tracks = p.tracks.map { it.copy(locked = false) })))
        assertTrue(p.preservesLockedClips(p.copy(tracks = p.tracks.map { it.copy(muted = true) })))
    }

    @Test fun mainTrackIsLaidEndToEnd() {
        val p = base()
        val clips = p.mainTrack.clips
        assertEquals(listOf(0L, 10_000_000L, 13_000_000L), clips.map { it.startUs })
        assertEquals(23_000_000L, p.durationUs)
    }

    @Test fun transitionsOverlapAndAreClamped() {
        var p = base()
        val second = p.mainTrack.clips[1]
        p = p.setTransition(second.id, Transition(TransitionType.FADE, 5_000_000))
        val clips = p.mainTrack.clips
        // Clamped to half the shorter neighbour (the 3 s photo).
        assertEquals(1_500_000L, clips[1].transitionIn!!.durationUs)
        assertEquals(10_000_000L - 1_500_000L, clips[1].startUs)
        assertEquals(clips[1].endUs, clips[2].startUs)
        // The first clip never has an incoming transition.
        p = p.setTransition(clips[0].id, Transition(TransitionType.FADE))
        assertNull(p.mainTrack.clips[0].transitionIn)
    }

    @Test fun splitKeepsSourceContinuity() {
        val p = base()
        val first = p.mainTrack.clips[0]
        val (split, secondId) = p.splitClip(first.id, 4_000_000)
        assertNotNull(secondId)
        val a = split.clip(first.id)!!
        val b = split.clip(secondId!!)!!
        assertEquals(4_000_000L, a.srcOutUs)
        assertEquals(4_000_000L, b.srcInUs)
        assertEquals(4_000_000L, b.startUs)
        assertEquals(p.durationUs, split.durationUs)
    }

    @Test fun splitRespectsSpeed() {
        var p = base()
        val first = p.mainTrack.clips[0]
        p = p.setSpeed(first.id, 2f)
        assertEquals(5_000_000L, p.clip(first.id)!!.durationUs)
        val (split, second) = p.splitClip(first.id, 1_000_000)
        assertEquals(2_000_000L, split.clip(second!!)!!.srcInUs)
    }

    @Test fun trimClampsToSource() {
        var p = base()
        val id = p.mainTrack.clips[0].id
        p = p.trimEnd(id, 5_000_000) // cannot extend past the source
        assertEquals(10_000_000L, p.clip(id)!!.srcOutUs)
        p = p.trimStart(id, 2_000_000)
        assertEquals(2_000_000L, p.clip(id)!!.srcInUs)
        assertEquals(2_000_000L, p.clip(id)!!.startUs) // the clip's end stays put, leaving a gap before it
        assertEquals(10_000_000L, p.clip(id)!!.endUs)
        p = p.trimStart(id, -9_000_000)
        assertEquals(0L, p.clip(id)!!.srcInUs)
        assertEquals(0L, p.clip(id)!!.startUs)
    }

    @Test fun stillsStretchAndPushLaterClips() {
        var p = base()
        val id = p.mainTrack.clips[1].id
        p = p.trimEnd(id, 7_000_000)
        assertEquals(10_000_000L, p.clip(id)!!.durationUs)
        assertEquals(20_000_000L, p.mainTrack.clips[2].startUs)
    }

    @Test fun splitThenTrimLeavesAGap() {
        val p = Project("id", "Test", 0, 0).addToMainAt(listOf(video.copy(durationUs = 50_000_000)), 0)
        val id = p.mainTrack.clips[0].id
        val (split, second) = p.splitClip(id, 25_000_000)
        val q = split.trimStart(second!!, 3_000_000)
        val b = q.clip(second)!!
        assertEquals(28_000_000L, b.startUs)
        assertEquals(50_000_000L, b.endUs)
        assertEquals(28_000_000L, b.srcInUs)
        assertEquals(25_000_000L, q.clip(id)!!.endUs)
        assertEquals(25_000_000L until 28_000_000L, q.mainGapAt(26_000_000))
        // Closing the gap moves the second part back.
        val closed = q.deleteMainGap(26_000_000)
        assertEquals(25_000_000L, closed.clip(second)!!.startUs)
        assertNull(closed.mainGapAt(26_000_000))
    }

    @Test fun mainClipsMoveFreely() {
        var p = base()
        val last = p.mainTrack.clips[2].id
        p = p.moveClip(last, p.mainTrack.id, 30_000_000)
        assertEquals(30_000_000L, p.clip(last)!!.startUs)
        assertEquals(40_000_000L, p.durationUs)
        // Dropped onto the first clip's first half: inserted before it, later clips pushed only as needed.
        val photoId = p.mainTrack.clips[1].id
        p = p.moveClip(photoId, p.mainTrack.id, 2_000_000)
        assertEquals(listOf(photoId), p.mainTrack.clips.take(1).map { it.id })
        assertEquals(3_000_000L, p.mainTrack.clips[1].startUs)
        assertEquals(30_000_000L, p.clip(last)!!.startUs) // far enough away: not moved
    }

    @Test fun draggingAMainClipAboveAProjectWithOnlyTheMainTrackCreatesAnOverlay() {
        val p = base()
        assertEquals(listOf(TrackKind.MAIN), p.tracks.filter { it.kind != TrackKind.TEXT && it.kind != TrackKind.AUDIO }.map { it.kind })
        val id = p.mainTrack.clips[1].id
        val moved = p.moveClip(id, p.mainTrack.id, 4_000_000, newTrack = true)
        val overlay = moved.tracks.single { it.kind == TrackKind.OVERLAY }
        assertEquals(listOf(id), overlay.clips.map { it.id })
        assertEquals(4_000_000L, overlay.clips.single().startUs)
        assertTrue(moved.mainTrack.clips.none { it.id == id })
        assertTrue(moved.tracks.indexOfFirst { it.kind == TrackKind.OVERLAY } < moved.tracks.indexOfFirst { it.kind == TrackKind.MAIN })
    }

    @Test fun insertingPushesOnlyAsFarAsNeeded() {
        var p = base()
        val last = p.mainTrack.clips[2].id
        p = p.moveClip(last, p.mainTrack.id, 20_000_000) // 7 s gap after the photo
        p = p.addToMainAt(listOf(photo.copy(id = "p2")), 14_000_000) // in the gap: placed at the playhead
        val added = p.mainTrack.clips.first { it.assetId == "p2" }
        assertEquals(14_000_000L, added.startUs)
        assertEquals(20_000_000L, p.clip(last)!!.startUs)
        p = p.addToMainAt(listOf(photo.copy(id = "p3")), 18_000_000) // 2 s left before the last clip: pushed by 1 s
        assertEquals(18_000_000L, p.mainTrack.clips.first { it.assetId == "p3" }.startUs)
        assertEquals(21_000_000L, p.clip(last)!!.startUs)
        p = p.addToMainAt(listOf(video.copy(id = "v3")), 99_000_000) // past the end: appended
        assertEquals(31_000_000L, p.mainTrack.clips.last().startUs)
    }

    @Test fun transitionsNeedTouchingClips() {
        var p = base()
        val second = p.mainTrack.clips[1].id
        p = p.trimStart(second, 1_000_000) // gap before the photo
        p = p.setTransition(second, Transition(TransitionType.FADE, 500_000))
        assertNull(p.clip(second)!!.transitionIn)
        // Trimming into a transition shortens it to the overlap that is left.
        var q = base()
        val (first, photoId) = q.mainTrack.clips.let { it[0].id to it[1].id }
        q = q.setTransition(photoId, Transition(TransitionType.FADE, 1_000_000))
        assertEquals(9_000_000L, q.clip(photoId)!!.startUs)
        q = q.trimEnd(first, -400_000)
        assertEquals(600_000L, q.clip(photoId)!!.transitionIn!!.durationUs)
        assertEquals(9_000_000L, q.clip(photoId)!!.startUs)
        q = q.trimEnd(first, -600_000)
        assertNull(q.clip(photoId)!!.transitionIn)
        assertEquals(9_000_000L, q.clip(photoId)!!.startUs)
    }

    @Test fun mainLayersSplitOnlyAtTransitions() {
        var p = base()
        assertEquals(listOf(setOf(0, 1, 2)), com.framenova.app.engine.mainLayerGroups(p.mainTrack.clips))
        p = p.setTransition(p.mainTrack.clips[2].id, Transition(TransitionType.FADE, 500_000))
        val clips = p.mainTrack.clips
        assertEquals(listOf(setOf(0, 1), setOf(2)), com.framenova.app.engine.mainLayerGroups(clips))
        assertTrue(com.framenova.app.engine.onUpperMainLayer(clips, 1))
        assertTrue(!com.framenova.app.engine.onUpperMainLayer(clips, 2))
    }

    @Test fun otherTracksStopAtTheNextClip() {
        var p = base().addOverlayAt(photo, 0).addOverlayAt(video, 5_000_000)
        val track = p.tracks.first { it.kind == TrackKind.OVERLAY }
        assertEquals(2, track.clips.size)
        p = p.trimEnd(track.clips[0].id, 9_000_000)
        assertEquals(5_000_000L, p.clip(track.clips[0].id)!!.endUs)
        p = p.trimStart(track.clips[1].id, -9_000_000) // video at its source start: cannot extend
        assertEquals(5_000_000L, p.clip(track.clips[1].id)!!.startUs)
    }

    @Test fun overlaysUseFreeTracksOrNewOnes() {
        var p = base().addOverlayAt(video, 0)
        p = p.addOverlayAt(video2, 5_000_000) // overlaps the first overlay: new track
        assertEquals(2, p.tracks.count { it.kind == TrackKind.OVERLAY })
        p = p.addOverlayAt(photo, 15_000_000) // free on an existing track
        assertEquals(2, p.tracks.count { it.kind == TrackKind.OVERLAY })
        // Overlay tracks sit above the main track.
        assertTrue(p.tracks.indexOfFirst { it.kind == TrackKind.OVERLAY } < p.tracks.indexOfFirst { it.kind == TrackKind.MAIN })
    }

    @Test fun moveBetweenMainAndOverlay() {
        var p = base()
        val id = p.mainTrack.clips[1].id
        p = p.moveToOverlay(id)
        assertEquals(2, p.mainTrack.clips.size)
        assertEquals(TrackKind.OVERLAY, p.trackOf(id)!!.kind)
        p = p.moveToMain(id)
        assertEquals(3, p.mainTrack.clips.size)
        assertTrue(p.tracks.none { it.kind == TrackKind.OVERLAY })
    }

    @Test fun toNewLayerPreservesNonMainClipAndNeverReusesAFreeTrack() {
        for (kind in listOf(TrackKind.OVERLAY, TrackKind.TEXT, TrackKind.AUDIO)) {
            val clip = Clip("moving", assetId = if (kind == TrackKind.TEXT) null else if (kind == TrackKind.AUDIO) song.id else video.id,
                startUs = 2_000_000, srcInUs = 1_000_000, srcOutUs = 5_000_000, speed = 2f, volume = 0.4f,
                fadeInUs = 200_000, fadeOutUs = 300_000, transform = Transform(scale = 0.7f),
                text = if (kind == TrackKind.TEXT) TextStyle() else null)
            val sibling = clip.copy(id = "sibling", startUs = 10_000_000)
            val source = Track("source", kind, listOf(clip, sibling))
            val free = Track("free", kind, listOf(clip.copy(id = "other", startUs = 20_000_000)))
            val main = Track("main", TrackKind.MAIN)
            val p = Project("id", "New layer", 0, 0, assets = listOf(video, song),
                tracks = if (kind == TrackKind.AUDIO) listOf(main, source, free) else listOf(free, source, main))
            val moved = p.moveToNewLayer(clip.id)
            assertEquals(clip, moved.clip(clip.id))
            assertEquals(kind, moved.trackOf(clip.id)!!.kind)
            assertTrue(moved.trackOf(clip.id)!!.id !in listOf(source.id, free.id))
            assertEquals(listOf(sibling), moved.track(source.id)!!.clips)
            assertEquals(free, moved.track(free.id))
            assertEquals(moved.tracks.indexOfFirst { it.id == source.id } + if (kind == TrackKind.AUDIO) 1 else -1,
                moved.tracks.indexOfFirst { it.id == moved.trackOf(clip.id)!!.id })
            val locked = p.updateTrack(source.id) { it.copy(locked = true) }
            assertEquals(locked, locked.moveToNewLayer(clip.id))
        }
    }

    @Test fun mainToNewLayerCreatesFreshOverlayEvenWhenAnotherOverlayIsFree() {
        val p = base().addOverlayAt(photo, 40_000_000)
        val id = p.mainTrack.clips.first().id
        val existing = p.tracks.first { it.kind == TrackKind.OVERLAY }
        val moved = p.moveToNewLayer(id)
        assertTrue(moved.trackOf(id)!!.id != existing.id)
        assertEquals(existing, moved.track(existing.id))
        assertEquals(p.clip(id)!!.transform.scale * 0.6f, moved.clip(id)!!.transform.scale, 0.0001f)
    }

    @Test fun moveRejectsIncompatibleTracks() {
        var p = base().addAudioAt(song, 0)
        val audioId = p.tracks.first { it.kind == TrackKind.AUDIO }.clips.first().id
        val moved = p.moveClip(audioId, p.mainTrack.id, 0)
        assertEquals(p, moved)
    }

    @Test fun extractAudioMutesSourceAndAddsLinkedClip() {
        val p = base()
        val id = p.mainTrack.clips[0].id
        val (q, audioId) = p.extractAudio(id)
        assertEquals(0f, q.clip(id)!!.volume)
        val audio = q.clip(audioId!!)!!
        assertTrue(audio.audioOnly)
        assertEquals(TrackKind.AUDIO, q.trackOf(audioId)!!.kind)
        assertEquals(q.clip(id)!!.startUs, audio.startUs)
    }

    @Test fun keyframesInterpolate() {
        var p = base()
        val id = p.mainTrack.clips[0].id
        p = p.toggleKeyframe(id, 0, 33_333)
        p = p.updateClip(id) { it.withTransformAt(4_000_000, Transform(cx = 1f), 33_333) }
        val c = p.clip(id)!!
        assertEquals(2, c.keyframes.size)
        assertEquals(0.75f, c.transformAt(2_000_000).cx, 0.01f)
        assertEquals(1f, c.transformAt(9_000_000).cx, 0.001f)
        // Toggling at an existing keyframe removes it.
        p = p.toggleKeyframe(id, 4_000_000, 33_333)
        assertEquals(1, p.clip(id)!!.keyframes.size)
    }

    @Test fun freezeFrameSplitsAndInserts() {
        val p = base()
        val id = p.mainTrack.clips[0].id
        val q = p.insertFreezeFrame(id, 5_000_000, photo.copy(id = "still"))
        assertEquals(5, q.mainTrack.clips.size) // first half, still, second half, photo, video
        assertEquals("still", q.mainTrack.clips[1].assetId)
        assertEquals(p.durationUs + 2_000_000, q.durationUs)
    }

    @Test fun subtitleCuesBecomeOneTextTrack() {
        val cues = listOf(Cue(0, 2_000_000, "one"), Cue(1_500_000, 4_000_000, "two"))
        val p = base().addTextCues(cues, TextStyle(role = TextRole.SUBTITLE))
        val track = p.tracks.first { it.kind == TrackKind.TEXT }
        assertEquals(2, track.clips.size)
        assertEquals(2_000_000L, track.clips[1].startUs) // overlaps are pushed back
    }

    @Test fun projectJsonRoundTrips() {
        val p = base().addTextAt(TextStyle(text = "繁體字"), 0).setTransition("x", null)
        val text = ProjectRepository.json.encodeToString(Project.serializer(), p)
        assertEquals(p, ProjectRepository.json.decodeFromString(Project.serializer(), text))
    }

    @Test fun layoutFillsCells() {
        val canvas = PixelSize(3840, 2160)
        val (t, crop) = fillCell(Cell(0f, 0f, 0.5f, 1f), 3840, 2160, canvas)
        // Half-width cell of a 16:9 canvas is 8:9: crop the sides of the 16:9 source.
        assertEquals(0.25f, crop.left, 0.001f)
        assertEquals(0.25f, t.cx, 0.001f)
        assertEquals(1f, t.scale, 0.001f)
    }

    @Test fun canvasSizesAreEvenAndFit() {
        assertEquals(PixelSize(3840, 2160), CanvasSettings.sizeFor(AspectPreset.R16_9, 3840))
        assertEquals(PixelSize(2160, 3840), CanvasSettings.sizeFor(AspectPreset.R9_16, 3840))
        assertEquals(PixelSize(2160, 2160), CanvasSettings.sizeFor(AspectPreset.R1_1, 3840))
        val wide = CanvasSettings.sizeFor(AspectPreset.R21_9, 3840)
        assertEquals(3840, wide.width)
        assertEquals(0, wide.height % 2)
    }
}
