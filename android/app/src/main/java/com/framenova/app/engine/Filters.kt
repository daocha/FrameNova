package com.framenova.app.engine

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** A color filter defined as a function on linear-ish RGB in 0..1, baked into a 3D LUT for the GPU. */
class FilterDef(val id: String, val name: String, val swatch: Long, val fn: (Float, Float, Float) -> FloatArray)

object Filters {
    private fun c(v: Float) = min(1f, max(0f, v))
    private fun luma(r: Float, g: Float, b: Float) = 0.2126f * r + 0.7152f * g + 0.0722f * b
    private fun sat(r: Float, g: Float, b: Float, s: Float): FloatArray {
        val l = luma(r, g, b)
        return floatArrayOf(l + (r - l) * s, l + (g - l) * s, l + (b - l) * s)
    }
    private fun contrast(v: Float, k: Float) = (v - 0.5f) * k + 0.5f
    private fun scurve(v: Float, k: Float): Float {
        val x = c(v)
        val s = x * x * (3 - 2 * x)
        return x + (s - x) * k
    }
    private fun lift(v: Float, black: Float, white: Float = 1f) = black + v * (white - black)
    private fun arr(r: Float, g: Float, b: Float) = floatArrayOf(r, g, b)

    val all: List<FilterDef> = listOf(
        FilterDef("vivid", "Vivid", 0xFFE8505B) { r, g, b ->
            val s = sat(r, g, b, 1.35f); arr(contrast(s[0], 1.08f), contrast(s[1], 1.08f), contrast(s[2], 1.08f))
        },
        FilterDef("warm", "Warm", 0xFFF2A65A) { r, g, b -> val s = sat(r * 1.07f + 0.02f, g * 1.01f, b * 0.88f, 1.08f); s },
        FilterDef("cool", "Cool", 0xFF4FA3E0) { r, g, b -> sat(r * 0.9f, g * 1.0f, b * 1.08f + 0.02f, 1.05f) },
        FilterDef("golden", "Golden", 0xFFE7B53C) { r, g, b ->
            val l = luma(r, g, b); arr(r * 1.08f + 0.04f * l, g * 1.03f + 0.02f * l, b * 0.82f)
        },
        FilterDef("teal_orange", "Teal & Orange", 0xFF2CA6A4) { r, g, b ->
            val l = luma(r, g, b) - 0.5f
            val s = sat(r + l * 0.16f, g + 0.01f, b - l * 0.18f, 1.12f)
            arr(scurve(s[0], 0.25f), scurve(s[1], 0.25f), scurve(s[2], 0.25f))
        },
        FilterDef("film", "Film", 0xFFB08D6E) { r, g, b ->
            val s = sat(r * 1.02f, g, b * 0.97f, 0.88f); arr(lift(scurve(s[0], 0.35f), 0.03f), lift(scurve(s[1], 0.35f), 0.03f), lift(scurve(s[2], 0.35f), 0.04f))
        },
        FilterDef("chrome", "Chrome", 0xFFC9463D) { r, g, b ->
            val s = sat(r, g, b, 1.22f); arr(contrast(s[0], 1.15f) + 0.01f, contrast(s[1], 1.15f), contrast(s[2], 1.15f) - 0.01f)
        },
        FilterDef("fade", "Fade", 0xFF9AA0A6) { r, g, b -> val s = sat(r, g, b, 0.8f); arr(lift(s[0], 0.08f, 0.96f), lift(s[1], 0.08f, 0.96f), lift(s[2], 0.09f, 0.96f)) },
        FilterDef("pastel", "Pastel", 0xFFF3B6C8) { r, g, b -> val s = sat(r, g, b, 0.7f); arr(lift(s[0], 0.08f) + 0.02f, lift(s[1], 0.08f) + 0.02f, lift(s[2], 0.1f) + 0.03f) },
        FilterDef("vintage", "Vintage", 0xFFA67C52) { r, g, b ->
            val l = luma(r, g, b)
            val sr = l * 1.07f + 0.05f; val sg = l * 0.92f + 0.03f; val sb = l * 0.72f + 0.02f
            arr(lift(r * 0.45f + sr * 0.55f, 0.05f, 0.95f), lift(g * 0.45f + sg * 0.55f, 0.05f, 0.95f), lift(b * 0.45f + sb * 0.55f, 0.07f, 0.92f))
        },
        FilterDef("forest", "Forest", 0xFF3E8E5A) { r, g, b -> sat(r * 0.94f, g * 1.06f + 0.01f, b * 0.95f, 1.1f) },
        FilterDef("rose", "Rose", 0xFFE48FA8) { r, g, b -> arr(r * 1.05f + 0.03f, g * 0.96f, b * 1.02f + 0.03f) },
        FilterDef("cyber", "Cyber", 0xFF7B5CFF) { r, g, b ->
            val l = luma(r, g, b) - 0.5f
            sat(r - l * 0.1f + 0.02f, g + l * 0.08f, b - l * 0.1f + 0.06f, 1.18f)
        },
        FilterDef("bleach", "Bleach", 0xFFB8B8B0) { r, g, b -> val s = sat(r, g, b, 0.55f); arr(contrast(s[0], 1.22f), contrast(s[1], 1.22f), contrast(s[2], 1.22f)) },
        FilterDef("mono", "Mono", 0xFF8E8E8E) { r, g, b -> val l = luma(r, g, b); arr(l, l, l) },
        FilterDef("noir", "Noir", 0xFF2B2B2B) { r, g, b -> val l = scurve(contrast(luma(r, g, b), 1.25f), 0.6f); arr(l, l, l) },
    )

    fun byId(id: String?): FilterDef? = all.firstOrNull { it.id == id }

    /** The filtered color of (r, g, b), blended with the original by [intensity]. */
    fun apply(def: FilterDef, r: Float, g: Float, b: Float, intensity: Float): FloatArray {
        val out = def.fn(r, g, b)
        val k = intensity.coerceIn(0f, 1f)
        return floatArrayOf(c(r + (out[0] - r) * k), c(g + (out[1] - g) * k), c(b + (out[2] - b) * k))
    }

    /** A LUT cube indexed [r][g][b] holding opaque ARGB colors. Inputs are treated as display (gamma) values. */
    fun cube(def: FilterDef, intensity: Float, size: Int = 33): Array<Array<IntArray>> = Array(size) { ri ->
        Array(size) { gi ->
            IntArray(size) { bi ->
                val r = ri / (size - 1f); val g = gi / (size - 1f); val b = bi / (size - 1f)
                val o = apply(def, r, g, b, intensity)
                (0xFF shl 24) or ((o[0] * 255f + 0.5f).toInt() shl 16) or ((o[1] * 255f + 0.5f).toInt() shl 8) or (o[2] * 255f + 0.5f).toInt()
            }
        }
    }

    /** Applies the filter to a packed ARGB color (used for UI previews). */
    fun applyArgb(def: FilterDef, argb: Int, intensity: Float = 1f): Int {
        val o = apply(def, (argb shr 16 and 0xFF) / 255f, (argb shr 8 and 0xFF) / 255f, (argb and 0xFF) / 255f, intensity)
        return (argb and 0xFF000000.toInt()) or ((o[0] * 255).toInt() shl 16) or ((o[1] * 255).toInt() shl 8) or (o[2] * 255).toInt()
    }

    @Suppress("unused")
    private fun gamma(v: Float, g: Float) = c(v).pow(g)
}
