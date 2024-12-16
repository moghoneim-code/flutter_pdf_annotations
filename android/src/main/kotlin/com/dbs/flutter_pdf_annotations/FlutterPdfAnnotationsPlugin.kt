package com.dbs.flutter_pdf_annotations

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterPdfAnnotationsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context

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
      "openPDF" -> handleOpenPDF(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleOpenPDF(call: MethodCall, result: MethodChannel.Result) {
    val args = call.arguments as? Map<*, *>
    val filePath = args?.get("filePath") as? String
    val savePath = args?.get("savePath") as? String

    if (filePath.isNullOrEmpty() || savePath.isNullOrEmpty()) {
      result.error("INVALID_ARGUMENTS", "filePath or savePath is missing", null)
      return
    }

    val intent = Intent(context, PDFViewerActivity::class.java).apply {
      putExtra("filePath", filePath)
      putExtra("savePath", savePath)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    context.startActivity(intent)
    result.success(null)
  }
}
