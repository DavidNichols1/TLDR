package com.vibetemp.ketchup.reader

import kotlin.math.max
import kotlin.math.min

/**
 * A rectangle in screen pixels: Android's Rect without Android, so the
 * parser runs and is tested on the JVM.
 */
data class Bounds(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
    val centerX: Float get() = (left + right) / 2f
    val isEmpty: Boolean get() = width <= 0 || height <= 0

    fun intersects(other: Bounds): Boolean =
        left < other.right && other.left < right && top < other.bottom && other.top < bottom

    fun clippedTo(other: Bounds): Bounds =
        Bounds(max(left, other.left), max(top, other.top), min(right, other.right), min(bottom, other.bottom))

    override fun toString(): String = "[$left,$top][$right,$bottom]"
}

/**
 * One node of another app's screen, as the reader sees it: Android's
 * AccessibilityNodeInfo cut down to what the parser needs. Instagram's view
 * ids are obfuscated and change between releases, so the parser goes by
 * visible text, content descriptions and geometry; [viewId] is only for the
 * debug structure dump.
 */
interface ReaderNode {
    val className: String?
    val viewId: String?

    /** What it says. Null for an editable field (a draft is never read) and in a structure-only snapshot. */
    val text: String?
    val contentDescription: String?

    /** An editable field's hint ("Message..."). */
    val hint: String?

    /** In screen pixels, clipped to what's on screen (Android's getBoundsInScreen). */
    val bounds: Bounds
    val isVisibleToUser: Boolean
    val isScrollable: Boolean

    /** It offers ACTION_SCROLL_BACKWARD right now (it isn't at the top). */
    val canScrollBack: Boolean
    val isEditable: Boolean
    val isClickable: Boolean
    val isLongClickable: Boolean
    val children: List<ReaderNode>
}

/**
 * A copy of one node, made the moment the reader looks, so nothing holds
 * on to the other app's live nodes. Tests build trees of these by hand.
 * In a structure-only copy (what the service uses to spot a thread, and
 * the debug dump) [text] and [contentDescription] are null and only their
 * lengths are kept.
 */
data class SnapshotNode(
    override val bounds: Bounds,
    override val className: String? = null,
    override val viewId: String? = null,
    override val text: String? = null,
    override val contentDescription: String? = null,
    override val hint: String? = null,
    override val isVisibleToUser: Boolean = true,
    override val isScrollable: Boolean = false,
    override val canScrollBack: Boolean = false,
    override val isEditable: Boolean = false,
    override val isClickable: Boolean = false,
    override val isLongClickable: Boolean = false,
    override val children: List<SnapshotNode> = emptyList(),
    val textLength: Int = text?.length ?: 0,
    val descriptionLength: Int = contentDescription?.length ?: 0,
) : ReaderNode {
    // Identity, not structure: two equal-looking nodes are still two nodes,
    // and hashing a whole subtree on every lookup would be slow.
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/** Every node under (and including) this one, depth first. */
internal fun ReaderNode.walkTree(visit: (node: ReaderNode, depth: Int) -> Unit) {
    fun go(node: ReaderNode, depth: Int) {
        visit(node, depth)
        node.children.forEach { go(it, depth + 1) }
    }
    go(this, 0)
}
