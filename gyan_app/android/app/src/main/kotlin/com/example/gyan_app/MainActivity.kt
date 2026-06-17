package com.example.gyan_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "gyan/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Launch an allowed app from the (backgrounded) Focus Lock.
                    // NEW_TASK is required to start an activity from a non-resumed
                    // context; the "display over other apps" permission exempts the
                    // app from background-activity-start limits.
                    "launchApp" -> result.success(launch(call.argument<String>("package")))
                    // Bring GYAN itself back to the foreground (Exit).
                    "bringSelfToFront" -> result.success(launch(packageName))
                    // Force-exit a blocked app by jumping to the home screen.
                    "goHome" -> { goHome(); result.success(true) }
                    // ── YPT-style foreground detection via Usage Access ──
                    // (no AccessibilityService → no Google Play Protect block).
                    "getForegroundApp" -> result.success(foregroundApp())
                    "getLauncherPackage" -> result.success(launcherPackage())
                    "isUsageAccessGranted" -> result.success(isUsageAccessGranted())
                    "openUsageAccessSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Most-recently foregrounded package in the last 10s, via UsageStatsManager.
    // Requires the PACKAGE_USAGE_STATS ("Usage access") permission; returns null
    // if it isn't granted or no event was recorded.
    private fun foregroundApp(): String? {
        return try {
            val usm = applicationContext
                .getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val events = usm.queryEvents(end - 10_000, end)
            var pkg: String? = null
            var ts = 0L
            val e = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND && e.timeStamp >= ts) {
                    ts = e.timeStamp
                    pkg = e.packageName
                }
            }
            pkg
        } catch (ex: Exception) {
            null
        }
    }

    // The default home launcher package — the lock covers it but never force-exits
    // it (you ARE allowed to sit at your home screen with the lock showing).
    private fun launcherPackage(): String? = try {
        packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
        )?.activityInfo?.packageName
    } catch (ex: Exception) {
        null
    }

    private fun isUsageAccessGranted(): Boolean = try {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
            )
        }
        mode == AppOpsManager.MODE_ALLOWED
    } catch (ex: Exception) {
        false
    }

    private fun goHome() {
        try {
            startActivity(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (ex: Exception) {
        }
    }

    private fun launch(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        return try {
            val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
