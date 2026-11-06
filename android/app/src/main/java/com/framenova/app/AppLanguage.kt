package com.framenova.app

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/** The language chosen in Settings: the phone's own, English or Traditional Chinese. */
object AppLanguage {
    const val SYSTEM = "system"
    const val ENGLISH = "en"
    const val TRADITIONAL_CHINESE = "zh-Hant"
    val all = listOf(SYSTEM, ENGLISH, TRADITIONAL_CHINESE)

    private fun prefs(context: Context) = context.getSharedPreferences("preferences", Context.MODE_PRIVATE)

    fun get(context: Context): String = prefs(context).getString("language", SYSTEM)?.takeIf { it in all } ?: SYSTEM

    /** [base] with the chosen language, for an activity or service to use as its base context. */
    fun wrap(base: Context): Context {
        val tag = get(base)
        if (tag == SYSTEM) return base
        val config = Configuration(base.resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) }
        return base.createConfigurationContext(config)
    }

    /** The language in use. Compose reads it, so the screen redraws in the new language without the activity restarting. */
    var current by mutableStateOf(SYSTEM)
        private set

    /** Reads the saved choice; call before the first screen is composed. */
    fun load(context: Context) { current = get(context) }

    /** [live] (the screen's current configuration) with the chosen language: the phone's own for [SYSTEM]. */
    fun localize(live: Configuration, tag: String): Configuration = Configuration(live).apply {
        setLocale(if (tag == SYSTEM) Resources.getSystem().configuration.locales[0] else Locale.forLanguageTag(tag))
    }

    /** Saves the choice and applies it to the application's resources and to every screen that reads [current]. */
    @Suppress("DEPRECATION")
    fun set(context: Context, tag: String) {
        if (tag !in all || tag == current) return
        prefs(context).edit().putString("language", tag).apply()
        // Text read outside the screens (messages from the editor, notifications) comes from the application's resources.
        val app = context.applicationContext
        app.resources.updateConfiguration(localize(app.resources.configuration, tag), app.resources.displayMetrics)
        current = tag
    }
}
