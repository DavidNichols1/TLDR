package com.vibetemp.ketchup.reader

import android.content.Context
import com.vibetemp.ketchup.data.KetchupApi

/**
 * The person's name on Snapchat, which they type once (SnapchatNameActivity)
 * so the reader can tell their messages from their friends': Snapchat
 * draws everyone's on the left, under the sender's name. The only thing the
 * reader keeps. In private app storage on this phone (the manifest keeps
 * the app out of backups), never sent anywhere, kept for the Ketchup
 * account that saved it, and forgotten when the person signs out of
 * Ketchup (AppModel.signOut).
 */
object ReaderMemory {
    private const val PREFS = "ketchup.reader"
    private const val SNAPCHAT_NAME = "snapchat_name"
    private const val SNAPCHAT_NAME_USER = "snapchat_name_user"

    /** The saved name, or null when this Ketchup account hasn't saved one. */
    fun snapchatName(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val name = prefs.getString(SNAPCHAT_NAME, null)?.takeIf(String::isNotBlank) ?: return null
        val user = KetchupApi.get(context).session.value?.userId.orEmpty()
        return name.takeIf { prefs.getString(SNAPCHAT_NAME_USER, "").orEmpty() == user }
    }

    fun setSnapchatName(context: Context, name: String) {
        val user = KetchupApi.get(context).session.value?.userId.orEmpty()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(SNAPCHAT_NAME, name.trim().replace(Regex("\\s+"), " "))
            .putString(SNAPCHAT_NAME_USER, user)
            .apply()
    }

    fun forget(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(SNAPCHAT_NAME)
            .remove(SNAPCHAT_NAME_USER)
            .apply()
    }
}
