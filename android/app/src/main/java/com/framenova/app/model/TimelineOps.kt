package com.framenova.app.model

import java.util.UUID
import kotlin.math.max
import kotlin.math.min

const val MIN_CLIP_US = 100_000L
const val DEFAULT_STILL_US = 3_000_000L
private const val MAX_STILL_US = 3_600_000_000L

fun newId(): String = UUID.randomUUID().toString().replace("-", "").take(12)

enum class ClipCategory { VISUAL, TEXT, AUDIO }

fun Project.categoryOf(clip: Clip): ClipCategory = when {
    clip.isText -> ClipCategory.TEXT
    clip.audioOnly -> ClipCategory.AUDIO
    asset(clip.assetId)?.type == MediaType.AUDIO -> ClipCategory.AUDIO
    else -> ClipCategory.VISUAL
}

fun TrackKind.accepts(category: ClipCategory): Boolean = when (this) {
    TrackKind.MAIN, TrackKind.OVERLAY -> category == ClipCategory.VISUAL
    TrackKind.TEXT -> category == ClipCategory.TEXT
    TrackKind.AUDIO -> category == ClipCategory.AUDIO
}

/** Whether the source range of [clip] has a hard limit (video/audio) or can stretch freely (stills, text). */
fun Project.isStretchable(clip: Clip): Boolean = clip.isText || asset(clip.assetId)?.type == MediaType.IMAGE

// ---------------------------------------------------------------------------------------------------------------
// Normalization

/** Clips this close count as touching (timeline positions come from snapping, so this only absorbs rounding). */
const val TOUCH_US = 2_000L

/** Whether [clip] starts where [prev] ends (or overlaps it through a transition), so a transition can join them. */
fun touches(prev: Clip, clip: Clip): Boolean = clip.startUs <= prev.endUs + TOUCH_US

/**
 * Keeps clips where they are, with gaps allowed. Main-track clips never overlap except through a transition, and a
 * transition exists only between touching clips: the incoming clip overlaps the previous one by its duration. A clip
 * that would overlap the previous one is pushed later. Empty secondary tracks are dropped.
 */
fun Project.normalized(): Project {
    val main = mainTrack
    val laid = ArrayList<Clip>(main.clips.size)
    for (c in main.clips.sortedBy { it.startUs }) {
        var clip = c.copy(startUs = max(0L, c.startUs))
        val prev = laid.lastOrNull()
        val tr = clip.transitionIn
        if (prev == null) {
            clip = clip.copy(transitionIn = null)
        } else if (tr != null) {
            val maxD = min(prev.durationUs, clip.durationUs) / 2
            clip = if (maxD < MIN_CLIP_US || !touches(prev, clip)) clip.copy(transitionIn = null)
            else {
                val d = tr.durationUs.coerceIn(MIN_CLIP_US, maxD)
                clip.copy(transitionIn = tr.copy(durationUs = d), startUs = prev.endUs - d)
            }
        }
        if (prev != null && clip.transitionIn == null && clip.startUs < prev.endUs) clip = clip.copy(startUs = prev.endUs)
        laid += clip
    }
    val tracks = tracks.mapNotNull { t ->
        when {
            t.kind == TrackKind.MAIN -> t.copy(clips = laid)
            t.clips.isEmpty() -> null
            else -> t.copy(clips = t.clips.sortedBy { it.startUs })
        }
    }
    return copy(tracks = tracks)
}

private fun Project.mapTrack(trackId: String, f: (Track) -> Track): Project =
    copy(tracks = tracks.map { if (it.id == trackId) f(it) else it })

fun Project.updateClip(clipId: String, f: (Clip) -> Clip): Project =
    copy(tracks = tracks.map { t -> if (t.clips.none { it.id == clipId }) t else t.copy(clips = t.clips.map { if (it.id == clipId) f(it) else it }) })
        .normalized()

fun Project.updateTrack(trackId: String, f: (Track) -> Track): Project = mapTrack(trackId, f)

// ---------------------------------------------------------------------------------------------------------------
// Track placement

private fun Track.isFree(startUs: Long, endUs: Long, ignoreClipId: String? = null): Boolean =
    !locked && clips.none { it.id != ignoreClipId && it.startUs < endUs && startUs < it.endUs }

/** Inserts a new empty track of [kind] in its visual group and returns the project and the track id. */
fun Project.withNewTrack(kind: TrackKind, nearTrackId: String? = null): Pair<Project, String> {
    require(kind != TrackKind.MAIN)
    val track = Track(id = newId(), kind = kind)
    val list = tracks.toMutableList()
    val near = nearTrackId?.let { id -> list.indexOfFirst { it.id == id } }?.takeIf { it >= 0 && list[it].kind == kind }
    val index = when {
        near != null -> if (kind == TrackKind.AUDIO) near + 1 else near
        kind == TrackKind.TEXT -> 0
        kind == TrackKind.OVERLAY -> list.indexOfFirst { it.kind == TrackKind.OVERLAY }.takeIf { it >= 0 }
            ?: list.indexOfFirst { it.kind == TrackKind.MAIN }
        else -> list.size
    }
    list.add(index, track)
    return copy(tracks = list) to track.id
}

/** Places [clip] on a free track of [kind], creating one when every existing track is busy at that time. */
fun Project.placeOnFreeTrack(kind: TrackKind, clip: Clip, preferTrackId: String? = null): Project {
    val candidates = tracks.filter { it.kind == kind }
    val preferred = candidates.firstOrNull { it.id == preferTrackId }?.takeIf { it.isFree(clip.startUs, clip.endUs, clip.id) }
    // Overlays: prefer the lowest free track (closest to the main track); text: the top-most free one.
    val ordered = if (kind == TrackKind.OVERLAY || kind == TrackKind.AUDIO) candidates.reversed() else candidates
    val free = preferred ?: (if (kind == TrackKind.AUDIO) candidates else ordered).firstOrNull { it.isFree(clip.startUs, clip.endUs, clip.id) }
    val (project, trackId) = if (free != null) this to free.id else withNewTrack(kind, preferTrackId)
    return project.mapTrack(trackId) { t -> t.copy(clips = (t.clips + clip).sortedBy { it.startUs }) }.normalized()
}

// ---------------------------------------------------------------------------------------------------------------
// Adding

fun Project.withAssets(newAssets: List<MediaAsset>): Project =
    copy(assets = assets + newAssets.filter { a -> assets.none { it.id == a.id } })

fun clipForAsset(asset: MediaAsset, startUs: Long, audioOnly: Boolean = false): Clip = when (asset.type) {
    MediaType.IMAGE -> Clip(id = newId(), assetId = asset.id, startUs = startUs, srcInUs = 0, srcOutUs = DEFAULT_STILL_US)
    else -> Clip(id = newId(), assetId = asset.id, startUs = startUs, srcInUs = 0, srcOutUs = max(MIN_CLIP_US, asset.durationUs), audioOnly = audioOnly)
}

/**
 * Where on the main track new clips go for [timeUs]: the nearer edge of the clip under it, the time itself in a gap,
 * or the end of the track after the last clip.
 */
fun Project.mainInsertTime(timeUs: Long): Long {
    val clips = mainTrack.clips
    val end = clips.lastOrNull()?.endUs ?: 0L
    if (timeUs >= end) return end
    val c = clips.lastOrNull { it.contains(timeUs) } ?: return max(0L, timeUs)
    return if (timeUs < c.startUs + c.durationUs / 2) c.startUs else c.endUs
}

/**
 * Inserts [clips] end to end at [atUs] on the main track. Later clips move right only as far as needed to make room,
 * keeping their gaps; the clip right after the insertion loses its transition.
 */
fun Project.insertMainAt(clips: List<Clip>, atUs: Long): Project {
    if (clips.isEmpty()) return this
    val main = mainTrack
    val at = max(0L, atUs)
    // A clip counts as later when its visible cut (after its transition) is at or after the insertion point.
    val (before, after) = main.clips.partition { it.startUs + (it.transitionIn?.durationUs ?: 0L) < at }
    var cursor = at
    val inserted = clips.map { c -> c.copy(startUs = cursor, transitionIn = null).also { cursor += it.durationUs } }
    // Only the first later clip is placed here; normalizing pushes the rest along only where they would overlap.
    val moved = after.mapIndexed { i, c -> if (i == 0) c.copy(startUs = max(c.startUs, cursor), transitionIn = null) else c }
    return mapTrack(main.id) { it.copy(clips = before + inserted + moved) }.normalized()
}

fun Project.addToMainAt(assetsToAdd: List<MediaAsset>, timeUs: Long): Project {
    val clips = assetsToAdd.filter { it.type != MediaType.AUDIO }.map { clipForAsset(it, 0) }
    return withAssets(assetsToAdd).insertMainAt(clips, mainInsertTime(timeUs))
}

/** The empty stretch of the main track around [timeUs] (between two clips, or before the first), or null. */
fun Project.mainGapAt(timeUs: Long): LongRange? {
    val clips = mainTrack.clips
    if (clips.any { it.contains(timeUs) }) return null
    val prevEnd = clips.filter { it.endUs <= timeUs }.maxOfOrNull { it.endUs } ?: 0L
    val next = clips.firstOrNull { it.startUs > timeUs } ?: return null
    return if (next.startUs - prevEnd >= TOUCH_US) prevEnd until next.startUs else null
}

/** Removes the main-track gap around [timeUs]: the clips after it move left. */
fun Project.deleteMainGap(timeUs: Long): Project {
    val gap = mainGapAt(timeUs) ?: return this
    val len = gap.last + 1 - gap.first
    return mapTrack(mainTrack.id) { t -> t.copy(clips = t.clips.map { if (it.startUs >= gap.last) it.copy(startUs = it.startUs - len) else it }) }.normalized()
}

fun Project.addOverlayAt(asset: MediaAsset, timeUs: Long): Project {
    val clip = clipForAsset(asset, timeUs).copy(transform = Transform(cx = 0.5f, cy = 0.5f, scale = 0.5f))
    return withAssets(listOf(asset)).placeOnFreeTrack(TrackKind.OVERLAY, clip)
}

fun Project.addAudioAt(asset: MediaAsset, timeUs: Long, audioOnly: Boolean = asset.type != MediaType.AUDIO): Project =
    withAssets(listOf(asset)).placeOnFreeTrack(TrackKind.AUDIO, clipForAsset(asset, timeUs, audioOnly))

fun Project.addTextAt(style: TextStyle, timeUs: Long, durationUs: Long = DEFAULT_STILL_US, transform: Transform? = null): Project {
    val t = transform ?: when (style.role) {
        TextRole.SUBTITLE -> Transform(cx = 0.5f, cy = 0.86f)
        else -> Transform()
    }
    val clip = Clip(id = newId(), startUs = timeUs, srcInUs = 0, srcOutUs = durationUs, text = style, transform = t)
    return placeOnFreeTrack(TrackKind.TEXT, clip)
}

/** Adds several timed text clips (subtitles or lyrics) on one new text track. */
fun Project.addTextCues(cues: List<Triple<Long, Long, String>>, style: TextStyle): Project {
    if (cues.isEmpty()) return this
    val (p, trackId) = withNewTrack(TrackKind.TEXT)
    val clips = cues.sortedBy { it.first }.fold(mutableListOf<Clip>()) { acc, (start, end, text) ->
        val s = max(start, acc.lastOrNull()?.endUs ?: 0L)
        if (end - s >= MIN_CLIP_US) acc += Clip(
            id = newId(), startUs = s, srcInUs = 0, srcOutUs = end - s,
            text = style.copy(text = text), transform = Transform(cx = 0.5f, cy = 0.86f),
        )
        acc
    }
    return p.mapTrack(trackId) { it.copy(clips = clips) }.normalized()
}

// ---------------------------------------------------------------------------------------------------------------
// Editing

fun Project.deleteClip(clipId: String): Project =
    copy(tracks = tracks.map { t -> t.copy(clips = t.clips.filterNot { it.id == clipId }) }).normalized()

fun Project.splitClip(clipId: String, atUs: Long): Pair<Project, String?> {
    val clip = clip(clipId) ?: return this to null
    if (atUs - clip.startUs < MIN_CLIP_US || clip.endUs - atUs < MIN_CLIP_US) return this to null
    val track = trackOf(clipId) ?: return this to null
    val cutSrc = clip.sourceTimeAt(atUs)
    val splitOffset = atUs - clip.startUs
    val (kfA, kfB) = splitKeyframes(clip, splitOffset)
    val first = clip.copy(srcOutUs = cutSrc, fadeOutUs = 0, keyframes = kfA)
    val second = clip.copy(
        id = newId(), startUs = atUs, srcInUs = cutSrc, transitionIn = null, fadeInUs = 0, keyframes = kfB,
    )
    val list = track.clips.toMutableList()
    val i = list.indexOfFirst { it.id == clipId }
    list[i] = first
    list.add(i + 1, second)
    return mapTrack(track.id) { it.copy(clips = list) }.normalized() to second.id
}

private fun splitKeyframes(clip: Clip, offset: Long): Pair<List<Keyframe>, List<Keyframe>> {
    if (clip.keyframes.isEmpty()) return emptyList<Keyframe>() to emptyList()
    val boundary = clip.transformAt(clip.startUs + offset)
    val a = clip.keyframes.filter { it.offsetUs < offset } + Keyframe(offset, boundary)
    val b = listOf(Keyframe(0, boundary)) + clip.keyframes.filter { it.offsetUs > offset }.map { it.copy(offsetUs = it.offsetUs - offset) }
    return a to b
}

fun Project.duplicateClip(clipId: String): Pair<Project, String?> {
    val clip = clip(clipId) ?: return this to null
    val track = trackOf(clipId) ?: return this to null
    val copy = clip.copy(id = newId(), transitionIn = null)
    return if (track.kind == TrackKind.MAIN) {
        insertMainAt(listOf(copy), clip.endUs) to copy.id
    } else {
        placeOnFreeTrack(track.kind, copy.copy(startUs = clip.endUs), track.id) to copy.id
    }
}

private fun Track.neighbours(clipId: String): Pair<Clip?, Clip?> {
    val i = clips.indexOfFirst { it.id == clipId }
    return clips.getOrNull(i - 1) to clips.getOrNull(i + 1)
}

/** A transition shortened to the clips' remaining overlap, or none when they no longer overlap enough. */
private fun Transition.withOverlap(overlapUs: Long): Transition? = if (overlapUs >= MIN_CLIP_US) copy(durationUs = min(durationUs, overlapUs)) else null

/**
 * Trims the clip's start by [deltaUs] of timeline time (positive trims in). The clip's end stays where it is, so trimming
 * in leaves a gap before it; extending stops at the previous clip.
 */
fun Project.trimStart(clipId: String, deltaUs: Long): Project {
    val clip = clip(clipId) ?: return this
    val track = trackOf(clipId) ?: return this
    val (prev, _) = track.neighbours(clipId)
    val stretch = isStretchable(clip)
    val maxIn = clip.durationUs - MIN_CLIP_US
    // Extending: back to the previous clip (a clip joined by a transition does not extend), the source start, or 0.
    val limit = when {
        clip.transitionIn != null -> clip.startUs
        else -> clip.startUs - (prev?.endUs ?: 0L)
    }
    val minIn = -min(limit, if (stretch) MAX_STILL_US else (clip.srcInUs / clip.speed).toLong())
    val d = deltaUs.coerceIn(min(0L, minIn), max(0L, maxIn))
    if (d == 0L) return this
    val srcDelta = (d * clip.speed).toLong()
    val shifted = clip.keyframes.map { it.copy(offsetUs = it.offsetUs - d) }.filter { it.offsetUs >= 0 }
    // Keep the evaluated pose when trimming between keys or past the final key.
    val keyframes = if (d > 0 && clip.keyframes.isNotEmpty() && shifted.none { it.offsetUs == 0L }) {
        listOf(Keyframe(0, clip.transformAt(clip.startUs + d))) + shifted
    } else shifted
    val start = clip.startUs + d
    val updated = if (stretch) clip.copy(srcInUs = 0, srcOutUs = clip.srcOutUs - clip.srcInUs - srcDelta, keyframes = keyframes)
    else clip.copy(srcInUs = clip.srcInUs + srcDelta, keyframes = keyframes)
    val transition = clip.transitionIn?.let { tr -> prev?.let { tr.withOverlap(it.endUs - start) } }
    return updateClip(clipId) { updated.copy(startUs = start, transitionIn = transition) }
}

/**
 * Moves the clip's end by [deltaUs] of timeline time (positive extends). Trimming in leaves a gap after the clip. On the
 * main track, extending pushes later clips only as far as needed; on other tracks it stops at the next clip.
 */
fun Project.trimEnd(clipId: String, deltaUs: Long): Project {
    val clip = clip(clipId) ?: return this
    val track = trackOf(clipId) ?: return this
    val (_, next) = track.neighbours(clipId)
    val asset = asset(clip.assetId)
    val stretch = isStretchable(clip)
    var delta = deltaUs
    if (track.kind != TrackKind.MAIN && next != null) delta = min(delta, max(0L, next.startUs - clip.endUs))
    val maxOut = if (stretch) MAX_STILL_US else asset?.durationUs ?: clip.srcOutUs
    val newOut = (clip.srcOutUs + (delta * clip.speed).toLong()).coerceIn(clip.srcInUs + (MIN_CLIP_US * clip.speed).toLong(), max(clip.srcOutUs, maxOut))
    if (newOut == clip.srcOutUs) return this
    val trimmed = clip.copy(srcOutUs = newOut)
    var p = copy(tracks = tracks.map { t -> if (t.id != track.id) t else t.copy(clips = t.clips.map { if (it.id == clipId) trimmed else it }) })
    // The next clip's transition shrinks with the overlap that is left.
    if (next?.transitionIn != null && trimmed.endUs < clip.endUs) {
        val tr = next.transitionIn.withOverlap(trimmed.endUs - next.startUs)
        p = p.copy(tracks = p.tracks.map { t -> if (t.id != track.id) t else t.copy(clips = t.clips.map { if (it.id == next.id) it.copy(transitionIn = tr) else it }) })
    }
    return p.normalized()
}

fun Project.setSpeed(clipId: String, speed: Float): Project = updateClip(clipId) { c ->
    val s = speed.coerceIn(0.1f, 10f)
    val ratio = c.speed / s
    c.copy(speed = s, keyframes = c.keyframes.map { it.copy(offsetUs = (it.offsetUs * ratio).toLong()) })
}

/**
 * Moves a clip to [targetTrackId] (or a new track of the source kind above it when [newTrack] is set) at [startUs].
 * On the main track the clip lands exactly there when the space is free (gaps are kept); dropped onto another clip, it
 * is inserted at that clip's nearer edge and later clips move right only as far as needed.
 */
fun Project.moveClip(clipId: String, targetTrackId: String, startUs: Long, newTrack: Boolean = false): Project {
    val clip = clip(clipId) ?: return this
    val from = trackOf(clipId) ?: return this
    val target = track(targetTrackId) ?: return this
    val category = categoryOf(clip)
    if (!target.kind.accepts(category)) return this
    val removed = copy(tracks = tracks.map { t -> t.copy(clips = t.clips.filterNot { it.id == clipId }) })
    val start = max(0L, startUs)
    return when {
        target.kind == TrackKind.MAIN -> {
            val fromMain = from.kind == TrackKind.MAIN
            val moved = clip.copy(
                startUs = start,
                transitionIn = null,
                transform = if (fromMain) clip.transform else Transform(),
                keyframes = if (fromMain) clip.keyframes else emptyList(),
            )
            val main = removed.mainTrack
            if (main.isFree(start, start + clip.durationUs)) removed.mapTrack(main.id) { it.copy(clips = it.clips + moved) }.normalized()
            else {
                val under = main.clips.lastOrNull { it.contains(start) }
                val at = if (under == null) start else if (start < under.startUs + under.durationUs / 2) under.startUs else under.endUs
                removed.insertMainAt(listOf(moved), at)
            }
        }
        newTrack -> {
            val (p, id) = removed.withNewTrack(target.kind, target.id)
            p.mapTrack(id) { it.copy(clips = listOf(clip.copy(startUs = start, transitionIn = null))) }.normalized()
        }
        else -> {
            val moved = clip.copy(startUs = start, transitionIn = null)
            val t = removed.track(target.id)!!
            if (t.isFree(moved.startUs, moved.endUs)) removed.mapTrack(t.id) { it.copy(clips = (it.clips + moved).sortedBy { c -> c.startUs }) }.normalized()
            else removed.placeOnFreeTrack(target.kind, moved, t.id)
        }
    }
}

fun Project.moveToOverlay(clipId: String): Project {
    if (trackOf(clipId)?.kind != TrackKind.MAIN) return this
    return moveToNewLayer(clipId)
}

/** Creates a fresh compatible track rather than reusing a free track. */
fun Project.moveToNewLayer(clipId: String): Project {
    val clip = clip(clipId) ?: return this
    val source = trackOf(clipId)?.takeUnless { it.locked } ?: return this
    val kind = when (categoryOf(clip)) {
        ClipCategory.VISUAL -> TrackKind.OVERLAY
        ClipCategory.TEXT -> TrackKind.TEXT
        ClipCategory.AUDIO -> TrackKind.AUDIO
    }
    val moved = clip.copy(transitionIn = null, transform = if (source.kind == TrackKind.MAIN)
        clip.transform.copy(scale = clip.transform.scale * 0.6f) else clip.transform)
    val removed = copy(tracks = tracks.map { it.copy(clips = it.clips.filterNot { c -> c.id == clipId }) })
    val (project, id) = removed.withNewTrack(kind, source.id)
    return project.mapTrack(id) { it.copy(clips = listOf(moved)) }.normalized()
}

fun Project.moveToMain(clipId: String): Project {
    val clip = clip(clipId) ?: return this
    if (trackOf(clipId)?.kind != TrackKind.OVERLAY) return this
    return moveClip(clipId, mainTrack.id, clip.startUs)
}

/**
 * Sets the transition into a main-track clip. The clip moves to overlap the previous one by the transition (or back
 * when it is removed), and the clips after it move with it so their spacing is kept.
 */
fun Project.setTransition(clipId: String, transition: Transition?): Project {
    val before = clip(clipId) ?: return this
    if (trackOf(clipId)?.kind != TrackKind.MAIN) return this
    val changed = updateClip(clipId) { it.copy(transitionIn = transition) }
    val delta = (changed.clip(clipId)?.startUs ?: return changed) - before.startUs
    if (delta == 0L) return changed
    val main = changed.mainTrack
    val i = main.clips.indexOfFirst { it.id == clipId }
    val shifted = main.clips.mapIndexed { k, c -> if (k > i) c.copy(startUs = c.startUs + delta) else c }
    return changed.mapTrack(main.id) { it.copy(clips = shifted) }.normalized()
}

/** Copies the audio of a video clip to an audio track and silences the original. */
fun Project.extractAudio(clipId: String): Pair<Project, String?> {
    val clip = clip(clipId) ?: return this to null
    val asset = asset(clip.assetId) ?: return this to null
    if (!asset.hasAudio || clip.audioOnly) return this to null
    val audio = clip.copy(
        id = newId(), audioOnly = true, transitionIn = null, keyframes = emptyList(), transform = Transform(),
        crop = CropRect(), adjust = Adjust(), filter = null,
    )
    val p = updateClip(clipId) { it.copy(volume = 0f) }.placeOnFreeTrack(TrackKind.AUDIO, audio)
    return p to audio.id
}

/** Splits the main clip under [atUs] and inserts a still of [stillAsset] there. */
fun Project.insertFreezeFrame(clipId: String, atUs: Long, stillAsset: MediaAsset, durationUs: Long = 2_000_000): Project {
    val source = clip(clipId) ?: return this
    val track = trackOf(clipId) ?: return this
    val still = Clip(
        id = newId(), assetId = stillAsset.id, startUs = atUs, srcInUs = 0, srcOutUs = durationUs,
        transform = source.transformAt(atUs), crop = source.crop, flipH = source.flipH, flipV = source.flipV,
        adjust = source.adjust, filter = source.filter,
    )
    val withAsset = withAssets(listOf(stillAsset))
    if (track.kind != TrackKind.MAIN) return withAsset.placeOnFreeTrack(track.kind, still, track.id)
    val (split, secondId) = withAsset.splitClip(clipId, atUs)
    val at = if (secondId != null) atUs else split.clip(clipId)?.endUs ?: atUs
    return split.insertMainAt(listOf(still.copy(startUs = at)), at)
}

/** Adds or removes a keyframe at [atUs]; returns the project unchanged when [atUs] is outside the clip. */
fun Project.toggleKeyframe(clipId: String, atUs: Long, frameUs: Long): Project = updateClip(clipId) { c ->
    if (!c.contains(atUs) && atUs != c.endUs) return@updateClip c
    val offset = atUs - c.startUs
    val existing = c.keyframes.firstOrNull { kotlin.math.abs(it.offsetUs - offset) <= frameUs / 2 }
    if (existing != null) c.copy(keyframes = c.keyframes - existing)
    else {
        val base = if (c.keyframes.isEmpty()) listOf(Keyframe(offset, c.transform)) else c.keyframes + Keyframe(offset, c.transformAt(atUs))
        c.copy(keyframes = base.sortedBy { it.offsetUs })
    }
}

/** Sets the transform at [atUs]: updates (or adds) the keyframe there when the clip is keyframed, else the base transform. */
fun Clip.withTransformAt(atUs: Long, t: Transform, frameUs: Long): Clip {
    if (keyframes.isEmpty()) return copy(transform = t)
    val offset = (atUs - startUs).coerceIn(0, durationUs)
    val existing = keyframes.firstOrNull { kotlin.math.abs(it.offsetUs - offset) <= frameUs / 2 }
    val list = if (existing != null) keyframes.map { if (it === existing) it.copy(transform = t) else it } else keyframes + Keyframe(offset, t)
    return copy(keyframes = list.sortedBy { it.offsetUs })
}

fun Project.clipsAt(timeUs: Long, kinds: Set<TrackKind>): List<Pair<Track, Clip>> =
    tracks.filter { it.kind in kinds }.mapNotNull { t -> t.clips.firstOrNull { it.contains(timeUs) }?.let { t to it } }

/** Keeps existing tracks aligned when a cover becomes an opening clip. */
fun Project.prependCover(): Project {
    val cover = asset(coverAssetId)?.takeIf { it.type == MediaType.IMAGE } ?: return this
    if (tracks.any { it.locked && (it.kind == TrackKind.MAIN || it.clips.isNotEmpty()) }) return this
    val duration = 3_000_000L
    val opening = Clip(id = newId(), assetId = cover.id, startUs = 0, srcOutUs = duration)
    return copy(tracks = tracks.map { track ->
        val shifted = track.clips.map { it.copy(startUs = it.startUs + duration) }
        track.copy(clips = if (track.kind == TrackKind.MAIN) listOf(opening) + shifted else shifted)
    })
}
