package com.vibetemp.ketchup.reader

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.ui.design.ButtonFill
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * "Your name on Snapchat": asked once, the first time the Snapchat bubble
 * is tapped (or from the Snapchat page's Change). Snapchat draws everyone's
 * messages on the left under the sender's name, so this is how the reader
 * tells the person's own from their friends'. Prefilled with their Ketchup
 * name. Its own task, like BriefActivity: Save or Not now goes back to
 * Snapchat, where the bubble's panel opens.
 */
class SnapchatNameActivity : ComponentActivity() {

    companion object {
        /** Opens it; from the reader service it adds FLAG_ACTIVITY_NEW_TASK, so it opens over Snapchat. */
        fun start(context: Context) {
            val intent = Intent(context, SnapchatNameActivity::class.java)
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val saved = ReaderMemory.snapchatName(this)
        setContent {
            KetchupTheme {
                var ketchupName by rememberSaveable { mutableStateOf<String?>(null) }
                if (saved == null) {
                    LaunchedEffect(Unit) {
                        ketchupName = runCatching { KetchupApi.get(this@SnapchatNameActivity).myProfile()?.displayName }.getOrNull()
                    }
                }
                SnapchatNameScreen(
                    initial = saved ?: ketchupName,
                    onSave = { name ->
                        ReaderMemory.setSnapchatName(this, name)
                        finish()
                    },
                    onCancel = ::finish,
                )
            }
        }
    }
}

/**
 * The screen itself. [initial] fills the field until the person types
 * (it may arrive a moment late: the Ketchup name comes from the server).
 */
@Composable
fun SnapchatNameScreen(initial: String?, onSave: (String) -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val colors = KetchupTheme.colors
    var name by rememberSaveable { mutableStateOf("") }
    var typed by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(initial) {
        if (!typed && initial != null) name = initial
    }
    val save = { if (name.isNotBlank()) onSave(name.trim()) }
    Column(
        modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Kicker(stringResource(R.string.reader_name_kicker))
            Text(
                stringResource(R.string.reader_name_title),
                style = KetchupTheme.type.serifTitle,
                color = colors.ink,
                modifier = Modifier.semantics { heading() },
            )
        }
        Text(stringResource(R.string.reader_name_body), style = KetchupTheme.type.body, color = colors.ink)
        OutlinedTextField(
            value = name,
            onValueChange = {
                name = it
                typed = true
            },
            label = { Text(stringResource(R.string.reader_name_field)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { save() }),
            modifier = Modifier.fillMaxWidth(),
        )
        Text(stringResource(R.string.reader_name_note), style = KetchupTheme.type.footnote, color = colors.inkSoft)
        CapsuleButton(stringResource(R.string.reader_name_save), onClick = save, enabled = name.isNotBlank())
        CapsuleButton(stringResource(R.string.reader_name_cancel), onClick = onCancel, fill = ButtonFill.Outline)
    }
}
