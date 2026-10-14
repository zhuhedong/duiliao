package com.duiliao.duiliao_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val installerChannel = "com.duiliao.duiliao_app/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "path required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApk(path))
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Returns "started", "needs_permission" or "signature_mismatch". */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }
        if (!sameSignerAsInstalled(file)) {
            return "signature_mismatch"
        }
        // Android 8+: "install unknown apps" is a per-app toggle. Without it
        // some ROMs silently drop the ACTION_VIEW intent.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "needs_permission"
        }
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = android.content.ClipData.newRawUri("", uri)
        }
        startActivity(intent)
        return "started"
    }

    /**
     * Compare the archive's signing certificates with the installed app's.
     * Returns true when they match or cannot be determined (let the system
     * installer decide), false only on a definite mismatch.
     */
    @Suppress("DEPRECATION")
    private fun sameSignerAsInstalled(file: File): Boolean {
        return try {
            val pm = packageManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val flags = PackageManager.GET_SIGNING_CERTIFICATES
                val archive = pm.getPackageArchiveInfo(file.path, flags)?.signingInfo
                    ?: return true
                val installed = pm.getPackageInfo(packageName, flags).signingInfo
                    ?: return true
                val a = (if (archive.hasMultipleSigners()) archive.apkContentsSigners
                    else archive.signingCertificateHistory)?.map { it.toCharsString() }?.toSet()
                    ?: return true
                val b = (if (installed.hasMultipleSigners()) installed.apkContentsSigners
                    else installed.signingCertificateHistory)?.map { it.toCharsString() }?.toSet()
                    ?: return true
                a.intersect(b).isNotEmpty()
            } else {
                val flags = PackageManager.GET_SIGNATURES
                val a = pm.getPackageArchiveInfo(file.path, flags)?.signatures
                    ?.map { it.toCharsString() }?.toSet() ?: return true
                val b = pm.getPackageInfo(packageName, flags).signatures
                    ?.map { it.toCharsString() }?.toSet() ?: return true
                a == b
            }
        } catch (_: Exception) {
            true
        }
    }
}
