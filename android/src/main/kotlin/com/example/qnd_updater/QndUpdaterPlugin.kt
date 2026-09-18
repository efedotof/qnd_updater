package com.example.qnd_updater

import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result 

class QndUpdaterPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var applicationContext: Context? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "qnd_updater")
    channel.setMethodCallHandler(this)
    applicationContext = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "getAppVersion") { 
      val context = applicationContext
      if (context != null) {
        try {
          val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
          val versionName = packageInfo.versionName
          result.success(versionName)
        } catch (e: PackageManager.NameNotFoundException) {
          result.error("UNAVAILABLE", "Не удалось получить версию приложения.", null)
        }
      } else {
        result.error("NO_CONTEXT", "Контекст приложения недоступен.", null)
      }
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    applicationContext = null
  }
}
