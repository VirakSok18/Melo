package com.example.melo

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private val BANK_CHANNEL = "com.example.melo/bank_launcher"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val modes = display?.supportedModes ?: emptyArray()
                val maxMode = modes.maxByOrNull { it.refreshRate }
                if (maxMode != null && maxMode.refreshRate >= 90f) {
                    window.attributes = window.attributes.apply {
                        preferredDisplayModeId = maxMode.modeId
                    }
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                val modes = windowManager.defaultDisplay.supportedModes
                val maxMode = modes.maxByOrNull { it.refreshRate }
                if (maxMode != null && maxMode.refreshRate >= 90f) {
                    window.attributes = window.attributes.apply {
                        preferredDisplayModeId = maxMode.modeId
                    }
                }
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BANK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchBankWithQrImage" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val packageNamesArg = call.argument<List<String>>("packageNames") ?: emptyList()
                    val qrData = call.argument<String>("qrData") ?: ""
                    val schemes = call.argument<List<String>>("schemes") ?: emptyList()
                    val imageBytes = call.argument<ByteArray>("imageBytes")

                    val allPackages = mutableListOf<String>()
                    if (packageName.isNotBlank()) allPackages.add(packageName)
                    for (pkg in packageNamesArg) {
                        if (pkg.isNotBlank() && !allPackages.contains(pkg)) {
                            allPackages.add(pkg)
                        }
                    }

                    val launched = launchBankWithImage(allPackages, imageBytes, qrData, schemes)
                    result.success(launched)
                }
                "launchBank" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val qrData = call.argument<String>("qrData") ?: ""
                    val schemes = call.argument<List<String>>("schemes") ?: emptyList()
                    val packageNamesArg = call.argument<List<String>>("packageNames") ?: emptyList()

                    val allPackages = mutableListOf<String>()
                    if (packageName.isNotBlank()) allPackages.add(packageName)
                    for (pkg in packageNamesArg) {
                        if (pkg.isNotBlank() && !allPackages.contains(pkg)) {
                            allPackages.add(pkg)
                        }
                    }

                    val launched = launchBankApp(allPackages, qrData, schemes)
                    result.success(launched)
                }
                "isAppInstalled" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(isPackageInstalled(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        if (packageName.isEmpty()) return false
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun launchBankWithImage(
        packageNames: List<String>,
        imageBytes: ByteArray?,
        qrData: String,
        schemes: List<String>
    ): Boolean {
        // 1. Direct Intent: Share the rendered QR image directly into the bank's image-scan receiver (ABA Mobile, Bakong, etc.)
        if (imageBytes != null && imageBytes.isNotEmpty()) {
            for (pkg in packageNames) {
                if (pkg.isBlank()) continue
                try {
                    val cacheDir = externalCacheDir ?: cacheDir

                    // Clean up any previous temp QR images and permissions to avoid stale intent data
                    try {
                        val authority = "${applicationContext.packageName}.fileprovider"
                        cacheDir.listFiles { file -> file.name.startsWith("melo_khqr_") }?.forEach { oldFile ->
                            try {
                                val oldUri = FileProvider.getUriForFile(this, authority, oldFile)
                                revokeUriPermission(oldUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            } catch (_: Exception) {}
                            oldFile.delete()
                        }
                    } catch (_: Exception) {}

                    val qrFile = File(cacheDir, "melo_khqr_${System.currentTimeMillis()}.png")
                    FileOutputStream(qrFile).use { fos ->
                        fos.write(imageBytes)
                        fos.flush()
                    }

                    val authority = "${applicationContext.packageName}.fileprovider"
                    val contentUri = FileProvider.getUriForFile(this, authority, qrFile)

                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, contentUri)
                        putExtra(Intent.EXTRA_TEXT, qrData)
                        putExtra("data", qrData)
                        putExtra("qr", qrData)
                        putExtra("khqr", qrData)
                        setPackage(pkg)
                        clipData = android.content.ClipData.newUri(contentResolver, "KHQR Image", contentUri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }

                    grantUriPermission(pkg, contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

                    if (sendIntent.resolveActivity(packageManager) != null) {
                        startActivity(sendIntent)
                        return true
                    }
                } catch (e: Exception) {
                    // If image sharing fails for this package, continue to fallback
                }
            }
        }

        // 2. Fallback to standard URI schemes or package launch
        return launchBankApp(packageNames, qrData, schemes)
    }

    private fun launchBankApp(packageNames: List<String>, qrData: String, schemes: List<String>): Boolean {
        // 1. Try URI schemes targeted directly to candidate packages
        for (pkg in packageNames) {
            if (pkg.isBlank()) continue
            for (scheme in schemes) {
                if (scheme.isBlank()) continue
                try {
                    val uri = Uri.parse(scheme)
                    val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        setPackage(pkg)
                    }
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        return true
                    }
                } catch (e: Exception) {
                    // Ignore and proceed
                }
            }
        }

        // 2. Try URI schemes without restricting package (in case system handles it via intent filter)
        for (scheme in schemes) {
            if (scheme.isBlank()) continue
            try {
                val uri = Uri.parse(scheme)
                val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (e: Exception) {
                // Ignore and proceed
            }
        }

        // 3. Fallback: Direct package launch intent
        for (pkg in packageNames) {
            if (pkg.isBlank()) continue
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    launchIntent.putExtra("data", qrData)
                    launchIntent.putExtra("qr", qrData)
                    launchIntent.putExtra("khqr", qrData)
                    startActivity(launchIntent)
                    return true
                }
            } catch (e: Exception) {
                // Ignore
            }
        }

        return false
    }
}
