package com.vibetemp.ketchup.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.vibetemp.ketchup.data.TextSource
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * The home pager's Instagram or Snapchat page; the chat slice's pager shows
 * it. The reader slice fills it in: what the bubble does, turning the
 * service on, and opening the official app. Stub for now.
 */
@Composable
fun ReaderPage(source: TextSource, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(source.appName, style = KetchupTheme.type.serifTitle2, color = KetchupTheme.colors.ink)
    }
}
