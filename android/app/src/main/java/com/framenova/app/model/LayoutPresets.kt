package com.framenova.app.model

import kotlin.math.min

/** A cell in canvas fractions. */
data class Cell(val x: Float, val y: Float, val w: Float, val h: Float)

data class LayoutPreset(val id: String, val label: String, val cells: List<Cell>)

object LayoutPresets {
    private fun grid(cols: Int, rows: Int): List<Cell> =
        (0 until rows).flatMap { r -> (0 until cols).map { c -> Cell(c.toFloat() / cols, r.toFloat() / rows, 1f / cols, 1f / rows) } }

    val all: List<LayoutPreset> = listOf(
        LayoutPreset("fit", "Fit", listOf(Cell(0f, 0f, 1f, 1f))),
        LayoutPreset("side2", "Side by side", grid(2, 1)),
        LayoutPreset("stack2", "Top / bottom", grid(1, 2)),
        LayoutPreset("pip_br", "PiP bottom right", listOf(Cell(0f, 0f, 1f, 1f), Cell(0.62f, 0.62f, 0.34f, 0.34f))),
        LayoutPreset("pip_tl", "PiP top left", listOf(Cell(0f, 0f, 1f, 1f), Cell(0.04f, 0.04f, 0.34f, 0.34f))),
        LayoutPreset("split64", "60 / 40", listOf(Cell(0f, 0f, 0.6f, 1f), Cell(0.6f, 0f, 0.4f, 1f))),
        LayoutPreset("cols3", "3 columns", grid(3, 1)),
        LayoutPreset("rows3", "3 rows", grid(1, 3)),
        LayoutPreset("big_left3", "1 + 2", listOf(Cell(0f, 0f, 0.6f, 1f), Cell(0.6f, 0f, 0.4f, 0.5f), Cell(0.6f, 0.5f, 0.4f, 0.5f))),
        LayoutPreset("big_top3", "1 over 2", listOf(Cell(0f, 0f, 1f, 0.6f), Cell(0f, 0.6f, 0.5f, 0.4f), Cell(0.5f, 0.6f, 0.5f, 0.4f))),
        LayoutPreset("grid4", "2 × 2", grid(2, 2)),
        LayoutPreset("big_strip4", "1 + 3", listOf(Cell(0f, 0f, 1f, 0.7f), Cell(0f, 0.7f, 1f / 3, 0.3f), Cell(1f / 3, 0.7f, 1f / 3, 0.3f), Cell(2f / 3, 0.7f, 1f / 3, 0.3f))),
        LayoutPreset("grid6", "3 × 2", grid(3, 2)),
    )

    fun forCount(n: Int): List<LayoutPreset> = all.filter { it.cells.size == n || (n >= 2 && it.id.startsWith("pip") && n == 2) || it.id == "fit" }
}

/**
 * Fills [cell] with a clip whose display size is [srcW]×[srcH]: crops the source to the cell's aspect ratio (centered)
 * and sizes it to the cell. [gap] shrinks the cell on each side (canvas fraction of the shorter side).
 */
fun fillCell(cell: Cell, srcW: Int, srcH: Int, canvas: PixelSize, gap: Float = 0f): Pair<Transform, CropRect> {
    val g = gap * min(canvas.width, canvas.height)
    val cellW = (cell.w * canvas.width - 2 * g).coerceAtLeast(2f)
    val cellH = (cell.h * canvas.height - 2 * g).coerceAtLeast(2f)
    val cellAspect = cellW / cellH
    val srcAspect = srcW.toFloat() / srcH
    val crop = if (srcAspect > cellAspect) {
        val keep = cellAspect / srcAspect
        CropRect(left = (1 - keep) / 2, right = (1 - keep) / 2)
    } else {
        val keep = srcAspect / cellAspect
        CropRect(top = (1 - keep) / 2, bottom = (1 - keep) / 2)
    }
    // Scale 1 = the cropped frame fits the canvas; find the scale that makes it exactly cellW wide.
    val fitW = min(canvas.width.toFloat(), canvas.height * cellAspect)
    val transform = Transform(
        cx = cell.x + cell.w / 2,
        cy = cell.y + cell.h / 2,
        scale = cellW / fitW,
    )
    return transform to crop
}

/** Applies [preset] to the visual clips showing at [timeUs]: the main clip first, then overlays bottom to top. */
fun Project.applyLayout(preset: LayoutPreset, timeUs: Long, gap: Float): Project {
    val visible = clipsAt(timeUs, setOf(TrackKind.MAIN, TrackKind.OVERLAY))
        .sortedBy { (t, _) -> if (t.kind == TrackKind.MAIN) Int.MAX_VALUE else tracks.indexOf(t) }
        .reversed()
    if (visible.isEmpty()) return this
    val size = canvas.size
    var p = this
    visible.forEachIndexed { i, (_, clip) ->
        val asset = asset(clip.assetId) ?: return@forEachIndexed
        val cell = preset.cells[i % preset.cells.size]
        val (transform, crop) = if (preset.id == "fit") Transform() to CropRect() else fillCell(cell, asset.width, asset.height, size, gap)
        p = p.updateClip(clip.id) { it.copy(transform = transform.copy(rotation = 0f, opacity = it.transform.opacity), crop = crop, keyframes = emptyList()) }
    }
    return p
}
