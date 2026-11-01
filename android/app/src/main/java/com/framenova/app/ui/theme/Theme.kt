package com.framenova.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

object Palette {
    val Accent = Color(0xFF8B6CFF)
    val AccentSoft = Color(0xFF2C2547)
    val Teal = Color(0xFF2FD1C1)
    val Bg = Color(0xFF0E0E12)
    val Surface = Color(0xFF17171D)
    val Surface2 = Color(0xFF202028)
    val Surface3 = Color(0xFF2A2A34)
    val Text = Color(0xFFF2F2F5)
    val TextDim = Color(0xFF9B9BA8)
    val Main = Color(0xFF3A3A48)
    val Overlay = Color(0xFF4A3B7A)
    val TextClip = Color(0xFFB0457E)
    val Audio = Color(0xFF1F6F6A)
    val Danger = Color(0xFFFF5A6A)
}

private val scheme = darkColorScheme(
    primary = Palette.Accent,
    onPrimary = Color.White,
    secondary = Palette.Teal,
    background = Palette.Bg,
    surface = Palette.Surface,
    surfaceVariant = Palette.Surface2,
    surfaceContainer = Palette.Surface2,
    surfaceContainerHigh = Palette.Surface3,
    onSurface = Palette.Text,
    onSurfaceVariant = Palette.TextDim,
    error = Palette.Danger,
)

@Composable
fun FrameNovaTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = Typography(), content = content)
}
