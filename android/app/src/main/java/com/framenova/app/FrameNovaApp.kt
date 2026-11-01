package com.framenova.app

import android.app.Application
import com.framenova.app.engine.FontManager

class FrameNovaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FontManager.init(this)
    }
}
