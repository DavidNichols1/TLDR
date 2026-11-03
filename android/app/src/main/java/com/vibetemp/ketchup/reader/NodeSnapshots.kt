package com.vibetemp.ketchup.reader

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import java.util.IdentityHashMap

/**
 * Copies another app's live accessibility nodes into [SnapshotNode]s, so
 * the parser never holds the live ones across a scroll.
 *
 * Two kinds of copy. [structure] is what the service uses to spot a
 * thread without the person's tap, and the debug dump: no text and no
 * descriptions, only their lengths, plus an editable field's hint (to
 * know a "Message..." composer). [full] is only made after the person
 * taps a pick: it has the text. Neither ever copies what's typed in an
 * editable field (a draft).
 */
internal object NodeSnapshots {
    private const val MAX_NODES = 3000
    private const val MAX_DEPTH = 64

    fun structure(root: AccessibilityNodeInfo, live: IdentityHashMap<SnapshotNode, AccessibilityNodeInfo>? = null): SnapshotNode =
        copy(root, withText = false, live = live)

    fun full(root: AccessibilityNodeInfo): SnapshotNode = copy(root, withText = true, live = null)

    private fun copy(root: AccessibilityNodeInfo, withText: Boolean, live: IdentityHashMap<SnapshotNode, AccessibilityNodeInfo>?): SnapshotNode {
        var count = 0
        val rect = Rect()
        fun go(info: AccessibilityNodeInfo, depth: Int): SnapshotNode {
            count++
            info.getBoundsInScreen(rect)
            // Read now: the children below reuse the same Rect.
            val bounds = Bounds(rect.left, rect.top, rect.right, rect.bottom)
            val kids = ArrayList<SnapshotNode>(info.childCount)
            if (depth < MAX_DEPTH) {
                for (i in 0 until info.childCount) {
                    if (count >= MAX_NODES) break
                    val child = info.getChild(i) ?: continue
                    kids += go(child, depth + 1)
                }
            }
            val editable = info.isEditable
            val text = info.text
            val description = info.contentDescription
            // An empty field reports its hint as its text; a draft is never copied.
            val hint = if (editable) (info.hintText ?: if (info.isShowingHintText) text else null)?.toString() else null
            val node = SnapshotNode(
                bounds = bounds,
                className = info.className?.toString(),
                viewId = info.viewIdResourceName,
                text = if (withText && !editable) text?.toString() else null,
                contentDescription = if (withText) description?.toString() else null,
                hint = hint,
                isVisibleToUser = info.isVisibleToUser,
                isScrollable = info.isScrollable,
                canScrollBack = info.actionList.contains(AccessibilityAction.ACTION_SCROLL_BACKWARD),
                isEditable = editable,
                isClickable = info.isClickable,
                isLongClickable = info.isLongClickable,
                children = kids,
                textLength = if (editable) 0 else text?.length ?: 0,
                descriptionLength = description?.length ?: 0,
            )
            live?.put(node, info)
            return node
        }
        return go(root, 0)
    }
}
