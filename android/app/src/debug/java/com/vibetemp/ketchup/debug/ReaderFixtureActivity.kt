package com.vibetemp.ketchup.debug

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.Space
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.Previewing
import com.vibetemp.ketchup.data.TextMessage
import com.vibetemp.ketchup.data.TextThread
import kotlin.math.roundToInt

/**
 * Debug only: the synthetic Instagram thread ("Breck Crew 🎿", made-up
 * people, debug/assets/fixtures/instagram-thread.json) drawn the way
 * Instagram's app draws a DM thread, in plain Android views, so the reader
 * service can be tried on an emulator without Instagram:
 *
 *     adb shell am start -n com.vibetemp.ketchup/.debug.ReaderFixtureActivity
 *
 * A header with the title and call buttons, a ListView that only holds the
 * rows on screen (like Instagram's RecyclerView), their bubbles on the left
 * with name labels over each run and an avatar at its end, mine on the
 * right, long-pressable bubbles, a reply with its quote, photos, a voice
 * note, time stamps, a notice, a reaction and "Seen", and a "Message..."
 * composer. The service treats only this screen as a thread (its root's
 * id, ReaderDebug). Offline: nothing it leads to reaches the server, and
 * the reader skips its sign-in check here. With `--ez live true` it keeps
 * that check, so the panel's "Sign in to Cetchup first" shows when signed out.
 */
class ReaderFixtureActivity : Activity() {

    private sealed interface Row {
        data class Notice(val text: String) : Row
        data class Message(val message: TextMessage, val label: Boolean, val avatar: Boolean, val reaction: String?) : Row
        data object Seen : Row
    }

    private val density get() = resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).roundToInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Previewing.active = true
        val thread = PreviewData.get(this).instagramThread
        setContentView(screen(thread, rows(thread), live = intent.getBooleanExtra(EXTRA_LIVE, false)))
    }

    /** The fixture's messages as Instagram's rows, with a few time stamps and the extras it draws. */
    private fun rows(thread: TextThread): List<Row> {
        val stamps = mapOf(0 to "Sat 7:42 PM", 34 to "Yesterday 9:15 AM", 62 to "Today 8:03 AM")
        val m = thread.messages
        val out = mutableListOf<Row>(Row.Notice("Maya named the group ${thread.title}"))
        m.forEachIndexed { i, msg ->
            stamps[i]?.let { out += Row.Notice(it) }
            val prev = m.getOrNull(i - 1)
            val next = m.getOrNull(i + 1)
            val first = prev == null || prev.isMine || prev.sender != msg.sender || i in stamps
            val last = next == null || next.isMine || next.sender != msg.sender || (i + 1) in stamps
            out += Row.Message(msg, label = !msg.isMine && first && msg.quote == null, avatar = !msg.isMine && last, reaction = if (i == 19) "❤️" else null)
        }
        out += Row.Seen
        return out
    }

    private fun screen(thread: TextThread, rows: List<Row>, live: Boolean): View {
        val root = LinearLayout(this).apply {
            id = R.id.reader_fixture_root
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(WHITE)
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }
        root.addView(
            header(thread.title).apply { if (live) id = R.id.reader_fixture_live },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64)),
        )
        val list = ListView(this).apply {
            id = R.id.reader_fixture_list
            divider = null
            dividerHeight = 0
            isStackFromBottom = true
            transcriptMode = AbsListView.TRANSCRIPT_MODE_NORMAL
            selector = GradientDrawable().apply { setColor(Color.TRANSPARENT) }
            overScrollMode = View.OVER_SCROLL_NEVER
            adapter = RowAdapter(rows)
        }
        root.addView(list, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(composer(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)).apply { setMargins(dp(10), dp(6), dp(10), dp(8)) })
        list.setSelection(rows.size - 1)
        return root
    }

    private fun header(title: String): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(8), 0, dp(8), 0)
        addView(icon("Back", dp(28), GRAY_LINE), square(dp(40)))
        addView(oval(PURPLE, dp(36)).apply { contentDescription = null }, square(dp(36)).apply { marginStart = dp(4) })
        addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(10), 0, 0, 0)
                addView(text(title, 16f, BLACK).apply { setTypeface(typeface, Typeface.BOLD) })
                addView(text("Maya, Jordan, Priya and Sam", 12f, GRAY_TEXT))
            },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        addView(icon("Audio call", dp(26), BLACK), square(dp(40)))
        addView(icon("Video call", dp(26), BLACK), square(dp(40)))
    }

    private fun composer(): View = LinearLayout(this).apply {
        id = R.id.reader_fixture_composer
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = rounded(GRAY_BUBBLE, dp(28))
        setPadding(dp(6), 0, dp(10), 0)
        addView(oval(BLUE, dp(40)).apply { contentDescription = "Camera" }, square(dp(40)))
        addView(
            EditText(context).apply {
                hint = "Message..."
                background = null
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPadding(dp(10), 0, dp(10), 0)
            },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f),
        )
        addView(icon("Voice clip", dp(24), BLACK), square(dp(36)))
        addView(icon("Gallery", dp(24), BLACK), square(dp(36)))
    }

    private inner class RowAdapter(private val rows: List<Row>) : BaseAdapter() {
        override fun getCount() = rows.size
        override fun getItem(position: Int): Any = rows[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun isEnabled(position: Int) = false
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View = when (val row = rows[position]) {
            is Row.Notice -> FrameLayout(this@ReaderFixtureActivity).apply {
                setPadding(0, dp(14), 0, dp(10))
                addView(text(row.text, 12f, GRAY_TEXT), FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
            }
            Row.Seen -> FrameLayout(this@ReaderFixtureActivity).apply {
                setPadding(0, dp(2), dp(16), dp(10))
                addView(text("Seen", 11f, GRAY_TEXT), FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.END))
            }
            is Row.Message -> message(row)
        }
    }

    /** One message's row: label, quote, avatar, bubble and reaction, the way Instagram stacks them. */
    private fun message(row: Row.Message): View {
        val m = row.message
        val mine = m.isMine
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = if (mine) Gravity.END else Gravity.START
            setPadding(if (mine) dp(64) else dp(10), dp(2), if (mine) dp(12) else dp(64), dp(2))
        }
        val indent = dp(28 + 8)
        if (row.label) {
            column.addView(text(m.sender, 12f, GRAY_TEXT), wrap().apply { marginStart = indent + dp(12); bottomMargin = dp(2); topMargin = dp(6) })
        }
        val quote = m.quote
        if (quote != null) {
            val header = "${m.sender} replied to ${quote.sender}"
            column.addView(text(header, 11f, GRAY_TEXT), wrap().apply { marginStart = indent + dp(12); topMargin = dp(8) })
            val quoted = FrameLayout(this).apply {
                background = rounded(GRAY_QUOTE, dp(16))
                setPadding(dp(12), dp(8), dp(12), dp(8))
                isClickable = true
                setOnClickListener { }
                addView(text(quote.text.orEmpty(), 13f, GRAY_TEXT).apply { maxWidth = dp(240) })
            }
            column.addView(quoted, wrap().apply { marginStart = indent; topMargin = dp(2); bottomMargin = dp(2) })
        }
        val line = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        if (!mine) {
            val slot = if (row.avatar) {
                oval(colorFor(m.sender), dp(28)).apply { contentDescription = null }
            } else {
                Space(this)
            }
            line.addView(slot, square(dp(28)).apply { marginEnd = dp(8) })
        }
        line.addView(bubble(m))
        column.addView(line, wrap())
        row.reaction?.let { r ->
            val pill = text(r, 12f, BLACK).apply {
                background = rounded(WHITE, dp(12)).apply { setStroke(dp(1), GRAY_LINE) }
                setPadding(dp(6), dp(1), dp(6), dp(1))
                isClickable = true
                setOnClickListener { }
            }
            column.addView(pill, wrap().apply { marginStart = indent + dp(8); topMargin = -dp(8) })
        }
        return column
    }

    /** The bubble: long-pressable (the react and reply menu), holding text, media or a big emoji. */
    private fun bubble(m: TextMessage): View {
        val mine = m.isMine
        val ink = if (mine) WHITE else BLACK
        val media = MEDIA.entries.firstOrNull { m.text.startsWith(it.key) }
        val caption = if (media != null) m.text.removePrefix(media.key).trim() else m.text
        val emoji = media == null && m.text.codePoints().allMatch { Character.isWhitespace(it) || it > 0x2000 }
        val box: View = when {
            emoji -> text(m.text, 40f, BLACK)
            media == null -> FrameLayout(this).apply {
                background = rounded(if (mine) PURPLE else GRAY_BUBBLE, dp(20))
                setPadding(dp(13), dp(9), dp(13), dp(9))
                addView(text(m.text, 15f, ink).apply { maxWidth = dp(250) })
            }
            media.value == "Voice message" -> LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = rounded(if (mine) PURPLE else GRAY_BUBBLE, dp(20))
                setPadding(dp(10), dp(8), dp(14), dp(8))
                addView(icon("Voice message", dp(28), ink), square(dp(32)))
                addView(View(context).apply { background = rounded(GRAY_LINE, dp(2)) }, LinearLayout.LayoutParams(dp(120), dp(4)).apply { marginStart = dp(8); marginEnd = dp(8) })
                addView(text("0:07", 13f, ink))
            }
            else -> LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                background = rounded(if (mine) PURPLE else GRAY_BUBBLE, dp(20))
                setPadding(dp(3), dp(3), dp(3), if (caption.isEmpty()) dp(3) else dp(9))
                addView(
                    ImageView(context).apply {
                        contentDescription = media.value
                        background = rounded(colorFor(media.value), dp(17))
                    },
                    LinearLayout.LayoutParams(dp(210), dp(if (media.value == "Shared post") 210 else 250)),
                )
                if (caption.isNotEmpty()) {
                    addView(text(caption, 15f, ink).apply { maxWidth = dp(200) }, wrap().apply { marginStart = dp(10); topMargin = dp(6) })
                }
            }
        }
        box.isClickable = true
        box.setOnClickListener { }
        box.setOnLongClickListener { true }
        return box
    }

    private fun text(s: String, sp: Float, color: Int) = TextView(this).apply {
        text = s
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
    }

    /** An icon stand-in: a described shape, no text (so it can't pass for a title). */
    private fun icon(description: String, size: Int, color: Int) = ImageView(this).apply {
        contentDescription = description
        isClickable = true
        setOnClickListener { }
        setImageDrawable(GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(dp(2), color); setSize(size, size) })
        scaleType = ImageView.ScaleType.CENTER
    }

    private fun oval(color: Int, size: Int) = ImageView(this).apply {
        setImageDrawable(GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color); setSize(size, size) })
    }

    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }

    private fun square(size: Int) = LinearLayout.LayoutParams(size, size)
    private fun wrap() = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)

    private fun colorFor(name: String): Int = PEOPLE[(name.hashCode() and 0x7fffffff) % PEOPLE.size]

    companion object {
        const val EXTRA_LIVE = "live"

        private val MEDIA = linkedMapOf(
            "[photo]" to "Photo",
            "[video]" to "Video",
            "[GIF]" to "GIF",
            "[voice message]" to "Voice message",
            "[shared post]" to "Shared post",
        )
        private val WHITE = Color.WHITE
        private val BLACK = Color.parseColor("#000000")
        private val GRAY_TEXT = Color.parseColor("#737373")
        private val GRAY_LINE = Color.parseColor("#C7C7C7")
        private val GRAY_BUBBLE = Color.parseColor("#EFEFEF")
        private val GRAY_QUOTE = Color.parseColor("#F5F5F5")
        private val PURPLE = Color.parseColor("#7B4BF5")
        private val BLUE = Color.parseColor("#3797F0")
        private val PEOPLE = listOf("#E1306C", "#F77737", "#FCAF45", "#5B51D8", "#3797F0", "#20B486").map(Color::parseColor)
    }
}
