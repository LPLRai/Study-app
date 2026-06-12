package com.example.gyan_app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import java.io.File

// Reports the current foreground app in real time. usage_stats is unreliable
// (it lags and misses background-launched activities), so Focus Lock relies on
// this instead: on every window change it writes the foreground package to a
// file the Dart FocusMonitor reads. The user enables it once in
// Settings → Accessibility. It does NOT read screen content.
class FocusAccessibilityService : AccessibilityService() {
    // Transient/system windows that fire window-state-changed but are NOT the
    // foreground app (status bar, shade, recents, the overlay host, IMEs…).
    // Skipping them keeps the last real app/launcher as the reported foreground.
    private val ignored = setOf(
        "com.android.systemui",
        "com.google.android.inputmethod.latin",
        "com.android.inputmethod.latin",
        "android"
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg in ignored) return
        // Only real app/launcher windows that have a launchable activity — this
        // filters out toasts, dialogs and other non-foreground popups while
        // still catching the launcher (which is launchable).
        if (packageManager.getLaunchIntentForPackage(pkg) == null) return
        try {
            File(cacheDir, "fg_pkg.txt").writeText(pkg)
        } catch (_: Exception) {
        }
    }

    override fun onInterrupt() {}
}
