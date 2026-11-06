package com.framenova.app.ui.editor

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.framenova.app.R
import com.framenova.app.engine.ExportQuality
import com.framenova.app.engine.FilterDef
import com.framenova.app.engine.FontDef
import com.framenova.app.model.LayoutPreset
import com.framenova.app.model.TextAnim
import com.framenova.app.model.TransitionType

/** Display names for the model's built-in options. The enum labels stay English for logs; the UI shows these. */

@Composable
fun TransitionType.displayName(): String = stringResource(
    when (this) {
        TransitionType.FADE -> R.string.transition_fade
        TransitionType.DIP_BLACK -> R.string.transition_dip_to_black
        TransitionType.DIP_WHITE -> R.string.transition_dip_to_white
        TransitionType.PUSH_LEFT -> R.string.transition_push_left
        TransitionType.PUSH_RIGHT -> R.string.transition_push_right
        TransitionType.PUSH_UP -> R.string.transition_push_up
        TransitionType.PUSH_DOWN -> R.string.transition_push_down
        TransitionType.SLIDE_LEFT -> R.string.transition_slide_left
        TransitionType.SLIDE_RIGHT -> R.string.transition_slide_right
        TransitionType.SLIDE_UP -> R.string.transition_slide_up
        TransitionType.SLIDE_DOWN -> R.string.transition_slide_down
        TransitionType.ZOOM_IN -> R.string.transition_zoom_in
        TransitionType.ZOOM_OUT -> R.string.transition_zoom_out
    },
)

@Composable
fun TextAnim.displayName(): String = stringResource(
    when (this) {
        TextAnim.NONE -> R.string.anim_none
        TextAnim.FADE -> R.string.transition_fade
        TextAnim.SLIDE_UP -> R.string.transition_slide_up
        TextAnim.SLIDE_DOWN -> R.string.transition_slide_down
        TextAnim.POP -> R.string.anim_pop
        TextAnim.TYPEWRITER -> R.string.anim_typewriter
        TextAnim.ZOOM -> R.string.anim_zoom
    },
)

@Composable
fun ExportQuality.displayName(): String = stringResource(
    when (this) {
        ExportQuality.STANDARD -> R.string.quality_standard
        ExportQuality.HIGH -> R.string.quality_high
        ExportQuality.MAXIMUM -> R.string.quality_maximum
    },
)

@Composable
fun LayoutPreset.displayName(): String = when (id) {
    "fit" -> stringResource(R.string.layout_fit)
    "side2" -> stringResource(R.string.layout_side_by_side)
    "stack2" -> stringResource(R.string.layout_top_bottom)
    "pip_br" -> stringResource(R.string.layout_pip_bottom_right)
    "pip_tl" -> stringResource(R.string.layout_pip_top_left)
    "cols3" -> stringResource(R.string.layout_3_columns)
    "rows3" -> stringResource(R.string.layout_3_rows)
    "big_top3" -> stringResource(R.string.layout_1_over_2)
    else -> label
}

@Composable
fun FilterDef.displayName(): String = when (id) {
    "vivid" -> stringResource(R.string.filter_vivid)
    "warm" -> stringResource(R.string.filter_warm)
    "cool" -> stringResource(R.string.filter_cool)
    "golden" -> stringResource(R.string.filter_golden)
    "teal_orange" -> stringResource(R.string.filter_teal_orange)
    "film" -> stringResource(R.string.filter_film)
    "chrome" -> stringResource(R.string.filter_chrome)
    "fade" -> stringResource(R.string.filter_fade)
    "pastel" -> stringResource(R.string.filter_pastel)
    "vintage" -> stringResource(R.string.filter_vintage)
    "forest" -> stringResource(R.string.filter_forest)
    "rose" -> stringResource(R.string.filter_rose)
    "cyber" -> stringResource(R.string.filter_cyber)
    "bleach" -> stringResource(R.string.filter_bleach)
    "mono" -> stringResource(R.string.filter_mono)
    "noir" -> stringResource(R.string.filter_noir)
    else -> name
}

@Composable
fun FontDef.displayName(): String = when (id) {
    "system" -> stringResource(R.string.font_system_sans)
    "system_serif" -> stringResource(R.string.font_system_serif)
    "system_mono" -> stringResource(R.string.font_system_mono)
    else -> name
}
