package com.example.flutter_pdf_annotations

import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

class PdfAnnotationsPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "flutter_pdf_annotations")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "openPDF" -> {
        val filePath = call.argument<String>("filePath")
        val savePath = call.argument<String>("savePath")

        if (filePath == null || savePath == null) {
          result.error("INVALID_ARGUMENTS", "File path or save path is missing", null)
          return
        }

        val intent = Intent(context, PdfActivity::class.java).apply {
          putExtra("filePath", filePath)
          putExtra("savePath", savePath)
        }
        context.startActivity(intent)
        result.success("PDF viewer opened")
      }
      else -> result.notImplemented()
    }
  }
}
