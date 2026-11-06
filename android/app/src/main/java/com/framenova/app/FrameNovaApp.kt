package com.framenova.app

import android.app.Application
import com.framenova.app.engine.FontManager

class FrameNovaApp : Application() {
    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(AppLanguage.wrap(base))

    override fun onCreate() {
        super.onCreate()
        DevTools.recordCrashes(this)
        android.util.Log.i(LOG_TAG, "Started ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) on ${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}, Android ${android.os.Build.VERSION.RELEASE}")
        FontManager.init(this)
    }
}
