package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FlutterPdfAnnotationsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private val mainScope = CoroutineScope(Dispatchers.Main)

  companion object {
    private var activeResult: Result? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)

    fun notifySaveResult(path: String?) {
      mainScope.launch(Dispatchers.Main) {
        activeResult?.success(path)
        activeResult = null
      }
    }
  }



  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_pdf_annotations")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "openPDF" -> {
        try {
          val filePath = call.argument<String>("filePath")
          if (filePath == null) {
            result.error("INVALID_ARGUMENT", "File path cannot be null", null)
            return
          }

          activeResult = result
          mainScope.launch(Dispatchers.Main) {
            val intent = Intent(context, PDFViewerActivity::class.java).apply {
              putExtra("filePath", filePath)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
          }
        } catch (e: Exception) {
          result.error("ERROR", "Failed to open PDF: ${e.message}", null)
        }
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    // Not used in this implementation
  }

  override fun onDetachedFromActivityForConfigChanges() {
    // Not used in this implementation
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    // Not used in this implementation
  }

  override fun onDetachedFromActivity() {
    // Not used in this implementation
  }
}