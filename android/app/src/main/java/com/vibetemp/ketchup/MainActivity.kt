package com.vibetemp.ketchup

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.data.Previewing
import com.vibetemp.ketchup.debug.PreviewHost
import com.vibetemp.ketchup.ui.design.KetchupDrop
import com.vibetemp.ketchup.ui.design.Wordmark
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * The app's one activity for Ketchup's own chats (the chat slice owns it and
 * the nav graph). Debug builds open a fixture screen instead when started
 * with `--es screen <name>` (debug/Previews.kt); nothing then goes to the
 * server ([Previewing]).
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
                if (name != null) PreviewHost.Screen(name) else Home()
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

/** Placeholder until the chat slice's sign-in and inbox land. */
@Composable
private fun Home() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(KetchupTheme.colors.cream)
            .safeDrawingPadding()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        KetchupDrop(size = 72.dp)
        Wordmark(drawIn = true)
        Text(
            stringResource(R.string.home_coming_soon),
            style = KetchupTheme.type.body,
            color = KetchupTheme.colors.inkSoft,
            textAlign = TextAlign.Center,
        )
    }
}
