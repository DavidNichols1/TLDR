package com.vibetemp.ketchup.reader

/**
 * The screen's structure as log lines, for tuning the parser on the real
 * apps later (debug builds only): class names, view ids, bounds, flags,
 * and text as lengths only, never the text itself. Feed it a
 * structure-only snapshot, which never held the text to begin with.
 *
 *     ListView #reader_fixture_list [0,236][1080,2148] scroll back kids=12
 *       LinearLayout [0,240][1080,420] click long
 *         TextView [42,250][310,300] t=14
 *
 * Flags: `scroll` scrolls, `back` can scroll toward older messages,
 * `edit` editable, `click`/`long` tappable or long-pressable, `hidden`
 * not visible to the user. `t=`, `d=` and `h=` are the lengths of the
 * text, description and hint.
 */
object StructureDump {
    fun lines(root: ReaderNode, maxLines: Int = 700): List<String> {
        val out = mutableListOf<String>()
        root.walkTree { node, depth ->
            if (out.size >= maxLines) return@walkTree
            out += line(node, depth)
        }
        if (out.size >= maxLines) out += "(stopped at $maxLines lines)"
        return out
    }

    fun line(node: ReaderNode, depth: Int): String = buildString {
        append("  ".repeat(depth.coerceAtMost(40)))
        append(node.className?.substringAfterLast('.') ?: "?")
        node.viewId?.let { append(" #").append(it.substringAfter(":id/")) }
        append(' ').append(node.bounds)
        if (node.isScrollable) append(" scroll")
        if (node.canScrollBack) append(" back")
        if (node.isEditable) append(" edit")
        if (node.isClickable) append(" click")
        if (node.isLongClickable) append(" long")
        if (!node.isVisibleToUser) append(" hidden")
        val textLength = (node as? SnapshotNode)?.textLength ?: node.text?.length ?: 0
        val descriptionLength = (node as? SnapshotNode)?.descriptionLength ?: node.contentDescription?.length ?: 0
        if (textLength > 0) append(" t=").append(textLength)
        if (descriptionLength > 0) append(" d=").append(descriptionLength)
        node.hint?.let { append(" h=").append(it.length) }
        if (node.children.size > 1) append(" kids=").append(node.children.size)
    }
}
