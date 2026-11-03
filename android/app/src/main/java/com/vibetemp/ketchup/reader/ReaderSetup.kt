package com.vibetemp.ketchup.reader

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import com.vibetemp.ketchup.MainActivity
import com.vibetemp.ketchup.data.TextSource

/**
 * Turning the reader on: the person's consent (a flag in private app
 * storage, never anything they read), whether Android has the service on,
 * and the other apps it works in.
 */
object ReaderSetup {
    private const val PREFS = "ketchup.reader"
    private const val CONSENTED = "consented"

    /** The person read what the bubble does and agreed, on the consent screen. */
    fun hasConsent(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(CONSENTED, false)

    fun setConsent(context: Context, agreed: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(CONSENTED, agreed).apply()
    }

    /** The reader service is switched on in Settings > Accessibility. */
    fun isServiceOn(context: Context): Boolean {
        val me = ComponentName(context, KetchupReaderService::class.java)
        val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()
        if (enabled.split(':').any { ComponentName.unflattenFromString(it) == me }) return true
        val manager = context.getSystemService(AccessibilityManager::class.java) ?: return false
        return manager.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo?.serviceInfo?.let { s -> s.packageName == me.packageName && s.name == me.className } == true }
    }

    /** Android 13 and later may block turning it on for an app that wasn't installed from a store. */
    val mayNeedRestrictedSettings: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    fun accessibilitySettings(): Intent =
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Ketchup's App info page, where "Allow restricted settings" lives (in its ⋮ menu). */
    fun appInfo(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** The official app's launcher intent, or null when it isn't installed. */
    fun launchIntent(context: Context, source: TextSource): Intent? =
        context.packageManager.getLaunchIntentForPackage(source.packageName)?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Ketchup itself, from the reader service (sign in, or the consent screen). */
    fun openKetchup(context: Context) {
        context.startActivity(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
        )
    }
}
