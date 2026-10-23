package dev.airbuild.airbuild

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log

/**
 * Receives the result of a [PackageInstaller] session commit for in-app APK
 * updates.
 *
 * On Android 12+ (API 31+) a session can complete silently when the app is
 * the installer of record for itself; otherwise the system reports
 * [PackageInstaller.STATUS_PENDING_USER_ACTION] carrying the confirmation
 * Intent, which we launch so the user sees the normal install sheet.
 */
class InstallResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // User confirmation is still required — launch the system's
                // install-confirmation activity it handed us.
                val confirm: Intent? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "APK update installed successfully")
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.e(TAG, "APK install failed (status $status): $message")
            }
        }
    }

    companion object {
        private const val TAG = "AirBuild"
    }
}
