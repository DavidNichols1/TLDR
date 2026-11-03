package com.vibetemp.ketchup.reader

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.ui.theme.KetchupTheme
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The reader's two windows over Instagram or Snapchat, both
 * TYPE_ACCESSIBILITY_OVERLAY (the accessibility grant covers them; no
 * "draw over other apps"): the bubble, draggable and kept above the
 * composer, and the panel it opens. Neither takes focus, and touches
 * outside them reach the app underneath.
 */
internal class ReaderOverlay(private val service: AccessibilityService, private val actions: Actions) {

    interface Actions {
        fun onBubbleTap()
        fun onBubbleLongPress()
        fun onPick(last: Int)
        fun onStop()
        fun onClosePanel()
        fun onOpenApp()

        /** The answer to "Which one is you?": a name, or null for "None of these". */
        fun onWho(name: String?)
    }

    private val wm = service.getSystemService(WindowManager::class.java)
    private val density = service.resources.displayMetrics.density
    private val owner = OverlayOwner()
    private var bubble: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var panel: View? = null
    private var panelState by mutableStateOf<PanelState>(PanelState.Pick)
    private var panelSource by mutableStateOf(TextSource.INSTAGRAM)

    /** Where the person dragged the bubble, if they did (kept while the thread stays open). */
    private var dragged: Pair<Int, Int>? = null
    private var thread: ThreadLayout.Found? = null

    /** When a touch outside last closed the panel: a tap on the bubble then shouldn't open it again. */
    private var closedOutsideAt = 0L

    val isBubbleShowing: Boolean get() = bubble != null
    val isPanelShowing: Boolean get() = panel != null

    /** The panel was just closed by the same touch that's now tapping the bubble. */
    val justClosed: Boolean get() = android.os.SystemClock.uptimeMillis() - closedOutsideAt < 500

    private fun px(dp: Int) = (dp * density).roundToInt()

    /** Shows the bubble over [found], or moves it to stay clear of the composer. */
    fun showBubble(found: ThreadLayout.Found, source: TextSource) {
        thread = found
        panelSource = source
        val size = px(BUBBLE_DP)
        val (x, y) = place(found, dragged)
        val existing = bubble
        val params = bubbleParams
        if (existing != null && params != null) {
            if (params.x != x || params.y != y) {
                params.x = x
                params.y = y
                runCatching { wm.updateViewLayout(existing, params) }
                if (panel != null) placePanel()
            }
            return
        }
        val lp = overlayParams(size, size).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }
        val view = BubbleFrame(service).apply {
            addView(compose { ReaderBubble() })
            contentDescription = service.getString(com.vibetemp.ketchup.R.string.reader_bubble_label)
        }
        own(view)
        if (runCatching { wm.addView(view, lp) }.isSuccess) {
            bubble = view
            bubbleParams = lp
        }
    }

    fun hideBubble() {
        hidePanel()
        bubble?.let { runCatching { wm.removeView(it) } }
        bubble = null
        bubbleParams = null
        dragged = null
        thread = null
    }

    fun showPanel(state: PanelState) {
        panelState = state
        if (panel != null) return
        val view = PanelFrame(service).apply {
            addView(
                compose {
                    ReaderPanel(
                        state = panelState,
                        source = panelSource,
                        onPick = actions::onPick,
                        onStop = actions::onStop,
                        onClose = actions::onClosePanel,
                        onOpenApp = actions::onOpenApp,
                        modifier = Modifier.padding(4.dp),
                        onWho = actions::onWho,
                    )
                },
            )
        }
        own(view)
        val lp = overlayParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT).apply {
            flags = flags or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
        }
        if (runCatching { wm.addView(view, lp) }.isSuccess) {
            panel = view
            placePanel()
        }
    }

    fun hidePanel() {
        panel?.let { runCatching { wm.removeView(it) } }
        panel = null
    }

    fun destroy() {
        hideBubble()
        owner.destroy()
    }

    /** The bubble's spot: the person's if they dragged it, else bottom right; always above the composer. */
    private fun place(found: ThreadLayout.Found, wanted: Pair<Int, Int>?): Pair<Int, Int> {
        val screen = screenSize()
        val size = px(BUBBLE_DP)
        val margin = px(12)
        val lowest = found.composer.top - size - px(14)
        val highest = found.list.top + margin
        val x = (wanted?.first ?: (screen.width() - size - margin)).coerceIn(margin, screen.width() - size - margin)
        val y = (wanted?.second ?: lowest).coerceIn(highest, maxOf(highest, lowest))
        return x to y
    }

    /** The panel sits above the bubble, right edges lined up, or under it when there's no room. */
    private fun placePanel() {
        val view = panel ?: return
        val lp = view.layoutParams as? WindowManager.LayoutParams ?: return
        val b = bubbleParams
        val screen = screenSize()
        val size = px(BUBBLE_DP)
        val margin = px(8)
        val bubbleTop = b?.y ?: (screen.height() / 2)
        val bubbleRight = (b?.x ?: (screen.width() - size)) + size
        lp.x = (screen.width() - bubbleRight).coerceAtLeast(margin)
        if (bubbleTop > px(320)) {
            lp.gravity = Gravity.BOTTOM or Gravity.END
            lp.y = screen.height() - bubbleTop + margin
        } else {
            lp.gravity = Gravity.TOP or Gravity.END
            lp.y = bubbleTop + size + margin
        }
        lp.width = minOf(screen.width() - margin * 2, px(368))
        runCatching { wm.updateViewLayout(view, lp) }
    }

    private fun screenSize(): Rect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        wm.currentWindowMetrics.bounds
    } else {
        val m = service.resources.displayMetrics
        Rect(0, 0, m.widthPixels, m.heightPixels)
    }

    private fun overlayParams(width: Int, height: Int) = WindowManager.LayoutParams(
        width,
        height,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    )

    private fun compose(content: @androidx.compose.runtime.Composable () -> Unit) = ComposeView(service).apply {
        setContent { KetchupTheme { content() } }
    }

    private fun own(view: View) {
        view.setViewTreeLifecycleOwner(owner)
        view.setViewTreeSavedStateRegistryOwner(owner)
    }

    /**
     * The bubble's touch handling: a tap opens the panel, a drag moves the
     * bubble, a long press is the debug structure dump. TalkBack's double
     * tap arrives as a click.
     */
    @SuppressLint("ViewConstructor")
    private inner class BubbleFrame(context: Context) : FrameLayout(context) {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private val handler = Handler(Looper.getMainLooper())
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var moving = false
        private var longPressed = false
        private val longPress = Runnable {
            longPressed = true
            actions.onBubbleLongPress()
        }

        init {
            isClickable = true
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = true

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            val params = bubbleParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moving = false
                    longPressed = false
                    handler.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!moving && (abs(dx) > slop || abs(dy) > slop)) {
                        moving = true
                        handler.removeCallbacks(longPress)
                    }
                    if (moving) {
                        val found = thread ?: return true
                        val (x, y) = place(found, (startX + dx.roundToInt()) to (startY + dy.roundToInt()))
                        params.x = x
                        params.y = y
                        runCatching { wm.updateViewLayout(this, params) }
                        if (panel != null) placePanel()
                    }
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPress)
                    if (moving) {
                        dragged = params.x to params.y
                    } else if (!longPressed) {
                        performClick()
                    }
                }
                MotionEvent.ACTION_CANCEL -> handler.removeCallbacks(longPress)
            }
            return true
        }

        override fun performClick(): Boolean {
            super.performClick()
            actions.onBubbleTap()
            return true
        }
    }

    /** The panel's window: a touch outside it closes it, unless it's reading. */
    @SuppressLint("ViewConstructor")
    private inner class PanelFrame(context: Context) : FrameLayout(context) {
        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_OUTSIDE && panelState !is PanelState.Reading) {
                closedOutsideAt = android.os.SystemClock.uptimeMillis()
                actions.onClosePanel()
                return true
            }
            return super.onTouchEvent(event)
        }
    }

    /** A lifecycle for Compose in windows that belong to no activity: resumed while the service runs. */
    private class OverlayOwner : SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val saved = SavedStateRegistryController.create(this)
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry

        init {
            saved.performAttach()
            saved.performRestore(null)
            registry.currentState = Lifecycle.State.RESUMED
        }

        fun destroy() {
            registry.currentState = Lifecycle.State.DESTROYED
        }
    }
}
