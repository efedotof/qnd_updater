package com.efedotof.qnd_updater

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class QndUpdaterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel
  private var appContext: Context? = null

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "qnd_updater")
    channel.setMethodCallHandler(this)
    appContext = binding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
    when (call.method) {
      "getAppVersion" -> {
        val ctx = appContext
        if (ctx == null) { result.error("NO_CONTEXT", "no context", null); return }
        try {
          val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
          val v = info.versionName ?: run {
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toString()
            else info.versionCode.toString()
          }
          result.success(v)
        } catch (e: PackageManager.NameNotFoundException) {
          result.error("UNAVAILABLE", "versionName unavailable", null)
        }
      }
      "applyUpdate" -> {
        val ctx = appContext
        val path = call.argument<String>("stagingDir")
        if (ctx == null || path == null) {
          result.error("BAD_ARGS", "context or stagingDir missing", null); return
        }
        try {
          installApk(ctx, path)
          result.success(true)
        } catch (e: Exception) {
          result.error("INSTALL_FAILED", e.message, null)
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun installApk(ctx: Context, path: String) {
    val src = File(path)
    if (!src.exists()) throw IllegalStateException("Path not found: $path")

   
    val apk: File = if (src.isDirectory) {
      src.listFiles()
          ?.firstOrNull { it.isFile && it.name.endsWith(".apk") }
          ?: throw IllegalStateException("No .apk file in $path")
    } else {
      if (!src.name.endsWith(".apk")) {
        throw IllegalStateException("Not an APK: $path")
      }
      src
    }

    val authority = "${ctx.packageName}.qnd_updater.fileprovider"
    val uri: Uri = FileProvider.getUriForFile(ctx, authority, apk)

    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, "application/vnd.android.package-archive")
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    ctx.startActivity(intent)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    appContext = null
  }
}