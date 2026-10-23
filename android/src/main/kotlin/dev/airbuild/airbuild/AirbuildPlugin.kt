package dev.airbuild.airbuild

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/// AirbuildPlugin — Flutter platform plugin for AirBuild SDK.
///
/// Handles the Android-specific install flow: receives the path to a downloaded
/// APK file from the Dart side and triggers the system PackageInstaller via an
/// Intent.
class AirbuildPlugin : FlutterPlugin, MethodCallHandler {

    private var channel: MethodChannel? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "dev.airbuild.airbuild/install")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "installApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_args", "Missing 'path' argument", null)
                    return
                }
                try {
                    installApk(path)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            }
            "getInstallerPackageName" -> {
                try {
                    result.success(installerPackageName())
                } catch (e: Exception) {
                    result.error("installer_lookup_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /// Returns the package name of the store/installer that installed this
    /// app (e.g. "com.android.vending" for Google Play), or null when the
    /// install source can't be determined (ADB, sideloads, preloaded apps).
    private fun installerPackageName(): String? {
        val context = binding?.applicationContext
            ?: throw IllegalStateException("Application context not available")
        val pm = context.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pm.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            pm.getInstallerPackageName(context.packageName)
        }
    }

    /// Triggers the Android system installer for the APK at [path].
    ///
    /// On Android 12+ (API 31+) the APK is installed through a
    /// [PackageInstaller] session — when this app is the installer of record
    /// for itself the update applies with no user confirmation at all;
    /// otherwise [InstallResultReceiver] launches the system's confirmation
    /// sheet. On older versions (or if the session path fails) we fall back
    /// to an ACTION_VIEW Intent on the FileProvider URI.
    private fun installApk(path: String) {
        val context = binding?.applicationContext
            ?: throw IllegalStateException("Application context not available")
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK file not found at $path")
        }

        // On Android 8+ the "install unknown apps" privilege is per-app and
        // must be granted before any install path can succeed. If it hasn't
        // been granted yet, take the user straight to the toggle for this
        // app and fail — the next attempt after they allow it will proceed.
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(settingsIntent)
            throw SecurityException(
                "Install permission not granted — allow installs from this " +
                    "app in the settings screen that just opened, then retry"
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                installApkViaSession(context, file)
                return
            } catch (e: Exception) {
                Log.w(TAG, "Session install failed, falling back to Intent", e)
            }
        }
        installApkViaIntent(context, file)
    }

    /// Installs [file] through a PackageInstaller session (API 31+).
    ///
    /// `USER_ACTION_NOT_REQUIRED` asks the system to skip the confirmation
    /// sheet — honored when this app originally installed itself through a
    /// session (installer of record) or holds UPDATE_PACKAGES_WITHOUT_USER_ACTION.
    /// Otherwise the result broadcast carries STATUS_PENDING_USER_ACTION and
    /// [InstallResultReceiver] opens the normal confirmation UI.
    private fun installApkViaSession(context: Context, file: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            setAppPackageName(context.packageName)
            setRequireUserAction(
                PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
            )
        }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            file.inputStream().use { input ->
                session.openWrite("airbuild_update.apk", 0, file.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }

            // FLAG_MUTABLE is required — the system writes the status extras
            // into this intent before broadcasting it to our receiver.
            val callback = Intent(context, InstallResultReceiver::class.java)
                .setPackage(context.packageName)
            val pending = PendingIntent.getBroadcast(
                context,
                sessionId,
                callback,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            session.commit(pending.intentSender)
        }
    }

    /// Installs [file] via a plain ACTION_VIEW Intent (pre-Android 12 path).
    /// Uses FileProvider to share the file URI (required for Android 7+).
    private fun installApkViaIntent(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.airbuild.fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }

        context.startActivity(intent)
    }

    companion object {
        private const val TAG = "AirBuild"
    }
}
