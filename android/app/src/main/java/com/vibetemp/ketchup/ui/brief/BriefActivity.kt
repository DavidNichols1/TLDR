package com.vibetemp.ketchup.ui.brief

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.BriefSourceIntent
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.ui.design.CapsuleButton
import com.vibetemp.ketchup.ui.design.Kicker
import com.vibetemp.ketchup.ui.design.paperCard
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * Catch me up and Ask, for a [BriefSource]. Started from the app (a Ketchup
 * chat) or from the reader service over Instagram or Snapchat (a
 * [TextThread], in a task of its own). The brief slice owns this file; the
 * two `start`/`intent` functions are the contract the other slices call.
 *
 * Stub for now: it shows which source it was started for.
 */
class BriefActivity : ComponentActivity() {

    companion object {
        /** An Intent that opens the brief for [source]. */
        fun intent(context: Context, source: BriefSource): Intent =
            BriefSourceIntent.put(Intent(context, BriefActivity::class.java), source)

        /**
         * Opens the brief for [source]. From anything but an activity (the
         * reader service) it adds FLAG_ACTIVITY_NEW_TASK, so the brief opens
         * over the other app in a task of its own.
         */
        fun start(context: Context, source: BriefSource) {
            val intent = intent(context, source)
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }

        /**
         * What a brief for a Ketchup chat returns (with RESULT_OK) when a cited
         * message is tapped: that message's id, so the chat scrolls to it.
         */
        const val EXTRA_JUMP_TO_MESSAGE = "com.vibetemp.ketchup.extra.JUMP_TO_MESSAGE"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val source = BriefSourceIntent.from(intent)
        setContent {
            KetchupTheme {
                BriefStub(source, onDone = ::finish)
            }
        }
    }
}

/** What the stub shows: the source it was started for, or why there's none. */
@Composable
fun BriefStub(source: BriefSource?, onDone: () -> Unit) {
    val colors = KetchupTheme.colors
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.cream)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Kicker(stringResource(R.string.brief_kicker))
        when (source) {
            null -> Text(stringResource(R.string.brief_source_gone), style = KetchupTheme.type.body, color = colors.ink)
            is BriefSource.Chat -> Column(Modifier.paperCard(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Kicker(stringResource(R.string.brief_source_chat))
                Text(source.displayTitle, style = KetchupTheme.type.serifTitle2, color = colors.ink)
                Text(source.id, style = KetchupTheme.type.monoCaption, color = colors.inkSoft)
            }
            is TextThread -> Column(Modifier.paperCard(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Kicker(source.source.appName)
                Text(source.displayTitle, style = KetchupTheme.type.serifTitle2, color = colors.ink)
                Text(
                    pluralStringResource(R.plurals.brief_message_count, source.messages.size, source.messages.size),
                    style = KetchupTheme.type.monoCaption,
                    color = colors.inkSoft,
                )
                source.messages.takeLast(3).forEach { m ->
                    Text(
                        "${if (m.isMine) stringResource(R.string.brief_you) else m.sender}: ${m.text}",
                        style = KetchupTheme.type.subheadline,
                        color = colors.ink,
                        maxLines = 2,
                    )
                }
            }
        }
        CapsuleButton(stringResource(R.string.brief_done), onClick = onDone)
    }
}
