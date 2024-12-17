package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterPdfAnnotationsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context

  companion object {
    private var saveResultCallback: ((String?) -> Unit)? = null

    fun notifySaveResult(path: String?) {
      saveResultCallback?.invoke(path)
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "flutter_pdf_annotations")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "openPDF" -> {
        val filePath = call.argument<String>("filePath")
        val savePath = call.argument<String>("savePath")
        val intent = Intent(context, PDFViewerActivity::class.java).apply {
          putExtra("filePath", filePath)
          putExtra("savePath", savePath)
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        saveResultCallback = { savedPath ->
          channel.invokeMethod("onPdfSaved", savedPath)
        }
        context.startActivity(intent)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }
}
