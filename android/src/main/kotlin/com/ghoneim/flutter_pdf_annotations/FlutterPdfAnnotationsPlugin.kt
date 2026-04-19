package com.ghoneim.flutter_pdf_annotations

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

    /** Notify Flutter that the user saved successfully. */
    fun notifySaveResult(path: String) {
      notify(mapOf("status" to "success", "path" to path))
    }

    /** Notify Flutter that the user cancelled without saving. */
    fun notifyCancelled() {
      notify(mapOf("status" to "cancelled"))
    }

    /** Notify Flutter that a save error occurred. */
    fun notifySaveError(message: String) {
      Log.e(TAG, "Save error: $message")
      notify(mapOf("status" to "error", "message" to message))
    }

    private fun notify(args: Map<String, String>) {
      try {
        methodChannel?.invokeMethod("onPdfSaved", args)
          ?: Log.e(TAG, "Method channel is null — cannot notify Flutter")
      } catch (e: Exception) {
        Log.e(TAG, "Error notifying Flutter: ${e.message}", e)
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

      if (filePath == null || savePath == null) {
        result.error("INVALID_ARGUMENT", "filePath and savePath are required", null)
        return
      }

      val intent = Intent(context, PDFViewerActivity::class.java).apply {
        putExtra("filePath", filePath)
        putExtra("savePath", savePath)
        // Optional config
        call.argument<String>("title")?.let { putExtra("title", it) }
        colorArgFromCall(call, "initialPenColor")?.let { putExtra("initialPenColor", it) }
        colorArgFromCall(call, "initialHighlightColor")?.let { putExtra("initialHighlightColor", it) }
        call.argument<Double>("initialStrokeWidth")?.let { putExtra("initialStrokeWidth", it.toFloat()) }
        call.argument<List<String>>("imagePaths")?.let {
          putStringArrayListExtra("imagePaths", ArrayList(it))
        }
        call.argument<Int>("initialPage")?.let { putExtra("initialPage", it) }
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

  /** Reads a color value that may arrive as Int or Long (Dart int encoding). */
  private fun colorArgFromCall(call: MethodCall, key: String): Int? {
    return when (val raw = call.argument<Any>(key)) {
      is Int -> raw
      is Long -> raw.toInt()
      else -> null
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