package com.vibetemp.ketchup.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

// A diner counter: cream paper, warm ink, ketchup red for the one thing to
// press, mustard for marking what matters, pickle green for "confirmed".
// No gradients, no sparkles, no glass. docs/DESIGN.md is the full guide; the
// values match iOS Theme.swift exactly.

/** Every token as one mode's value. Read them through `KetchupTheme.colors`. */
@Immutable
data class KetchupColors(
    /** App background. */
    val cream: Color,
    /** Raised paper: cards, other people's bubbles. */
    val card: Color,
    /** Hairlines and card borders. */
    val rule: Color,
    /** Primary text, and my own bubbles. */
    val ink: Color,
    /** Secondary text. */
    val inkSoft: Color,
    /** Placeholders and decoration only, never text someone must read. */
    val inkFaint: Color,
    /** Text on an ink fill. */
    val onInk: Color,
    /** The brand red: the logo and the one button to press on a screen. */
    val ketchup: Color,
    /** Small red text on cream (plain ketchup is too light to read small). */
    val ketchupText: Color,
    /** Text on a ketchup fill. */
    val onKetchup: Color,
    /** The marker: highlights, unread badges, the jump-to-message glow. */
    val mustard: Color,
    /** Text on a mustard fill. */
    val onMustard: Color,
    /** Confirmed stamps. */
    val pickle: Color,
    /** Name colors: brick, teal, plum, ochre, forest, navy, rose, slate. */
    val people: List<Color>,
    val isDark: Boolean,
)

val LightKetchupColors = KetchupColors(
    cream = Color(0xFFFBF5EA),
    card = Color(0xFFFFFDF8),
    rule = Color(0xFFEADFCC),
    ink = Color(0xFF2A1E19),
    inkSoft = Color(0xFF74655A),
    inkFaint = Color(0xFFA99A8C),
    onInk = Color(0xFFFFF8EE),
    ketchup = Color(0xFFD7372B),
    ketchupText = Color(0xFFB22A20),
    onKetchup = Color(0xFFFFF8EE),
    mustard = Color(0xFFF3B33D),
    onMustard = Color(0xFF2A1E19),
    pickle = Color(0xFF4F7A3A),
    people = listOf(
        Color(0xFFB4472E), Color(0xFF1E6E6A), Color(0xFF7A3E73), Color(0xFF9A6110),
        Color(0xFF3C6B2F), Color(0xFF2C4A86), Color(0xFFA63D57), Color(0xFF4F5B66),
    ),
    isDark = false,
)

val DarkKetchupColors = KetchupColors(
    cream = Color(0xFF17120F),
    card = Color(0xFF231C17),
    rule = Color(0xFF3A302A),
    ink = Color(0xFFF6EEE2),
    inkSoft = Color(0xFFB3A595),
    inkFaint = Color(0xFF7A6C60),
    onInk = Color(0xFF17120F),
    ketchup = Color(0xFFE8473A),
    ketchupText = Color(0xFFFF7B6B),
    onKetchup = Color(0xFFFFF8EE),
    mustard = Color(0xFFE9A92F),
    onMustard = Color(0xFF17120F),
    pickle = Color(0xFF8CC07A),
    people = listOf(
        Color(0xFFF08A6E), Color(0xFF6FC2BA), Color(0xFFD39BCB), Color(0xFFE8B25A),
        Color(0xFF93C784), Color(0xFF8FAEE6), Color(0xFFEC96AB), Color(0xFFA9B4BF),
    ),
    isDark = true,
)

/** People's colors and initials, the same on both platforms (iOS `Theme.personColor`). */
object People {
    /**
     * Which of the 8 name colors a name gets: FNV-1a over the trimmed,
     * lowercased name with salt 26, the same hash as iOS, so Maya is the
     * same teal in the chat, in Muse Spark's results and on both phones.
     * The demo chat's six people get six different colors.
     */
    fun colorIndex(name: String): Int {
        var hash = 0xcbf29ce484222325uL xor 26uL
        for (byte in name.trim().lowercase().encodeToByteArray()) {
            hash = hash xor byte.toUByte().toULong()
            hash *= 0x100000001b3uL
        }
        hash = hash xor (hash shr 32)
        return (hash % 8uL).toInt()
    }

    /** For places that only have an id: the sum of the uppercase uuid's characters (iOS `personColor(_ id:)`). */
    fun colorIndexForId(id: String): Int = id.uppercase().sumOf { it.code } % 8

    /** "Maya Chen" -> "MC", "sam" -> "S", "" -> "?". */
    fun initials(name: String): String {
        val letters = name.split(' ', '.', '_').filter(String::isNotEmpty).take(2).map { it.first() }
        return if (letters.isEmpty()) "?" else letters.joinToString("").uppercase()
    }
}

/** A person's name color in these colors. */
fun KetchupColors.person(name: String): Color = people[People.colorIndex(name)]
