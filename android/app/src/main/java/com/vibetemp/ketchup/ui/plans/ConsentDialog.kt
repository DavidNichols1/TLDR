package com.vibetemp.ketchup.ui.plans

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.vibetemp.ketchup.R
import com.vibetemp.ketchup.data.ConsentGate
import com.vibetemp.ketchup.ui.theme.KetchupTheme

/**
 * Shows the one-time Muse Spark question while [ConsentGate] is asking it
 * (one line in BriefActivity). Same words as iOS Plans/AIConsentSheet.swift:
 * what goes to Meta's Muse Spark (friends' messages included), that Meta
 * doesn't train on it, and an explicit "I'm 18 or older" before Allow works.
 */
@Composable
fun ConsentDialogHost() {
    val question by ConsentGate.asking.collectAsState()
    if (question != null) ConsentDialog(onAnswer = ConsentGate::answer)
}

@Composable
private fun ConsentDialog(onAnswer: (Boolean) -> Unit) {
    val colors = KetchupTheme.colors
    val type = KetchupTheme.type
    var adult by rememberSaveable { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { onAnswer(false) },
        title = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.plans_consent_kicker).uppercase(), style = type.monoCaption2, color = colors.inkSoft)
                Text(stringResource(R.string.plans_consent_title), style = type.serifTitle2, color = colors.ink)
            }
        },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.plans_consent_sends), style = type.body, color = colors.ink)
                Text(stringResource(R.string.plans_consent_standard), style = type.body, color = colors.ink)
                Text(stringResource(R.string.plans_consent_age), style = type.body, color = colors.inkSoft)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .toggleable(value = adult, role = Role.Checkbox, onValueChange = { adult = it })
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = adult,
                        onCheckedChange = null,
                        colors = CheckboxDefaults.colors(
                            checkedColor = colors.ink,
                            uncheckedColor = colors.inkSoft,
                            checkmarkColor = colors.onInk,
                        ),
                    )
                    Text(
                        stringResource(R.string.plans_consent_adult),
                        style = type.body.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.ink,
                        modifier = Modifier.padding(start = 12.dp),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onAnswer(true) }, enabled = adult) {
                Text(
                    stringResource(R.string.plans_consent_allow),
                    color = if (adult) colors.ketchupText else colors.inkFaint,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = { onAnswer(false) }) {
                Text(stringResource(R.string.plans_consent_not_now), color = colors.ink)
            }
        },
        containerColor = colors.card,
    )
}
