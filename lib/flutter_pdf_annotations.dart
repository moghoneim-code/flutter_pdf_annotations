import 'dart:developer';

import 'package:flutter/services.dart';

import 'flutter_pdf_annotations_platform_interface.dart';

class FlutterPdfAnnotations {
  static const MethodChannel _channel =
      MethodChannel('flutter_pdf_annotations');

  Future<String?> getPlatformVersion() {
    return FlutterPdfAnnotationsPlatform.instance.getPlatformVersion();
  }

  void startListening() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        _handleLog(call.arguments as String);
      }
    });
  }

  void _handleLog(String message) {
    print('Log from Swift: $message');
    // You can also route this log to any logging framework you use in Flutter.
  }
  static Future<void> openPDF({
    required String filePath,
    required String savePath,
    required void Function(String) onFileSaved,
  }) async {
    try {
      // Pass both filePath and savePath explicitly
      final String? savedFilePath = await _channel.invokeMethod('openPDF', {
        'filePath': filePath,
        'savePath': savePath,
      });

      log("Saved file path: $savedFilePath");
      if (savedFilePath != null) {
        onFileSaved(savedFilePath);
      }
    } catch (e) {
      print("Error opening PDF: $e");
    }
  }
}
