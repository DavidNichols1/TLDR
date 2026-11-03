package com.vibetemp.ketchup.reader

import android.content.Context
import com.vibetemp.ketchup.data.KetchupApi

/**
 * The one thing the reader remembers: the person's own name as Snapchat
 * shows it, once a read learned it (a one-to-one chat named them, or they
 * answered "Which one is you?"). It lets a group chat tell their messages
 * apart. In private app storage on this phone only (the manifest keeps the
 * app out of backups), never sent anywhere, kept for the Ketchup account
 * that learned it, and forgotten when the person signs out of Ketchup
 * (AppModel.signOut).
 */
object ReaderMemory {
    private const val PREFS = "ketchup.reader"
    private const val SNAPCHAT_NAME = "snapchat_name"
    private const val SNAPCHAT_NAME_USER = "snapchat_name_user"

    /** The learned Snapchat name, if this Ketchup account learned one. */
    fun snapchatName(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val name = prefs.getString(SNAPCHAT_NAME, null) ?: return null
        val user = KetchupApi.get(context).session.value?.userId ?: return null
        return name.takeIf { prefs.getString(SNAPCHAT_NAME_USER, null) == user }
    }

    fun rememberSnapchatName(context: Context, name: String) {
        val user = KetchupApi.get(context).session.value?.userId ?: return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(SNAPCHAT_NAME, name.trim())
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
