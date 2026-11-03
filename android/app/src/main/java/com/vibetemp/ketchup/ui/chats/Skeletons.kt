package com.vibetemp.ketchup.ui.chats

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.ui.theme.KetchupTheme

// Blank paper in the shape of what's coming, for a first load (iOS
// Design/Skeletons.swift): the inbox's rows and a thread's bubbles. Bars are
// hairline paper; bubbles are card paper with a hairline, like the real
// ones. It breathes (a slow opacity pulse, since a shimmer band would be a
// gradient) and holds still with Reduce Motion. Never a spinner.

/** Makes [content] breathe, and gives TalkBack one [label] for all of it. */
@Composable
fun Skeleton(label: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val alpha = if (KetchupTheme.reduceMotion) {
        1f
    } else {
        val breath = rememberInfiniteTransition(label = "skeleton")
        val value by breath.animateFloat(1f, 0.45f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "breath")
        value
    }
    Column(
        modifier
            .alpha(alpha)
            .clearAndSetSemantics { contentDescription = label },
        content = content,
    )
}

/** One blank line of type: a rounded bar sitting in a line of [line] height, so rows keep their real height. */
@Composable
fun Bone(width: Dp? = null, share: Float = 1f, height: Dp = 9.dp, line: Dp = 20.dp) {
    Box(Modifier.height(line).then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth()), contentAlignment = Alignment.CenterStart) {
        Box(
            Modifier
                .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth(share))
                .height(height)
                .background(KetchupTheme.colors.rule, RoundedCornerShape(50)),
        )
    }
}

/** The inbox before my_chats answers: rows in ChatListRow's shape, with its hairlines. */
@Composable
fun InboxSkeleton(label: String, rows: Int = 6) {
    val shapes = listOf(
        Triple(132.dp, 0.92f, true), Triple(96.dp, 0.66f, false), Triple(150.dp, 0.84f, false),
        Triple(108.dp, 0.9f, true), Triple(124.dp, 0.58f, false), Triple(88.dp, 0.76f, false),
    )
    val colors = KetchupTheme.colors
    Skeleton(label) {
        for (i in 0 until rows) {
            val (name, preview, twoLines) = shapes[i % shapes.size]
            Row(Modifier.padding(horizontal = 20.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(
                    Modifier
                        .size(ROW_MONOGRAM)
                        .background(colors.rule, RoundedCornerShape(ROW_MONOGRAM * 0.3f)),
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Bone(width = name, height = 12.dp, line = 22.dp)
                        Spacer(Modifier.weight(1f))
                        Bone(width = 36.dp, height = 8.dp, line = 22.dp)
                    }
                    Bone(share = preview)
                    if (twoLines) Bone(share = preview * 0.55f)
                }
            }
            if (i < rows - 1) RowHairline()
        }
    }
}

/** A thread before its first page: a day line, then bubbles from a few people, sitting at the bottom. */
@Composable
fun ThreadSkeleton(label: String, modifier: Modifier = Modifier) {
    Skeleton(label, modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .clipToBounds()
                .padding(horizontal = 14.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.Bottom,
        ) {
            Box(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 6.dp), contentAlignment = Alignment.Center) {
                Bone(width = 64.dp, height = 7.dp, line = 12.dp)
            }
            Theirs(name = true, lines = listOf(168.dp), startsRun = true, endsRun = false)
            Theirs(name = false, lines = listOf(214.dp, 120.dp), startsRun = false, endsRun = true)
            Mine(width = 132.dp, lines = 1)
            Theirs(name = true, lines = listOf(146.dp), startsRun = true, endsRun = true)
            Theirs(name = true, lines = listOf(196.dp, 172.dp), startsRun = true, endsRun = false)
            Theirs(name = false, lines = listOf(92.dp), startsRun = false, endsRun = true)
            Mine(width = 186.dp, lines = 2)
            Theirs(name = true, lines = listOf(120.dp), startsRun = true, endsRun = true)
        }
    }
}

@Composable
private fun Theirs(name: Boolean, lines: List<Dp>, startsRun: Boolean, endsRun: Boolean) {
    val colors = KetchupTheme.colors
    val shape = RoundedCornerShape(
        topStart = if (startsRun) 18.dp else 6.dp, bottomStart = if (endsRun) 18.dp else 6.dp,
        topEnd = 18.dp, bottomEnd = 18.dp,
    )
    Column(
        Modifier
            .padding(top = if (startsRun) 10.dp else 0.dp)
            .padding(vertical = 1.5.dp)
            .padding(end = 56.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (name) Box(Modifier.padding(start = 12.dp)) { Bone(width = 52.dp, height = 7.dp, line = 16.dp) }
        Column(
            Modifier
                .background(colors.card, shape)
                .border(1.dp, colors.rule, shape)
                .padding(horizontal = 14.dp, vertical = 9.dp),
        ) {
            lines.forEach { Bone(width = it, height = 8.dp, line = 22.dp) }
        }
    }
}

@Composable
private fun Mine(width: Dp, lines: Int) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = 10.dp)
            .padding(vertical = 1.5.dp),
        contentAlignment = Alignment.CenterEnd,
    ) {
        Box(
            Modifier
                .width(width + 28.dp)
                .height(22.dp * lines + 18.dp)
                .background(KetchupTheme.colors.rule, RoundedCornerShape(18.dp)),
        )
    }
}

/** The inbox's rule between rows, starting where the text starts. */
@Composable
fun RowHairline() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 20.dp + ROW_MONOGRAM + 14.dp)
            .height(1.dp)
            .background(KetchupTheme.colors.rule),
    )
}

/** The inbox row's monogram. */
val ROW_MONOGRAM = 48.dp
