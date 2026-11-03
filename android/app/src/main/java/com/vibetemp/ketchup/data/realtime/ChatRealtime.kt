package com.vibetemp.ketchup.data.realtime

import com.vibetemp.ketchup.data.Config
import com.vibetemp.ketchup.data.Message
import com.vibetemp.ketchup.data.Previewing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.min

/**
 * New messages in one open chat, live (iOS `ChatRealtime`). One socket per
 * open chat: join [RealtimeProtocol.topic], heartbeat every 25 s, and pass
 * the member's access token, so Realtime applies the messages select
 * policy. If the socket drops it reconnects with backoff (2, 4, 8, 16, then
 * every 30 s); the chat polls while [isLive] is false, so messages still
 * arrive. Refuses to connect in an offline preview ([Previewing]).
 *
 * [onInsert] runs on [scope]'s dispatcher (the main thread in the app).
 */
class ChatRealtime(
    private val chatId: String,
    private val scope: CoroutineScope,
    /** A valid access token, refreshed when it's about to lapse (`SupabaseClient.freshAccessToken`); null when signed out. */
    private val accessToken: suspend () -> String?,
    private val connector: WebSocketConnector = SocketConnector,
    private val url: String = Config.REALTIME_URL,
    private val heartbeatMs: Long = RealtimeProtocol.HEARTBEAT_MS,
    /** How long to wait before the [failures]th reconnect. */
    private val backoffMs: (failures: Int) -> Long = ::backoff,
    private val onInsert: (Message) -> Unit,
) {
    private val live = MutableStateFlow(false)

    /** Joined and streaming. False while connecting, after a drop, and once stopped. */
    val isLive: StateFlow<Boolean> = live.asStateFlow()

    private var job: Job? = null

    @Volatile
    private var connection: WebSocketConnection? = null
    private val ref = AtomicInteger(0)

    /** Connects (once; a second call while running does nothing). */
    fun start() {
        if (Previewing.active) return
        if (job?.isActive == true) return
        job = scope.launch { run() }
    }

    /** Leaves the channel and closes the socket. */
    fun stop() {
        job?.cancel()
        job = null
        connection?.let { conn ->
            connection = null
            conn.close()
        }
        live.value = false
    }

    private suspend fun run() {
        var failures = 0
        while (currentCoroutineContext().isActive) {
            val token = accessToken() ?: return // signed out: nothing to stream
            val joinRef = next()
            try {
                val conn = withContext(Dispatchers.IO) { connector.connect(url) }
                connection = conn
                session(conn, token, joinRef) { failures = 0 }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Couldn't connect, or the socket broke: back off and try again.
            }
            live.value = false
            connection?.let { conn ->
                connection = null
                conn.close()
            }
            if (!currentCoroutineContext().isActive) return
            failures += 1
            delay(backoffMs(failures))
        }
    }

    /** One socket's life: join, heartbeat, read frames until it closes or the channel goes down. */
    private suspend fun session(conn: WebSocketConnection, firstToken: String, joinRef: String, onJoined: () -> Unit) =
        coroutineScope {
            send(conn, RealtimeProtocol.join(chatId, firstToken, joinRef))
            val beats = launch {
                var sentToken = firstToken
                while (isActive) {
                    delay(heartbeatMs)
                    if (!send(conn, RealtimeProtocol.heartbeat(next()))) return@launch
                    // Tokens last an hour; hand Realtime the new one when it changes.
                    val token = accessToken()
                    if (token != null && token != sentToken) {
                        sentToken = token
                        send(conn, RealtimeProtocol.accessToken(chatId, token, next(), joinRef))
                    }
                }
            }
            try {
                while (true) {
                    val text = withContext(Dispatchers.IO) { conn.receive() } ?: break
                    when (val event = RealtimeProtocol.parse(text, chatId, joinRef)) {
                        RealtimeProtocol.Event.Joined -> {
                            live.value = true
                            onJoined()
                        }
                        is RealtimeProtocol.Event.Down -> {
                            live.value = false
                            break
                        }
                        is RealtimeProtocol.Event.Insert -> onInsert(event.message)
                        RealtimeProtocol.Event.Ignored -> Unit
                    }
                }
            } finally {
                beats.cancel()
            }
        }

    private suspend fun send(conn: WebSocketConnection, text: String): Boolean =
        withContext(Dispatchers.IO) { conn.send(text) }

    private fun next(): String = ref.incrementAndGet().toString()

    companion object {
        /** 2, 4, 8, 16, then 30 s between tries (iOS's backoff). */
        fun backoff(failures: Int): Long = min(30_000L, 1000L shl min(failures, 5))
    }
}
