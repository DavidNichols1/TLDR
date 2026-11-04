package com.vibetemp.ketchup.data

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.util.concurrent.ConcurrentHashMap

/**
 * The Terms of Service and Privacy Policy (migration 0011). Everyone in the
 * app has agreed to [Config.TERMS_VERSION] or a newer version. The sign-in
 * screen says continuing agrees to them, so every sign-in records it
 * ([signedIn]); someone whose session was already on the phone is checked
 * once a launch ([needsAgreement]), and whoever hasn't agreed sees the terms
 * screen before the app (ui/auth/TermsScreen.kt), whose Agree is [agree].
 *
 * It never traps anyone: a check that fails (offline, or a server from
 * before 0011, where terms_acceptances and accept_terms answer 404) lets them
 * in this time, and the next launch asks again. Versions are the dates the
 * terms were published ("2026-11-04"), so they compare as text. AppModel
 * keeps one for the app's process.
 */
class TermsGate(
    private val client: SupabaseClient,
    private val store: TermsStore,
    private val version: String = Config.TERMS_VERSION,
) {
    /** Who needs no terms screen while the app runs: they agreed here, or a check failed and let them in. */
    private val cleared: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /**
     * Whether [userId] sees the terms screen before the app. An acceptance of
     * this version or newer kept on this phone answers with no network;
     * otherwise their row on the server decides, and a current one is kept.
     * Never throws (cancellation aside): trouble lets them in.
     */
    suspend fun needsAgreement(userId: String): Boolean {
        if (userId in cleared) return false
        if (current(store.version(userId))) {
            cleared += userId
            return false
        }
        val latest = try {
            val body = client.select("terms_acceptances", "select" to "version,accepted_at", "user_id" to "eq.$userId")
            KetchupJson.decodeFromString(ListSerializer(TermsAcceptance.serializer()), body).maxOfOrNull { it.version }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Offline, or no terms_acceptances table yet: in this time, and the next launch asks again.
            cleared += userId
            return false
        }
        // A sign-in that agreed while this was asking wins.
        if (userId in cleared) return false
        if (latest != null && current(latest)) {
            store.keep(userId, latest)
            cleared += userId
            return false
        }
        return true
    }

    /**
     * Right after a sign-in (the emailed code or a password), which agrees to
     * the terms. Marks [userId] agreed before its first suspension, so the
     * root's own check can't show the terms screen while this records it
     * (start it undispatched, straight from the sign-in), then calls
     * accept_terms. If that fails, the usual check decides. Returns whether
     * the terms screen is needed after all.
     */
    suspend fun signedIn(userId: String): Boolean {
        cleared += userId
        return try {
            record(userId)
            false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            cleared -= userId
            needsAgreement(userId)
        }
    }

    /** The terms screen's Agree. Throws ([ApiException], or an IOException offline) when it couldn't be saved. */
    suspend fun agree(userId: String) {
        record(userId)
        cleared += userId
    }

    /** accept_terms writes the caller's own row at the server's time; this phone keeps the version too. */
    private suspend fun record(userId: String) {
        client.rpc("accept_terms", obj("p_version" to version))
        store.keep(userId, version)
    }

    private fun current(saved: String?): Boolean = saved != null && saved >= version
}

/** Where this phone keeps the version of the terms each person agreed to. */
interface TermsStore {
    fun version(userId: String): String?
    fun keep(userId: String, version: String)
}

/**
 * In the app's own preferences (`ketchup.app`, key `termsAccepted-<user id>`):
 * private to the app, and out of backups and device transfers like the rest.
 */
class PrefsTermsStore(context: Context) : TermsStore {
    private val prefs = context.applicationContext.getSharedPreferences("ketchup.app", Context.MODE_PRIVATE)

    override fun version(userId: String): String? = prefs.getString(key(userId), null)

    override fun keep(userId: String, version: String) {
        prefs.edit().putString(key(userId), version).apply()
    }

    private fun key(userId: String) = "termsAccepted-$userId"
}

/** A terms_acceptances row, as PostgREST sends it. */
@Serializable
internal data class TermsAcceptance(
    val version: String,
    @SerialName("accepted_at") val acceptedAt: String? = null,
)
