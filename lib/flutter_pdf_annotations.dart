import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as path;

class FlutterPdfAnnotations {
  static const MethodChannel _channel =
      MethodChannel('flutter_pdf_annotations');

  /// Open PDF for annotation
  static Future<void> openPDF({
    required String filePath,
    required String savePath,
    required void Function(String?) onFileSaved,
  }) async {
    try {
      // Validate input file exists
      if (!File(filePath).existsSync()) {
        _showToast("Error: Source file does not exist");
        onFileSaved(null);
        return;
      }

      // If no save path provided, create one in app documents directory

      // Ensure the directory exists
      final saveDir = Directory(path.dirname(savePath));
      if (!saveDir.existsSync()) {
        saveDir.createSync(recursive: true);
      }

      // Set up the method call handler
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onPdfSaved') {
          _handleSaveResult(call.arguments as String, onFileSaved);
          log('onPdfSaved: ${call.arguments}');
        }
      });

      await _channel.invokeMethod('openPDF', {
        'filePath': filePath,
        'savePath': savePath,
      });
    } catch (e) {
      _showToast("Error opening PDF: $e");
      onFileSaved(null);
    }
  }

  static void _handleSaveResult(
      String result, void Function(String?) onFileSaved) {
    try {
      onFileSaved(result);
      _showToast("PDF saved at: $result");
    } catch (e) {
      _showToast("Error processing save result");
      onFileSaved(null);
    }
  }

  static void _showToast(String message) {
    Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 2,
        backgroundColor: Colors.black87,
        textColor: Colors.white,
        fontSize: 16.0);
  }
}
