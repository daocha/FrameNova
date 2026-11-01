package com.framenova.app.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.framenova.app.model.TextAlign
import com.framenova.app.model.TextAnim
import com.framenova.app.model.TextStyle
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Renders text clips to bitmaps at output resolution, so text stays sharp at any export size. */
object TextRenderer {
    private class Prepared(val layout: StaticLayout, val paint: TextPaint, val textPx: Float, val pad: Float, val width: Int, val height: Int)

    private fun prepare(style: TextStyle, scale: Float, canvasW: Int, canvasH: Int, text: String = style.text): Prepared {
        val textPx = max(4f, style.size * canvasH * scale)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            val base = FontManager.typeface(style.fontId)
            val variable = FontManager.isVariable(style.fontId)
            val bold = style.bold && !variable
            val styleFlag = when {
                bold && style.italic -> Typeface.BOLD_ITALIC
                bold -> Typeface.BOLD
                style.italic -> Typeface.ITALIC
                else -> Typeface.NORMAL
            }
            typeface = if (styleFlag != Typeface.NORMAL) Typeface.create(base, styleFlag) else base
            if (variable) fontVariationSettings = "'wght' ${if (style.bold) 700 else 400}"
            textSize = textPx
            letterSpacing = style.letterSpacing
            color = style.color.toInt()
        }
        val maxWidth = (canvasW * 0.92f * max(1f, scale)).toInt().coerceAtLeast(16)
        val desired = text.split('\n').maxOf { line -> StaticLayout.getDesiredWidth(line.ifEmpty { " " }, paint) }
        val width = min(maxWidth, ceil(desired).toInt() + 2)
        val alignment = when (style.align) {
            TextAlign.LEFT -> Layout.Alignment.ALIGN_NORMAL
            TextAlign.CENTER -> Layout.Alignment.ALIGN_CENTER
            TextAlign.RIGHT -> Layout.Alignment.ALIGN_OPPOSITE
        }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(alignment)
            .setLineSpacing(0f, style.lineSpacing)
            .setIncludePad(false)
            .build()
        val stroke = style.strokeWidth * textPx
        val pad = (if (style.backgroundColor != 0L) textPx * 0.35f else textPx * 0.12f) + stroke + (if (style.shadow) textPx * 0.1f else 0f)
        return Prepared(layout, paint, textPx, pad, ceil(width + 2 * pad).toInt(), ceil(layout.height + 2 * pad).toInt())
    }

    /** Rendered size in canvas pixels for a [canvasW]×[canvasH] canvas. */
    fun measure(style: TextStyle, scale: Float, canvasW: Int, canvasH: Int): Pair<Float, Float> {
        val p = prepare(style, scale, canvasW, canvasH)
        return p.width.toFloat() to p.height.toFloat()
    }

    /** Renders the text; [visibleChars] (typewriter) draws only the first characters while keeping the full size. */
    fun render(style: TextStyle, scale: Float, canvasW: Int, canvasH: Int, visibleChars: Int = -1): Bitmap {
        val full = prepare(style, scale, canvasW, canvasH)
        val bitmap = Bitmap.createBitmap(max(1, full.width), max(1, full.height), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        if (style.backgroundColor != 0L) {
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = style.backgroundColor.toInt() }
            val r = full.textPx * 0.25f
            canvas.drawRoundRect(RectF(0f, 0f, full.width.toFloat(), full.height.toFloat()), r, r, bg)
        }
        val layout = if (visibleChars in 0 until style.text.length) {
            StaticLayout.Builder.obtain(style.text, 0, visibleChars, full.paint, full.layout.width)
                .setAlignment(full.layout.alignment).setLineSpacing(0f, style.lineSpacing).setIncludePad(false).build()
        } else full.layout
        canvas.save()
        canvas.translate(full.pad, full.pad)
        if (style.strokeWidth > 0f) {
            val strokePaint = TextPaint(full.paint).apply {
                this.style = Paint.Style.STROKE
                strokeWidth = style.strokeWidth * full.textPx * 2
                strokeJoin = Paint.Join.ROUND
                color = style.strokeColor.toInt()
            }
            StaticLayout.Builder.obtain(layout.text, 0, layout.text.length, strokePaint, layout.width)
                .setAlignment(layout.alignment).setLineSpacing(0f, style.lineSpacing).setIncludePad(false).build()
                .draw(canvas)
        }
        if (style.shadow) full.paint.setShadowLayer(full.textPx * 0.08f, 0f, full.textPx * 0.04f, 0x99000000.toInt())
        layout.draw(canvas)
        full.paint.clearShadowLayer()
        canvas.restore()
        return bitmap
    }
}

/** Animation state of a text clip at a local time. */
data class TextAnimState(val alpha: Float = 1f, val dy: Float = 0f, val scale: Float = 1f, val visibleFraction: Float = 1f)

object TextAnimations {
    fun at(style: TextStyle, localUs: Long, durationUs: Long): TextAnimState {
        val d = min(style.animDurationUs, durationUs / 2).coerceAtLeast(1)
        var s = TextAnimState()
        if (style.animIn != TextAnim.NONE && localUs < d) s = apply(style.animIn, localUs.toFloat() / d, entering = true)
        val remaining = durationUs - localUs
        if (style.animOut != TextAnim.NONE && remaining < d) s = apply(style.animOut, remaining.toFloat() / d, entering = false)
        return s
    }

    private fun apply(anim: TextAnim, p: Float, entering: Boolean): TextAnimState {
        val q = p.coerceIn(0f, 1f)
        val e = 1 - (1 - q) * (1 - q)
        return when (anim) {
            TextAnim.NONE -> TextAnimState()
            TextAnim.FADE -> TextAnimState(alpha = e)
            TextAnim.SLIDE_UP -> TextAnimState(alpha = e, dy = (1 - e) * (if (entering) 0.06f else -0.06f))
            TextAnim.SLIDE_DOWN -> TextAnimState(alpha = e, dy = (1 - e) * (if (entering) -0.06f else 0.06f))
            TextAnim.POP -> {
                val overshoot = if (q < 0.7f) 0.5f + 0.6f * (q / 0.7f) else 1.1f - 0.1f * ((q - 0.7f) / 0.3f)
                TextAnimState(alpha = min(1f, q * 2), scale = overshoot)
            }
            TextAnim.ZOOM -> TextAnimState(alpha = e, scale = 1.4f - 0.4f * e)
            TextAnim.TYPEWRITER -> TextAnimState(visibleFraction = q)
        }
    }
}
