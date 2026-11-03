package com.vibetemp.ketchup.reader

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Reads the DM thread open in the official Instagram or Snapchat app, when
 * the person asks, into a [com.vibetemp.ketchup.data.TextThread], and opens
 * `BriefActivity.start(this, thread)`. Limited to those two apps by
 * res/xml/reader_service.xml. The reader slice owns this package.
 *
 * Empty for now: it's declared, so it shows in Settings > Accessibility.
 * Rules carried over from iOS (CLAUDE.md, web-chat catch-up): read only the
 * chat that's open, only on the person's tap; store nothing; log counts only,
 * never message text or names.
 */
class KetchupReaderService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit
}
