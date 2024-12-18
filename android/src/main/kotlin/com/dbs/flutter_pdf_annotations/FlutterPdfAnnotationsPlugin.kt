package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterPdfAnnotationsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var context: Context

  companion object {
    private const val TAG = "PdfAnnotationsPlugin"
    private var methodChannel: MethodChannel? = null

    fun notifySaveResult(path: String?) {
      try {
        Log.d(TAG, "Notifying save result: $path")
        methodChannel?.let { channel ->
          channel.invokeMethod("onPdfSaved", path)
        } ?: run {
          Log.e(TAG, "Method channel is null when trying to notify save result")
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error notifying save result: ${e.message}", e)
      }
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    try {
      Log.d(TAG, "Attaching to Flutter engine")
      context = flutterPluginBinding.applicationContext
      methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_pdf_annotations")
      methodChannel?.setMethodCallHandler(this)
      Log.d(TAG, "Successfully attached to Flutter engine")
    } catch (e: Exception) {
      Log.e(TAG, "Error attaching to Flutter engine: ${e.message}", e)
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    try {
      Log.d(TAG, "Received method call: ${call.method}")
      when (call.method) {
        "openPDF" -> handleOpenPDF(call, result)
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error handling method call: ${e.message}", e)
      result.error("ERROR", "Error handling method call: ${e.message}", null)
    }
  }

  private fun handleOpenPDF(call: MethodCall, result: Result) {
    try {
      val filePath = call.argument<String>("filePath")
      val savePath = call.argument<String>("savePath")

      Log.d(TAG, "Opening PDF - File Path: $filePath, Save Path: $savePath")

      if (filePath == null) {
        Log.e(TAG, "File path is null")
        result.error("INVALID_ARGUMENT", "File path cannot be null", null)
        return
      }

      if (savePath == null) {
        Log.e(TAG, "Save path is null")
        result.error("INVALID_ARGUMENT", "Save path cannot be null", null)
        return
      }

      val intent = Intent(context, PDFViewerActivity::class.java).apply {
        putExtra("filePath", filePath)
        putExtra("savePath", savePath)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }

      context.startActivity(intent)
      Log.d(TAG, "PDF viewer activity started successfully")
      result.success(null)
    } catch (e: Exception) {
      Log.e(TAG, "Error opening PDF: ${e.message}", e)
      result.error("ERROR", "Failed to open PDF: ${e.message}", null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    try {
      Log.d(TAG, "Detaching from Flutter engine")
      methodChannel?.setMethodCallHandler(null)
      methodChannel = null
      Log.d(TAG, "Successfully detached from Flutter engine")
    } catch (e: Exception) {
      Log.e(TAG, "Error detaching from Flutter engine: ${e.message}", e)
    }
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    Log.d(TAG, "Attached to activity")
  }

  override fun onDetachedFromActivityForConfigChanges() {
    Log.d(TAG, "Detached from activity for config changes")
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    Log.d(TAG, "Reattached to activity for config changes")
  }

  override fun onDetachedFromActivity() {
    Log.d(TAG, "Detached from activity")
  }
}