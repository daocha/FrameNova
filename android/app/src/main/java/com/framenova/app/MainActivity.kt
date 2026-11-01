package com.framenova.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.media3.common.util.UnstableApi
import com.framenova.app.ui.editor.EditorRoute
import com.framenova.app.ui.home.HomeScreen
import com.framenova.app.ui.theme.FrameNovaTheme
import com.framenova.app.ui.theme.Palette
import com.framenova.app.update.AppUpdates

@UnstableApi
class MainActivity : ComponentActivity() {
    private lateinit var updates: AppUpdates
    private val playUpdate = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        updates.onPlayResult(result.resultCode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        updates = AppUpdates(this, playUpdate)
        setContent {
            FrameNovaTheme {
                var openProject by rememberSaveable { mutableStateOf<String?>(null) }
                Surface(Modifier.fillMaxSize(), color = Palette.Bg, contentColor = Palette.Text) {
                Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                    val id = openProject
                    if (id == null) {
                        HomeScreen(updates = updates, onOpen = { openProject = it })
                    } else {
                        BackHandler { openProject = null }
                        EditorRoute(projectId = id, onClose = { openProject = null })
                    }
                }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        updates.onResume()
    }

    override fun onDestroy() {
        updates.close()
        super.onDestroy()
    }
}
