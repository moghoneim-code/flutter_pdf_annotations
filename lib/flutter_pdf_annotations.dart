import 'dart:io';

import 'package:flutter/services.dart';
import 'flutter_pdf_annotations_platform_interface.dart';

class FlutterPdfAnnotations {
  static const MethodChannel _channel = MethodChannel('flutter_pdf_annotations');

  /// Get the platform version
  Future<String?> getPlatformVersion() {
    return FlutterPdfAnnotationsPlatform.instance.getPlatformVersion();
  }

  /// Set up a listener for method calls from the native side
  void startListening() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'log':
          _handleLog(call.arguments as String);
          break;
        case 'onPdfSaved':
          _handlePdfSaved(call.arguments as String?);
          break;
      }
    });
  }

  /// Handle log messages from native platform
  void _handleLog(String message) {
    print('Native Log: $message');
  }

  /// Handle PDF save result
  void _handlePdfSaved(String? savedFilePath) {
    print("PDF saved at: $savedFilePath");
  }

  /// Open PDF for annotation
  static Future<void> openPDF({
    required String filePath,
    required void Function(String?) onFileSaved,
  }) async {
    if (!File(filePath).existsSync()) {
      print("Error: File does not exist at path: $filePath");
      onFileSaved(null);
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPdfSaved') onFileSaved(call.arguments as String?);
    });

    try {
      await _channel.invokeMethod('openPDF', {'filePath': filePath});
    } catch (e) {
      print("Error opening PDF: $e");
      onFileSaved(null);
    }
  }
}