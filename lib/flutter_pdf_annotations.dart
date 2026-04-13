import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Configuration passed to the PDF annotation viewer on open.
class PDFAnnotationConfig {
  /// Title shown in the navigation / top bar.
  final String? title;

  /// Initial pen/draw color. Include desired alpha in the color value.
  final Color? initialPenColor;

  /// Initial highlight color. Include desired alpha (e.g. `Colors.yellow.withOpacity(0.5)`).
  final Color? initialHighlightColor;

  /// Initial stroke width. Nearest preset is used: 3.0 → S, 8.0 → M, 18.0 → L.
  final double? initialStrokeWidth;

  /// Images to make available for insertion onto PDF pages.
  /// Each [Uint8List] is raw image bytes (PNG, JPEG, etc.).
  final List<Uint8List>? imagesToInsert;

  const PDFAnnotationConfig({
    this.title,
    this.initialPenColor,
    this.initialHighlightColor,
    this.initialStrokeWidth,
    this.imagesToInsert,
  });

  Map<String, dynamic> toMap() => {
        if (title != null) 'title': title,
        // toSigned(32) ensures the value fits in Int32 on both native platforms
        if (initialPenColor != null)
          'initialPenColor': initialPenColor!.toARGB32().toSigned(32),
        if (initialHighlightColor != null)
          'initialHighlightColor': initialHighlightColor!.toARGB32().toSigned(32),
        if (initialStrokeWidth != null) 'initialStrokeWidth': initialStrokeWidth,
      };
}

class FlutterPdfAnnotations {
  static const MethodChannel _channel =
      MethodChannel('flutter_pdf_annotations');

  static Completer<String?>? _completer;
  static bool _handlerRegistered = false;

  static void _ensureHandlerRegistered() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPdfSaved') {
        final result = call.arguments as String?;
        log('onPdfSaved: $result');
        final completer = _completer;
        _completer = null;
        if (completer != null && !completer.isCompleted) {
          completer.complete(result);
        }
      }
    });
  }

  /// Open a local PDF file for annotation.
  ///
  /// Returns the saved file path, or `null` if the user cancelled.
  /// [savePath] is auto-generated in the system temp directory when omitted.
  static Future<String?> openPDF({
    required String filePath,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    if (!File(filePath).existsSync()) {
      log('openPDF: source file not found: $filePath');
      _showToast('Error: Source file does not exist');
      return null;
    }
    final resolvedSavePath = savePath ?? _tempSavePath();
    File(resolvedSavePath).parent.createSync(recursive: true);
    final args = <String, dynamic>{
      'filePath': filePath,
      'savePath': resolvedSavePath,
      ...?config?.toMap(),
    };
    if (config?.imagesToInsert != null && config!.imagesToInsert!.isNotEmpty) {
      final paths = await _saveImagesToTemp(config.imagesToInsert!);
      if (paths.isNotEmpty) args['imagePaths'] = paths;
    }
    return _openInternal(args: args);
  }

  /// Open a PDF from raw bytes for annotation.
  ///
  /// Useful when the PDF is already in memory (downloaded, generated, etc.).
  static Future<String?> openFromBytes({
    required Uint8List bytes,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/pdf_in_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await tempFile.writeAsBytes(bytes);
    return openPDF(filePath: tempFile.path, savePath: savePath, config: config);
  }

  /// Download a PDF from [url] and open it for annotation.
  ///
  /// Uses `dart:io` `HttpClient`; no additional packages required.
  static Future<String?> openFromUrl({
    required String url,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        _showToast('Error downloading PDF: HTTP ${response.statusCode}');
        client.close();
        return null;
      }
      final bytes = await response
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      client.close();
      return openFromBytes(
        bytes: Uint8List.fromList(bytes),
        savePath: savePath,
        config: config,
      );
    } catch (e) {
      _showToast('Error downloading PDF: $e');
      return null;
    }
  }

  /// Load a PDF from a Flutter asset and open it for annotation.
  ///
  /// [assetPath] matches the key declared in pubspec.yaml (e.g. `'assets/sample.pdf'`).
  static Future<String?> openFromAsset({
    required String assetPath,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      return openFromBytes(
        bytes: data.buffer.asUint8List(),
        savePath: savePath,
        config: config,
      );
    } catch (e) {
      _showToast('Error loading asset: $e');
      return null;
    }
  }

  static String _tempSavePath() =>
      '${Directory.systemTemp.path}/pdf_annotated_${DateTime.now().millisecondsSinceEpoch}.pdf';

  static Future<List<String>> _saveImagesToTemp(List<Uint8List> images) async {
    final paths = <String>[];
    // Use a plugin-specific subdirectory so temp images are isolated
    final dir = Directory(
        '${Directory.systemTemp.path}/flutter_pdf_annotations_imgs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (int i = 0; i < images.length; i++) {
      final file = File(
        '${dir.path}/pdf_img_${DateTime.now().millisecondsSinceEpoch}_$i.png',
      );
      await file.writeAsBytes(images[i]);
      paths.add(file.path);
    }
    return paths;
  }

  static Future<String?> _openInternal(
      {required Map<String, dynamic> args}) async {
    _ensureHandlerRegistered();
    final completer = Completer<String?>();
    _completer = completer;
    try {
      await _channel.invokeMethod('openPDF', args);
    } catch (e) {
      log('Error opening PDF: $e');
      _showToast('Error opening PDF: $e');
      if (_completer == completer) _completer = null;
      completer.complete(null);
      return null;
    }
    return completer.future;
  }

  static void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
}
