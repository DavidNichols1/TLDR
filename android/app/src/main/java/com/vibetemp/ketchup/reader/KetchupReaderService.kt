package com.vibetemp.ketchup.reader

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.KetchupApi
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.data.TextThread
import com.vibetemp.ketchup.ui.brief.BriefActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.IdentityHashMap

/**
 * Reads the DM thread open in the official Instagram or Snapchat app, when
 * the person asks, into a [TextThread], and opens
 * `BriefActivity.start(this, thread)`. Limited to those two apps by
 * res/xml/reader_service.xml (debug builds add the app's own fixture
 * thread, see ReaderDebug). The reader slice owns this package.
 *
 * - It spots an open thread by its shape (a message list over a
 *   "Message..." composer) from a structure-only copy of the screen: no
 *   message text, no names. Then a small Ketchup bubble floats over it.
 * - It reads only on a tap: the bubble opens a panel, the person picks the
 *   last 30, 80 or 120 messages, and only then does it copy text, scrolling
 *   back with ACTION_SCROLL_BACKWARD and putting the thread back after.
 * - It stores nothing: the thread goes to BriefActivity in memory. It logs
 *   counts only, never message text or names.
 */
class KetchupReaderService : AccessibilityService(), ReaderOverlay.Actions {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var overlay: ReaderOverlay? = null
    private var checkJob: Job? = null
    private var watchJob: Job? = null
    private var readJob: Job? = null

    /** The person tapped Stop: the reader puts the thread back and hands nothing over. */
    @Volatile
    private var stopRequested = false

    /** The thread the bubble is up for. */
    private var current: OnScreen? = null

    /** Events from the window being read, for waiting until a scroll settles. */
    private var readingWindow = NO_WINDOW
    private var changes = 0L
    private var lastChangeAt = 0L

    private class OnScreen(val source: TextSource, val layout: ThreadLayout.Found, val windowId: Int, val fixture: Boolean)

    override fun onServiceConnected() {
        super.onServiceConnected()
        overlay = ReaderOverlay(this, this)
        ReaderDebug.onConnected(this)
        Log.i(TAG, "connected")
        scheduleCheck(0)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        if (readingWindow != NO_WINDOW && event.windowId == readingWindow) {
            changes++
            lastChangeAt = SystemClock.uptimeMillis()
        }
        if (readJob?.isActive == true) return
        scheduleCheck(CHECK_DELAY_MS)
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        shutDown()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        shutDown()
        super.onDestroy()
    }

    private fun shutDown() {
        if (overlay == null) return
        ReaderDebug.onDisconnected(this)
        scope.cancel()
        overlay?.destroy()
        overlay = null
        current = null
        Log.i(TAG, "disconnected")
    }

    // MARK: Spotting a thread

    /** Looks again after the screen settles (events come in bursts). */
    private fun scheduleCheck(delayMs: Long) {
        checkJob?.cancel()
        checkJob = scope.launch {
            delay(delayMs)
            val found = withContext(Dispatchers.Default) { runCatching { threadOnScreen() }.getOrNull() }
            show(found)
        }
    }

    private fun show(found: OnScreen?) {
        val overlay = overlay ?: return
        if (readJob?.isActive == true) return
        current = found
        if (found == null) {
            overlay.hideBubble()
            watchJob?.cancel()
            return
        }
        overlay.showBubble(found.layout, found.source)
        // Back from "Your name on Snapchat" with a name saved: the panel opens, ready to read.
        if (pickAfterName && found.source == TextSource.SNAPCHAT && !overlay.isPanelShowing && ReaderMemory.snapchatName(this) != null) {
            pickAfterName = false
            overlay.showPanel(PanelState.Pick)
        }
        watch()
    }

    /**
     * While the bubble is up, checks every second that the thread's app is
     * still in front: leaving for another app sends this service no event
     * (it only hears from Instagram and Snapchat).
     */
    private fun watch() {
        if (watchJob?.isActive == true) return
        watchJob = scope.launch {
            while (isActive && current != null) {
                delay(WATCH_MS)
                if (readJob?.isActive == true) continue
                val stillThere = withContext(Dispatchers.Default) {
                    runCatching { rootInActiveWindow?.let { sourceOf(it) } }.getOrNull() != null
                }
                if (!stillThere) show(null)
            }
        }
    }

    /** The open thread, from a structure-only copy of the screen (no text, no names). */
    private fun threadOnScreen(): OnScreen? {
        val root = rootInActiveWindow ?: return null
        val source = sourceOf(root) ?: return null
        val structure = NodeSnapshots.structure(root)
        val layout = ThreadLayout.detect(structure, source)
        if (layout == null) {
            // Debug builds: which step failed, with view ids and hint lengths only.
            if (ReaderDebug.ENABLED) ReaderDebug.noThread(source, ThreadLayout.diagnose(structure, source))
            return null
        }
        val fixture = root.packageName?.toString() == packageName && ReaderDebug.fixtureIsOffline(root)
        return OnScreen(source, layout, root.windowId, fixture)
    }

    /** Which app [root] is: Instagram, Snapchat, or (debug builds) the fixture thread. */
    private fun sourceOf(root: AccessibilityNodeInfo): TextSource? {
        val pkg = root.packageName?.toString() ?: return null
        if (pkg == packageName) return ReaderDebug.fixtureSource(root)
        return TextSource.forPackage(pkg)
    }

    // MARK: The bubble and the panel

    override fun onBubbleTap() {
        val overlay = overlay ?: return
        if (overlay.isPanelShowing) {
            if (readJob?.isActive != true) overlay.hidePanel()
            return
        }
        if (overlay.justClosed) return
        val on = current ?: return
        val state = when {
            !ReaderSetup.hasConsent(this) -> PanelState.Setup
            // The debug fixture is offline: it needs no account.
            !on.fixture && KetchupApi.get(this).session.value == null -> PanelState.SignIn
            else -> PanelState.Pick
        }
        // Snapchat draws everyone's messages on the left: the first time, ask the person's name there.
        if (state == PanelState.Pick && on.source == TextSource.SNAPCHAT && ReaderMemory.snapchatName(this) == null) {
            pickAfterName = true
            SnapchatNameActivity.start(this)
            return
        }
        overlay.showPanel(state)
    }

    /** "Your name on Snapchat" is open: when it saves, the panel opens back in Snapchat. */
    @Volatile
    private var pickAfterName = false

    override fun onBubbleLongPress() {
        // Debug builds: log the screen's structure (class names, ids, bounds, lengths; never text).
        if (!ReaderDebug.ENABLED) return
        scope.launch(Dispatchers.Default) { rootInActiveWindow?.let { ReaderDebug.dump(it) } }
    }

    override fun onClosePanel() {
        if (readJob?.isActive == true) return
        overlay?.hidePanel()
    }

    override fun onOpenApp() {
        overlay?.hidePanel()
        ReaderSetup.openKetchup(this)
    }

    override fun onStop() {
        stopRequested = true
    }

    override fun onPick(last: Int) {
        if (readJob?.isActive == true) return
        val on = current ?: return
        val overlay = overlay ?: return
        overlay.showPanel(PanelState.Reading(ReadProgress(0, last)))
        readingWindow = on.windowId
        stopRequested = false
        readJob = scope.launch {
            try {
                val snapchatName = if (on.source == TextSource.SNAPCHAT) ReaderMemory.snapchatName(this@KetchupReaderService) else null
                val reader = ThreadReader(on.source, LiveScreen(on.windowId, on.source), snapchatName = snapchatName)
                val result = reader.read(last, { overlay.showPanel(PanelState.Reading(it)) }, { stopRequested })
                when (result) {
                    is ThreadReader.Result.Read -> handOff(result.thread, on)
                    ThreadReader.Result.NotAThread -> overlay.showPanel(PanelState.Problem(R.string.reader_problem_not_thread, null))
                    ThreadReader.Result.NothingFound -> overlay.showPanel(PanelState.Problem(R.string.reader_problem_nothing, last))
                    ThreadReader.Result.Stopped -> {
                        Log.i(TAG, "read stopped")
                        overlay.hidePanel()
                    }
                }
            } catch (e: CancellationException) {
                Log.i(TAG, "read stopped")
                overlay.hidePanel()
                throw e
            } catch (e: RuntimeException) {
                // The other app changed under us (a node went away mid-read). Its name only, never content.
                Log.w(TAG, "read failed: ${e.javaClass.simpleName}")
                overlay.showPanel(PanelState.Problem(R.string.reader_problem_unreadable, last))
            } finally {
                readingWindow = NO_WINDOW
                scheduleCheck(CHECK_DELAY_MS)
            }
        }
    }

    private fun handOff(thread: TextThread, on: OnScreen) {
        val s = thread.stats
        // Counts only.
        Log.i(
            TAG,
            "read ${thread.source.id}: ${thread.messages.size} kept (${thread.messages.count { it.isMine }} mine, " +
                "${thread.messages.count { it.quote != null }} replies), found ${s?.found}, steps ${s?.steps}, " +
                "loads ${s?.scrolls}, stop ${s?.stop}, dupes ${s?.dupes}, ${s?.ms} ms",
        )
        if (on.fixture) ReaderDebug.checkFixture(this, thread)
        overlay?.hidePanel()
        BriefActivity.start(this, thread)
    }

    // MARK: The screen, for the reader

    /** The thread's window over the accessibility API. Text is only copied in [snapshot], after a tap. */
    private inner class LiveScreen(private val windowId: Int, private val source: TextSource) : ReaderScreen {
        override val density: Float = resources.displayMetrics.density

        private fun root(): AccessibilityNodeInfo? = rootInActiveWindow?.takeIf { it.windowId == windowId }

        override suspend fun snapshot(): ReaderNode? = withContext(Dispatchers.Default) { root()?.let(NodeSnapshots::full) }

        override suspend fun scrollBack(): Boolean = scroll(AccessibilityAction.ACTION_SCROLL_BACKWARD)

        override suspend fun scrollForward(): Boolean = scroll(AccessibilityAction.ACTION_SCROLL_FORWARD)

        /** Finds the thread's list again (the old node may be stale) and scrolls it. */
        private suspend fun scroll(action: AccessibilityAction): Boolean = withContext(Dispatchers.Default) {
            val root = root() ?: return@withContext false
            val live = IdentityHashMap<SnapshotNode, AccessibilityNodeInfo>()
            val snapshot = NodeSnapshots.structure(root, live)
            val composer = ThreadLayout.findComposer(snapshot, source)
            val list = ThreadLayout.findList(snapshot, composer?.bounds, source) as? SnapshotNode ?: return@withContext false
            val node = live[list] ?: return@withContext false
            if (!node.actionList.contains(action)) return@withContext false
            node.performAction(action.id)
        }

        override suspend fun awaitChange(timeoutMs: Long): Boolean {
            val started = SystemClock.uptimeMillis()
            val before = changes
            while (changes == before && SystemClock.uptimeMillis() - started < timeoutMs) delay(POLL_MS)
            if (changes == before) return false
            while (SystemClock.uptimeMillis() - lastChangeAt < QUIET_MS && SystemClock.uptimeMillis() - started < timeoutMs) delay(POLL_MS)
            return true
        }

        override suspend fun pause(ms: Long) = delay(ms)

        override fun clock(): Long = SystemClock.uptimeMillis()
    }

    companion object {
        const val TAG = "KetchupReader"
        private const val NO_WINDOW = -1
        private const val CHECK_DELAY_MS = 250L
        private const val WATCH_MS = 1_000L
        private const val POLL_MS = 40L

        /** The list counts as settled after this long without an event. */
        private const val QUIET_MS = 220L
    }
}
