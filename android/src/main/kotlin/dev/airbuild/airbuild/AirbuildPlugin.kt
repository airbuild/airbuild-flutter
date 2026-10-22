package dev.airbuild.airbuild

import android.content.Intent
import android.net.Uri
import android.os.Build
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
    /// Uses FileProvider to share the file URI (required for Android 7+).
    private fun installApk(path: String) {
        val context = binding?.applicationContext
            ?: throw IllegalStateException("Application context not available")
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK file not found at $path")
        }

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
}
