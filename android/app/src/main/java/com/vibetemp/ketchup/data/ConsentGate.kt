package com.vibetemp.ketchup.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Plans (migration 0010): Muse Spark reads only for people who've said yes,
 * once, and are 18 or older. A brief sends the messages it covers, friends'
 * included, to Meta's Muse Spark, and Meta's terms (section 10.1) are for
 * people 18 and older. The server refuses catch-up and catch-up-text without
 * a row in ai_consents (a readable 403); this asks first, so the first brief
 * isn't a refusal. Port of iOS Plans/PlanGate.swift's consent half.
 *
 * BriefActivity, where every brief starts (the app's chats and the reader
 * bubble's hand-off), turns it on and shows the dialog
 * (ui/plans/ConsentDialog.kt). Off (JVM tests, anywhere else) a call goes as
 * before and the server decides. The question waits in [asking] until the
 * dialog answers it.
 */
object ConsentGate {
    const val DECLINED = "Nothing was sent to Muse Spark."

    private val museFunctions = setOf("catch-up", "catch-up-text")
    private const val ANSWER_WAIT_MS = 120_000L

    /** On while a screen that can show the dialog is up. */
    @Volatile var enabled = false

    /** Who has said yes, as the server last said. */
    @Volatile private var consented: String? = null

    private val lock = Mutex()
    private val _asking = MutableStateFlow<CompletableDeferred<Boolean>?>(null)

    /** A question for the dialog, until it's answered. */
    val asking: StateFlow<CompletableDeferred<Boolean>?> = _asking.asStateFlow()

    fun answer(yes: Boolean) {
        _asking.value?.complete(yes)
    }

    /** [block] (the edge function call), after the one-time question if it's a Muse Spark call. */
    suspend fun <T> call(client: SupabaseClient, function: String, block: suspend () -> T): T {
        if (enabled && function in museFunctions && !Previewing.active) ensure(client)
        return try {
            block()
        } catch (e: ApiException) {
            // The server knows best: a 403 (no consent after all) means check again next time.
            if (e.status == 403) consented = null
            throw e
        }
    }

    private suspend fun ensure(client: SupabaseClient) {
        val me = client.userId ?: return
        if (consented == me) return
        lock.withLock {
            if (consented == me) return
            val saved = try {
                client.rest("GET", "/rest/v1/ai_consents", listOf("select" to "consented_at", "user_id" to "eq.$me"))
            } catch (e: ApiException) {
                // No ai_consents table: the server doesn't have plans yet, so there's nothing to ask.
                if (e.status == 404) return
                throw e
            }
            if (saved.trim() != "[]") {
                consented = me
                return
            }
            val question = CompletableDeferred<Boolean>()
            _asking.value = question
            val yes = try {
                withTimeoutOrNull(ANSWER_WAIT_MS) { question.await() } ?: false
            } finally {
                _asking.compareAndSet(question, null)
            }
            if (!yes) throw ApiException(DECLINED)
            client.rest(
                "POST", "/rest/v1/ai_consents",
                body = """{"user_id":"$me","confirmed_adult":true}""",
                prefer = "resolution=ignore-duplicates,return=minimal",
            )
            consented = me
        }
    }
}
