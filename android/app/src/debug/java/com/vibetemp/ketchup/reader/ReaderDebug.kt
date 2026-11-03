package com.vibetemp.ketchup.reader

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.content.ContextCompat
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.debug.PreviewData

/**
 * The reader's debug-only hooks (src/release has the empty twin).
 *
 * - The fixture thread: debug/ReaderFixtureActivity draws the synthetic
 *   Instagram thread, and its root carries [FIXTURE_ROOT], so the service
 *   treats that one screen of the app as an Instagram thread.
 * - The structure dump, for tuning the parser on the real apps later:
 *   long-press the bubble, or with the phone on adb,
 *
 *       adb shell am broadcast -a com.vibetemp.ketchup.debug.READER_DUMP -p com.vibetemp.ketchup
 *       adb logcat -s KetchupReaderDump
 *
 *   It logs class names, view ids, bounds, flags and text lengths, never
 *   text, from a copy that never held the text.
 * - After reading the fixture, how many messages match the fixture (counts).
 * - When Instagram or Snapchat is in front but no thread is spotted, which
 *   step failed (no composer, no list), with the composer's view id and its
 *   hint's length (`adb logcat -s KetchupReader`). Never text.
 */
internal object ReaderDebug {
    const val ENABLED = true
    const val ACTION_DUMP = "com.vibetemp.ketchup.debug.READER_DUMP"
    private const val FIXTURE_ROOT = "com.vibetemp.ketchup:id/reader_fixture_root"
    private const val FIXTURE_LIVE = "com.vibetemp.ketchup:id/reader_fixture_live"
    private const val TAG_DUMP = "KetchupReaderDump"
    private var receiver: BroadcastReceiver? = null

    /** Instagram, when [root] is the fixture thread; null for every other screen of the app. */
    fun fixtureSource(root: AccessibilityNodeInfo): TextSource? =
        if (root.findAccessibilityNodeInfosByViewId(FIXTURE_ROOT).isNotEmpty()) TextSource.INSTAGRAM else null

    /** The fixture as offline test data (no account needed), unless it was started with `--ez live true`. */
    fun fixtureIsOffline(root: AccessibilityNodeInfo): Boolean =
        root.findAccessibilityNodeInfosByViewId(FIXTURE_LIVE).isEmpty()

    private var lastNoThread = ""
    private var lastNoThreadAt = 0L

    /** Logs why [source]'s screen isn't a thread: when the reason changes, or every 10 s. */
    @Synchronized
    fun noThread(source: TextSource, diagnosis: String) {
        val line = "${source.id}: $diagnosis"
        val now = android.os.SystemClock.uptimeMillis()
        if (line == lastNoThread && now - lastNoThreadAt < 10_000) return
        lastNoThread = line
        lastNoThreadAt = now
        Log.i(KetchupReaderService.TAG, "no thread on $line")
    }

    fun onConnected(service: AccessibilityService) {
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val root = service.rootInActiveWindow
                if (root == null) Log.i(TAG_DUMP, "no window to dump") else Thread { dump(root) }.start()
            }
        }
        // Exported so adb's shell can send it; debug builds only.
        ContextCompat.registerReceiver(service, r, IntentFilter(ACTION_DUMP), ContextCompat.RECEIVER_EXPORTED)
        receiver = r
    }

    fun onDisconnected(service: AccessibilityService) {
        receiver?.let { runCatching { service.unregisterReceiver(it) } }
        receiver = null
    }

    fun dump(root: AccessibilityNodeInfo) {
        val lines = StructureDump.lines(NodeSnapshots.structure(root))
        Log.i(TAG_DUMP, "${root.packageName}: ${lines.size} nodes (class, id, bounds, flags, text lengths; no text)")
        lines.forEach { Log.i(TAG_DUMP, it) }
    }

    /** Counts only: how many of the read messages are the fixture's, in order. */
    fun checkFixture(context: Context, thread: TextThread) {
        val fixture = PreviewData.get(context).instagramThread.messages.takeLast(thread.messages.size)
        val same = thread.messages.zip(fixture).count { (read, expected) -> read.copy(at = null) == expected.copy(at = null) }
        Log.i(
            KetchupReaderService.TAG,
            "fixture check: $same of ${thread.messages.size} match the fixture's newest ${fixture.size}; " +
                "${thread.messages.count { it.at != null }} carry a time, ${thread.messages.count { it.quote != null }} a quote",
        )
    }
}
