package com.vibetemp.ketchup.ui.brief

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.vibetemp.ketchup.data.AskResponse
import com.vibetemp.ketchup.data.BriefSource
import com.vibetemp.ketchup.data.CatchUpResponse
import com.vibetemp.ketchup.data.TextThread
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

/** The state of one Muse Spark request (iOS `AIPhase`). */
sealed interface Phase<out T> {
    data object Idle : Phase<Nothing>
    data object Loading : Phase<Nothing>
    data class Done<out T>(val value: T) : Phase<T>
    data class Failed(val message: String) : Phase<Nothing>
}

/** What a finished request brought back, or null. */
val <T> Phase<T>.done: T? get() = if (this is Phase.Done) value else null

/**
 * What a brief needs from the outside world: the live API for a Ketchup
 * chat or a thread ([ChatBackend], [ThreadBackend]), or an offline
 * preview's script.
 */
interface BriefBackend {
    val signedIn: Boolean

    /**
     * The reader as the chat names them ("David"), which is how Muse Spark
     * writes them. "" when unknown. For a thread it's also what gets sent,
     * so it's never empty there ("Me" without a Ketchup name, like iOS).
     */
    suspend fun readerName(): String

    /** The messages to run past while Muse Spark reads. */
    suspend fun skim(): Skim

    suspend fun catchUp(readerName: String): CatchUpResponse

    suspend fun ask(question: String, readerName: String): AskResponse

    /** The messages behind these refs, the ones it can find. */
    suspend fun cited(refs: Collection<String>): Map<String, Cited>

    /** A catch-up landed: move the read cursor to [until] (Ketchup chats only). */
    suspend fun caughtUp(until: Instant?)
}

/**
 * One Catch me up, and any questions asked after it, for one [source].
 * Owned by BriefActivity's ViewModel (so a rotation keeps a request that's
 * running) or by a preview. Compose state, written on the main thread.
 * Nothing here is written to disk; a thread's messages stay in memory.
 *
 * [askFirst] is the chat's Ask button: the page opens on Ask the chat and
 * no catch-up runs until the reader asks for one ([runCatchUp]), like iOS's
 * Ask sheet, which never catches up on its own.
 */
@Stable
class BriefSession(
    val source: BriefSource,
    private val backend: BriefBackend,
    private val scope: CoroutineScope,
    val askFirst: Boolean = false,
) {
    var signedOut by mutableStateOf(false)
        internal set
    var readerName by mutableStateOf("")
        internal set
    var catchUp by mutableStateOf<Phase<CatchUpResponse>>(Phase.Idle)
        internal set
    var answer by mutableStateOf<Phase<AskResponse>>(Phase.Idle)
        internal set
    var lastQuestion by mutableStateOf("")
        internal set
    var skim by mutableStateOf<Skim?>(null)
        internal set
    var cited by mutableStateOf<Map<String, Cited>>(emptyMap())
        internal set

    private var started = false

    /** Who's reading, asked for once and shared by every call that needs it. */
    private val reader = scope.async(start = CoroutineStart.LAZY) {
        catching { backend.readerName() }.getOrDefault("").also { readerName = it }
    }

    /**
     * Starts the catch-up unless one is running or already here, or the page
     * opened for Ask. Safe to call again.
     */
    fun start() {
        if (started) return
        started = true
        if (!backend.signedIn) {
            signedOut = true
            return
        }
        scope.launch { catching { backend.skim() }.onSuccess { skim = it } }
        scope.launch { reader.await() }
        when (val phase = catchUp) {
            Phase.Idle -> if (!askFirst) runCatchUp()
            is Phase.Done -> phase.value.result?.let { loadCited(Refs.all(it)) }
            else -> Unit
        }
        val asked = answer
        if (asked is Phase.Done) asked.value.result?.let { loadCited(it.refs) }
    }

    /** Catch me up (again, after a failure). Tapped twice, it runs once. */
    fun runCatchUp() {
        if (catchUp == Phase.Loading || signedOut) return
        catchUp = Phase.Loading
        scope.launch {
            catchUp = try {
                val response = backend.catchUp(reader.await())
                val error = response.error
                if (error != null) {
                    Phase.Failed(error)
                } else {
                    // Caught up through the newest message the brief read. Nothing new
                    // has no `until` and nothing to mark (a message arriving meanwhile stays unread).
                    response.untilInstant?.let { until ->
                        scope.launch { withContext(NonCancellable) { catching { backend.caughtUp(until) } } }
                    }
                    response.result?.let { loadCited(Refs.all(it)) }
                    Phase.Done(response)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed(e) ?: return@launch
            }
        }
    }

    /** Ask the chat. The question is trimmed and kept to 500 characters, like iOS. */
    fun ask(question: String) {
        val q = question.trim().take(500)
        if (q.isEmpty() || answer == Phase.Loading || signedOut) return
        lastQuestion = q
        answer = Phase.Loading
        scope.launch {
            answer = try {
                val response = backend.ask(q, reader.await())
                val error = response.error
                if (error != null) {
                    Phase.Failed(error)
                } else {
                    response.result?.let { loadCited(it.refs) }
                    Phase.Done(response)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed(e) ?: return@launch
            }
        }
    }

    /** The last question again. */
    fun retryAsk() = ask(lastQuestion)

    /** What a failure shows, or null when it was the session ending (the page turns to Sign in). */
    private fun failed(e: Exception): Phase.Failed? {
        if (!backend.signedIn) {
            signedOut = true
            return null
        }
        return Phase.Failed(BriefErrors.message(e))
    }

    private fun loadCited(refs: Collection<String>) {
        val missing = refs.filter { it !in cited }
        if (missing.isEmpty()) return
        scope.launch {
            catching { backend.cited(missing) }.onSuccess { found -> if (found.isNotEmpty()) cited = cited + found }
        }
    }

    /** A thread read off another app (refs open a sheet), not a Ketchup chat (refs jump into it). */
    val isThread: Boolean get() = source is TextThread
}

/** runCatching that lets cancellation through. */
internal inline fun <T> catching(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    Result.failure(e)
}
