package com.framenova.app.ui.editor

import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Tile indices intersecting the viewport, anchored to the clip's start. */
internal fun visibleTimelineTiles(start: Float, end: Float, tileWidth: Float, viewportWidth: Float): IntRange {
    if (tileWidth <= 0 || viewportWidth <= 0 || end <= 0 || start >= viewportWidth || end <= start) return IntRange.EMPTY
    val first = floor(max(0f, -start) / tileWidth).toInt()
    val last = ceil((min(end, viewportWidth).toDouble() - start) / tileWidth).toInt() - 1
    return first..last
}
