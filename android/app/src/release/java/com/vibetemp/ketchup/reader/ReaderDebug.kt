package com.vibetemp.ketchup.reader

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.view.accessibility.AccessibilityNodeInfo
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread

/** Release builds have no fixture thread and no structure dump (the debug twin is in src/debug). */
@Suppress("UNUSED_PARAMETER")
internal object ReaderDebug {
    const val ENABLED = false

    fun fixtureSource(root: AccessibilityNodeInfo): TextSource? = null

    fun fixtureIsOffline(root: AccessibilityNodeInfo): Boolean = false

    fun noThread(source: TextSource, diagnosis: String) = Unit

    fun onConnected(service: AccessibilityService) = Unit

    fun onDisconnected(service: AccessibilityService) = Unit

    fun dump(root: AccessibilityNodeInfo) = Unit

    fun checkFixture(context: Context, thread: TextThread) = Unit
}
