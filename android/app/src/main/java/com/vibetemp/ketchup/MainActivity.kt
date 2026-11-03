package com.vibetemp.ketchup

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.vibetemp.ketchup.data.Previewing
import com.vibetemp.ketchup.debug.PreviewHost
import com.vibetemp.ketchup.ui.chats.AppModel
import com.vibetemp.ketchup.ui.chats.KetchupRoot
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * The app's one activity for Ketchup's own chats (the chat slice owns it and
 * the nav graph, `ui/chats/KetchupRoot.kt`). Debug builds open a fixture
 * screen instead when started with `--es screen <name>` (debug/PreviewHost.kt);
 * nothing then goes to the server ([Previewing]).
 */
class MainActivity : ComponentActivity() {

    /** The `screen` extra, when a debug build was asked for a preview. */
    private var screen by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        screen = previewName(intent)
        setContent {
            KetchupTheme {
                val name = screen
                if (name != null) PreviewHost.Screen(name) else KetchupRoot(AppModel.get(this))
            }
        }
    }

    /** `am start` again with another `screen` lands here (singleTop). */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        previewName(intent)?.let { screen = it }
    }

    private fun previewName(intent: Intent?): String? {
        val name = intent?.getStringExtra(PreviewHost.EXTRA_SCREEN) ?: return null
        if (!PreviewHost.AVAILABLE) return null
        Previewing.active = true
        return name
    }
}
