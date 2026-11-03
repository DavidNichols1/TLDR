package com.vibetemp.ketchup.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * A small hand-rolled Supabase client: Auth (email code), PostgREST, RPCs and
 * edge functions over HttpURLConnection, so the app has no networking
 * dependency. A port of iOS `Net/Supabase.swift`, with AurariaGO Android's
 * plumbing (a swappable [Transport] for JVM tests, a [Mutex] around refresh).
 * Same token rule as both: only Supabase Auth refusing the refresh token
 * (400 or 401) signs you out; offline or a 5xx keeps the session.
 *
 * Realtime is the chat slice's (`data/realtime/`): it takes
 * [freshAccessToken] and [Config.REALTIME_URL].
 */
class SupabaseClient(
    private val store: SessionStore,
    private val transport: Transport = HttpTransport(),
    /** Unix seconds; the tests move it. */
    private val now: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val _session = MutableStateFlow(store.load())

    /** The signed-in session, or null. Kept in private app storage on every change. */
    val session: StateFlow<AuthSession?> = _session.asStateFlow()

    val userId: String? get() = _session.value?.userId

    private fun setSession(value: AuthSession?) {
        _session.value = value
        store.save(value)
    }

    // MARK: Auth (email code)

    /** Emails a one-time code ([Config.OTP_LENGTH] digits). Creates the account on first sign-in. */
    suspend fun sendCode(email: String) {
        auth("/auth/v1/otp", obj("email" to email, "create_user" to true))
    }

    /** Exchanges the emailed code for a session and keeps it. */
    suspend fun verifyCode(email: String, code: String): AuthSession {
        val body = auth("/auth/v1/verify", obj("type" to "email", "email" to email, "token" to code))
        return parseSession(body).also(::setSession)
    }

    /** Ends the session here, and on the server when it answers. */
    suspend fun signOut() {
        _session.value?.accessToken?.let { token ->
            runCatching { auth("/auth/v1/logout", obj(), bearer = token) }
        }
        setSession(null)
    }

    /** A valid access token (refreshed if it's about to lapse), for Realtime. */
    suspend fun freshAccessToken(): String? {
        runCatching { refreshIfNeeded() }
        return _session.value?.accessToken
    }

    /**
     * Refreshes the session when its token lapses within a minute. Every
     * [rest] call does this first. Concurrent callers share one refresh
     * instead of each spending the same refresh token.
     */
    suspend fun refreshIfNeeded() {
        if (_session.value?.isExpiringSoon(now()) != true) return
        refreshLock.withLock {
            val current = _session.value ?: return
            if (!current.isExpiringSoon(now())) return
            refresh(current)
        }
    }

    /** Spends the refresh token now, whatever the expiry says. */
    suspend fun refresh() = refreshLock.withLock {
        refresh(_session.value ?: throw ApiException.notSignedIn())
    }

    private suspend fun refresh(current: AuthSession) {
        val body = try {
            auth("/auth/v1/token?grant_type=refresh_token", obj("refresh_token" to current.refreshToken))
        } catch (e: ApiException) {
            if (e.status == 400 || e.status == 401) {
                setSession(null)
                throw ApiException.notSignedIn()
            }
            throw e
        }
        // A 2xx that isn't a session (a captive portal's page) is no verdict on the token.
        setSession(runCatching { parseSession(body) }.getOrElse { throw ApiException.badResponse() })
    }

    private val refreshLock = Mutex()

    // MARK: PostgREST, RPC, functions

    /**
     * One PostgREST call as the signed-in member: Row Level Security decides
     * what comes back. [path] starts with "/rest/v1/"; [query] pairs are
     * PostgREST filters ("chat_id" to "eq.<id>"). Returns the body.
     */
    suspend fun rest(
        method: String,
        path: String,
        query: List<Pair<String, String>> = emptyList(),
        body: String? = null,
        prefer: String? = null,
    ): String {
        if (Previewing.active) throw ApiException.offline()
        if (_session.value == null) throw ApiException.notSignedIn()
        refreshIfNeeded()
        val token = _session.value?.accessToken ?: throw ApiException.notSignedIn()
        val headers = linkedMapOf(
            "apikey" to Config.PUBLISHABLE_KEY,
            "Authorization" to "Bearer $token",
        )
        if (body != null) headers["Content-Type"] = "application/json"
        if (prefer != null) headers["Prefer"] = prefer
        val url = Config.SUPABASE_URL + path + queryString(query)
        val timeout = if (path.startsWith("/functions/")) FUNCTION_TIMEOUT_MS else REST_TIMEOUT_MS
        return check(transport.send(HttpRequest(method, url, headers, body, timeout)))
    }

    /** A table read: `select("messages", "chat_id" to "eq.<id>", "order" to "created_at.desc")`. */
    suspend fun select(table: String, vararg query: Pair<String, String>): String =
        rest("GET", "/rest/v1/$table", query.toList())

    /** Inserts [json] (an object or an array) and returns the new rows' [columns]. */
    suspend fun insert(table: String, json: String, columns: String = "*"): String =
        rest("POST", "/rest/v1/$table", listOf("select" to columns), json, prefer = "return=representation")

    /** Calls a Postgres function (`my_chats`, `mark_read`, ...) with named [args]. */
    suspend fun rpc(name: String, args: JsonObject = obj()): String =
        rest("POST", "/rest/v1/rpc/$name", body = args.toString())

    /** Calls an edge function (`catch-up`, `catch-up-text`) with the user's token. */
    suspend fun function(name: String, body: String): String =
        ConsentGate.call(this, name) { rest("POST", "/functions/v1/$name", body = body) } // Plans: Muse Spark consent (data/ConsentGate.kt)

    // MARK: Plumbing

    /** Auth endpoints take plain JSON and the publishable key. */
    private suspend fun auth(path: String, body: JsonObject, bearer: String? = null): String {
        if (Previewing.active) throw ApiException.offline()
        val headers = linkedMapOf("apikey" to Config.PUBLISHABLE_KEY, "Content-Type" to "application/json")
        if (bearer != null) headers["Authorization"] = "Bearer $bearer"
        return check(transport.send(HttpRequest("POST", Config.SUPABASE_URL + path, headers, body.toString(), REST_TIMEOUT_MS)))
    }

    private fun check(response: HttpResponse): String {
        if (response.status in 200..299) return response.body
        throw ApiException.from(response.status, response.body)
    }

    private fun parseSession(body: String): AuthSession {
        val auth = KetchupJson.decodeFromString(AuthResponse.serializer(), body)
        return AuthSession(
            accessToken = auth.accessToken,
            refreshToken = auth.refreshToken,
            userId = auth.user.id,
            email = auth.user.email.orEmpty(),
            expiresAt = auth.expiresAt ?: (now() + (auth.expiresIn ?: 3600)),
        )
    }

    @Serializable
    private data class AuthResponse(
        @SerialName("access_token") val accessToken: String,
        @SerialName("refresh_token") val refreshToken: String,
        @SerialName("expires_at") val expiresAt: Long? = null,
        @SerialName("expires_in") val expiresIn: Long? = null,
        val user: User,
    ) {
        @Serializable
        data class User(val id: String, val email: String? = null)
    }

    companion object {
        const val REST_TIMEOUT_MS = 30_000
        /** Muse Spark can take 20 s or more on a long chat. */
        const val FUNCTION_TIMEOUT_MS = 90_000

        /** PostgREST filter syntax must survive: ".", ",", "(", ")", "*" and ":" stay literal. */
        internal fun queryString(query: List<Pair<String, String>>): String =
            if (query.isEmpty()) "" else query.joinToString("&", prefix = "?") { (k, v) -> "${encode(k)}=${encode(v)}" }

        private fun encode(s: String): String = URLEncoder.encode(s, "UTF-8")
            .replace("%2C", ",").replace("%28", "(").replace("%29", ")")
            .replace("%2A", "*").replace("%3A", ":").replace("+", "%20")
    }
}

/** The signed-in session. [expiresAt] is Unix seconds. */
@Serializable
data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val email: String,
    val expiresAt: Long,
) {
    fun isExpiringSoon(nowSeconds: Long): Boolean = nowSeconds > expiresAt - 60
}

/** Where the session lives between launches. */
interface SessionStore {
    fun load(): AuthSession?
    fun save(session: AuthSession?)
}

/**
 * The session in the app's private storage (MODE_PRIVATE, readable by this
 * app only; the manifest keeps it out of backups and device transfers).
 */
class PrefsSessionStore(context: Context) : SessionStore {
    private val prefs = context.applicationContext.getSharedPreferences("ketchup.session", Context.MODE_PRIVATE)

    override fun load(): AuthSession? = prefs.getString(KEY, null)?.let { raw ->
        runCatching { KetchupJson.decodeFromString(AuthSession.serializer(), raw) }.getOrNull()
    }

    override fun save(session: AuthSession?) {
        val edit = prefs.edit()
        if (session == null) edit.remove(KEY) else edit.putString(KEY, KetchupJson.encodeToString(AuthSession.serializer(), session))
        edit.apply()
    }

    private companion object {
        const val KEY = "session"
    }
}

/**
 * Offline preview mode (debug builds' `--es screen <name>`): while it's on,
 * nothing goes to the server, whatever a screen does.
 */
object Previewing {
    @Volatile
    var active: Boolean = false
}

/** A failed call. [status] and [code] (PostgREST's "PGRST202", "42501") are the server's, when it answered. */
class ApiException(message: String, val status: Int? = null, val code: String? = null) : IOException(message) {
    companion object {
        fun notSignedIn() = ApiException("Sign in to continue.")
        fun badResponse() = ApiException("The server sent something unexpected. Try again.")
        fun offline() = ApiException("Offline preview: nothing goes to the server.")

        /** Supabase error bodies vary: {message}, {msg}, {error_description} or {error}. */
        fun from(status: Int, body: String): ApiException {
            val json = runCatching { KetchupJson.parseToJsonElement(body).jsonObject }.getOrNull()
            val code = json?.get("code")?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
            for (key in listOf("message", "msg", "error_description", "error")) {
                val m = json?.get(key)?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
                if (!m.isNullOrEmpty()) return ApiException(friendly(m, status), status, code)
            }
            return ApiException("Request failed ($status). Try again.", status, code)
        }

        /** The server's words people actually hit, said plainly (iOS `Supabase.friendly`). */
        fun friendly(raw: String, status: Int): String {
            val lower = raw.lowercase()
            return when {
                "sending too fast" in lower -> "Slow down a little."
                "token has expired" in lower || ("otp" in lower && "invalid" in lower) ->
                    "That code didn't work. Check it or send a new one."
                "row-level security" in lower -> "That isn't allowed in this chat."
                status == 429 || "rate limit" in lower -> "Too many tries. Wait a minute and try again."
                else -> raw
            }
        }
    }
}

// MARK: Transport

/** One call as it goes out. */
class HttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
    val body: String?,
    val timeoutMs: Int,
)

class HttpResponse(val status: Int, val body: String)

/** Sends a request and returns the answer, whatever its status. The JVM tests swap in a fake. */
fun interface Transport {
    suspend fun send(request: HttpRequest): HttpResponse
}

/** The app's transport: one HttpURLConnection per call, on the IO dispatcher. */
class HttpTransport : Transport {
    override suspend fun send(request: HttpRequest): HttpResponse = withContext(Dispatchers.IO) {
        val conn = URL(request.url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = request.method
            conn.connectTimeout = 15_000
            conn.readTimeout = request.timeoutMs
            // Every answer is per user: never serve one from a cache.
            conn.useCaches = false
            request.headers.forEach { (name, value) -> conn.setRequestProperty(name, value) }
            request.body?.let { body ->
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = conn.responseCode
            val stream = if (status in 200..299) conn.inputStream else conn.errorStream
            HttpResponse(status, stream?.bufferedReader()?.use { it.readText() }.orEmpty())
        } catch (e: IOException) {
            // The kind of failure and the host only (never the path, query or body),
            // so a phone that can't reach Supabase says why in `adb logcat -s KetchupNet`.
            Log.w(TAG, "${request.method} ${conn.url.host} failed: ${e.javaClass.simpleName}: ${e.message}")
            throw e
        } finally {
            conn.disconnect()
        }
    }

    private companion object {
        const val TAG = "KetchupNet"
    }
}
