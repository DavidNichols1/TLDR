package com.vibetemp.ketchup.ui.brief

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.vibetemp.ketchup.data.BriefResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.BriefSourceIntent
import com.vibetemp.ketchup.data.CatchUp
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.KetchupJson
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * Catch me up and Ask, for a [BriefSource]. Started from the app (a Ketchup
 * chat) or from the reader service over Instagram or Snapchat (a
 * [TextThread], in a task of its own, so Back returns to that app). The
 * brief slice owns this file; the two `start`/`intent` functions and
 * [EXTRA_JUMP_TO_MESSAGE] are the contract the other slices call.
 *
 * The catch-up starts as the page opens and survives a rotation (it lives
 * in a ViewModel). For a chat, a tapped source finishes with RESULT_OK and
 * the message's id; the brief also moves the chat's read cursor to the
 * newest message it read, like iOS, so the chat should refresh its unread
 * count when the brief returns.
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

        /** A chat's finished brief, kept across the process dying while the page was in the background. */
        private const val STATE_BRIEF = "brief"
    }

    private var session: BriefSession? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A thread brief's task reopened from Recents after it was closed
        // would read a thread that may have moved on (and spend another
        // catch-up): treat it as gone, like after the process died.
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        val source = BriefSourceIntent.from(intent)
            ?.takeUnless { it is TextThread && fromHistory && savedInstanceState == null }
        session = source?.let { s ->
            val restored = if (s is BriefSource.Chat) savedInstanceState?.getString(STATE_BRIEF)?.let(::decode) else null
            val factory = BriefViewModel.Factory(KetchupApi.get(applicationContext), s, restored)
            ViewModelProvider(this, factory)[BriefViewModel::class.java].session
        }
        setContent {
            KetchupTheme {
                BriefPage(session, onDone = ::finish, onJump = ::jumpTo, onOpenApp = ::openApp)
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Only a Ketchup chat's brief: a thread read off another app is never kept.
        val current = session ?: return
        if (current.source !is BriefSource.Chat) return
        current.catchUp.done?.let { outState.putString(STATE_BRIEF, KetchupJson.encodeToString(SERIALIZER, it)) }
    }

    /** A cited message in a Ketchup chat: hand its id back so the chat scrolls to it. */
    private fun jumpTo(messageId: String) {
        setResult(RESULT_OK, Intent().putExtra(EXTRA_JUMP_TO_MESSAGE, messageId))
        finish()
    }

    /** Not signed in: bring Ketchup itself up (its own task, when the brief opened over another app). */
    private fun openApp() {
        if (isTaskRoot) {
            packageManager.getLaunchIntentForPackage(packageName)?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        finish()
    }

    private fun decode(raw: String): CatchUpResponse? = catching { KetchupJson.decodeFromString(SERIALIZER, raw) }.getOrNull()
}

private val SERIALIZER = BriefResponse.serializer(CatchUp.serializer())

/** Holds the page's [BriefSession], so a rotation keeps a catch-up that's running. */
internal class BriefViewModel(api: KetchupApi, source: BriefSource, restored: CatchUpResponse?) : ViewModel() {
    val session = BriefSession(source, liveBackend(api, source), viewModelScope).apply {
        if (restored != null) catchUp = Phase.Done(restored)
        start()
    }

    class Factory(
        private val api: KetchupApi,
        private val source: BriefSource,
        private val restored: CatchUpResponse?,
    ) : ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            @Suppress("UNCHECKED_CAST")
            return BriefViewModel(api, source, restored) as T
        }
    }
}
