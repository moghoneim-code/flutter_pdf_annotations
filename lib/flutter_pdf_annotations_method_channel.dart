import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';

import 'flutter_pdf_annotations_platform_interface.dart';

/// Method-channel implementation of [FlutterPdfAnnotationsPlatform].
class MethodChannelFlutterPdfAnnotations extends FlutterPdfAnnotationsPlatform {
  static const MethodChannel _channel =
      MethodChannel('flutter_pdf_annotations');

  /// Native side sends a PdfAnnotationResult — only one session active at a time.
  static Completer<PdfAnnotationResult>? _completer;
  static bool _handlerRegistered = false;

  /// How long to wait for native to respond before declaring a timeout.
  static const _sessionTimeout = Duration(minutes: 10);

  static void _ensureHandlerRegistered() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onPdfSaved') return;

      // Protocol: native sends Map {status, path?, message?}
      final args = call.arguments as Map<Object?, Object?>?;
      final status = args?['status'] as String? ?? 'cancelled';

      final PdfAnnotationResult result;
      switch (status) {
        case 'success':
          final path = args?['path'] as String?;
          result = path != null && path.isNotEmpty
              ? PdfAnnotationResult.success(path)
              : PdfAnnotationResult.error('Save reported success but path is empty');
          break;
        case 'error':
          final msg = args?['message'] as String? ?? 'Unknown save error';
          result = PdfAnnotationResult.error(msg);
          break;
        default: // 'cancelled' or anything unexpected
          result = PdfAnnotationResult.cancelled();
      }

      log('flutter_pdf_annotations: onPdfSaved → $result');
      final completer = _completer;
      _completer = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete(result);
      }
    });
  }

  @override
  Future<PdfAnnotationResult> openPDF({
    required String filePath,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    final resolvedSavePath = savePath ?? _tempSavePath();

    try {
      File(resolvedSavePath).parent.createSync(recursive: true);
    } catch (e) {
      return PdfAnnotationResult.error(
          'Cannot create save directory: $e');
    }

    final args = <String, dynamic>{
      'filePath': filePath,
      'savePath': resolvedSavePath,
      ...?config?.toMap(),
    };

    final tempImagePaths = <String>[];
    if (config?.imagesToInsert != null && config!.imagesToInsert!.isNotEmpty) {
      try {
        tempImagePaths.addAll(await _saveImagesToTemp(config.imagesToInsert!));
      } catch (e) {
        return PdfAnnotationResult.error('Failed to prepare images: $e');
      }
      if (tempImagePaths.isNotEmpty) args['imagePaths'] = tempImagePaths;
    }

    try {
      return await _invoke(args);
    } finally {
      _cleanupTempImages(tempImagePaths);
    }
  }

  static Future<PdfAnnotationResult> _invoke(
      Map<String, dynamic> args) async {
    _ensureHandlerRegistered();

    final completer = Completer<PdfAnnotationResult>();
    _completer = completer;

    try {
      await _channel.invokeMethod('openPDF', args);
    } on PlatformException catch (e) {
      log('flutter_pdf_annotations: PlatformException — ${e.message}');
      if (_completer == completer) _completer = null;
      return PdfAnnotationResult.error(e.message ?? e.toString());
    } catch (e) {
      log('flutter_pdf_annotations: unexpected error — $e');
      if (_completer == completer) _completer = null;
      return PdfAnnotationResult.error(e.toString());
    }

    // Wait for native to call back, with a safety timeout.
    return completer.future.timeout(
      _sessionTimeout,
      onTimeout: () {
        log('flutter_pdf_annotations: session timed out after $_sessionTimeout');
        if (_completer == completer) _completer = null;
        return PdfAnnotationResult.error('PDF editor session timed out');
      },
    );
  }

  static String _tempSavePath() {
    final dir = Directory(
        '${Directory.systemTemp.path}/flutter_pdf_annotations');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/pdf_annotated_${DateTime.now().millisecondsSinceEpoch}.pdf';
  }

  static Future<List<String>> _saveImagesToTemp(
      List<Uint8List> images) async {
    final paths = <String>[];
    final dir = Directory(
        '${Directory.systemTemp.path}/flutter_pdf_annotations_imgs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (int i = 0; i < images.length; i++) {
      final file = File(
          '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}_$i.png');
      await file.writeAsBytes(images[i]);
      paths.add(file.path);
    }
    return paths;
  }

  static void _cleanupTempImages(List<String> paths) {
    for (final path in paths) {
      try {
        File(path).deleteSync();
      } catch (e) {
        log('flutter_pdf_annotations: failed to delete temp image $path — $e');
      }
    }
  }
}
