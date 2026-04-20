import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';

import 'flutter_pdf_annotations_method_channel.dart';
import 'flutter_pdf_annotations_platform_interface.dart';

export 'flutter_pdf_annotations_platform_interface.dart'
    show PdfAnnotationResult, PDFAnnotationConfig, FlutterPdfAnnotationsPlatform, PdfLocale;

/// Entry point for the `flutter_pdf_annotations` plugin.
///
/// Opens a native full-screen PDF editor on iOS and Android.
/// All methods return a [PdfAnnotationResult] — check [PdfAnnotationResult.isSuccess],
/// [PdfAnnotationResult.isCancelled], or [PdfAnnotationResult.isError] to handle
/// each outcome without a try/catch.
///
/// ### Minimal example
/// ```dart
/// final result = await FlutterPdfAnnotations.openPDF(
///   filePath: '/path/to/document.pdf',
/// );
/// if (result.isSuccess) print('Saved to ${result.savedPath}');
/// ```
///
/// ### With full configuration
/// ```dart
/// final result = await FlutterPdfAnnotations.openPDF(
///   filePath: '/path/to/document.pdf',
///   savePath: '/path/to/annotated.pdf',
///   config: PDFAnnotationConfig(
///     title: 'Review Contract',
///     initialPenColor: Colors.red,
///     initialHighlightColor: Colors.yellow.withOpacity(0.5),
///     initialStrokeWidth: 3.0,
///     imagesToInsert: [await File('signature.png').readAsBytes()],
///   ),
/// );
/// ```
class FlutterPdfAnnotations {
  FlutterPdfAnnotations._();

  static final _defaultPlatform = MethodChannelFlutterPdfAnnotations();

  static FlutterPdfAnnotationsPlatform get _platform =>
      FlutterPdfAnnotationsPlatform.instance ?? _defaultPlatform;

  /// Opens the PDF at [filePath] in the native annotation editor.
  ///
  /// - [filePath] — absolute path to an existing PDF file.
  /// - [savePath] — where to write the annotated output. An auto-generated
  ///   path inside the app temp directory is used when omitted.
  /// - [config] — optional editor configuration (title, colours, images, etc.).
  ///
  /// Returns a [PdfAnnotationResult]:
  /// - [PdfAnnotationResult.isSuccess] — user tapped Save; [PdfAnnotationResult.savedPath] is the output path.
  /// - [PdfAnnotationResult.isCancelled] — user dismissed the editor without saving.
  /// - [PdfAnnotationResult.isError] — something went wrong; [PdfAnnotationResult.error] describes it.
  static Future<PdfAnnotationResult> openPDF({
    required String filePath,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    if (!File(filePath).existsSync()) {
      log('flutter_pdf_annotations: source file not found: $filePath');
      return PdfAnnotationResult.error(
          'Source file does not exist: $filePath');
    }
    try {
      return await _platform.openPDF(
          filePath: filePath, savePath: savePath, config: config);
    } catch (e) {
      log('flutter_pdf_annotations: openPDF threw — $e');
      return PdfAnnotationResult.error(e.toString());
    }
  }

  /// Opens a PDF supplied as raw [bytes] in the native annotation editor.
  ///
  /// The bytes are written to a private temp file which is automatically
  /// deleted once the editor session ends (success, cancel, or error).
  ///
  /// - [bytes] — raw PDF bytes, e.g. from a network response or database blob.
  /// - [savePath] — see [openPDF].
  /// - [config] — see [openPDF].
  static Future<PdfAnnotationResult> openFromBytes({
    required Uint8List bytes,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    final dir = Directory(
        '${Directory.systemTemp.path}/flutter_pdf_annotations');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tempFile = File(
        '${dir.path}/pdf_in_${DateTime.now().millisecondsSinceEpoch}.pdf');
    try {
      await tempFile.writeAsBytes(bytes);
    } catch (e) {
      return PdfAnnotationResult.error('Failed to write PDF to temp file: $e');
    }
    try {
      return await openPDF(
          filePath: tempFile.path, savePath: savePath, config: config);
    } finally {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Downloads a PDF from [url] and opens it in the native annotation editor.
  ///
  /// Uses `dart:io` [HttpClient] — no additional networking packages required.
  /// The downloaded file is stored in a private temp file and deleted after
  /// the session ends.
  ///
  /// Requires the `INTERNET` permission on Android
  /// (`<uses-permission android:name="android.permission.INTERNET"/>`).
  ///
  /// - [url] — a publicly accessible PDF URL (`http` or `https`).
  /// - [headers] — optional HTTP request headers, e.g. `{'Authorization': 'Bearer token'}`.
  /// - [savePath] — see [openPDF].
  /// - [config] — see [openPDF].
  static Future<PdfAnnotationResult> openFromUrl({
    required String url,
    Map<String, String>? headers,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      headers?.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close();
      if (response.statusCode != 200) {
        client.close();
        return PdfAnnotationResult.error(
            'HTTP ${response.statusCode} downloading PDF from $url');
      }
      final bytes =
          await response.fold<List<int>>([], (acc, c) => acc..addAll(c));
      client.close();
      return openFromBytes(
          bytes: Uint8List.fromList(bytes),
          savePath: savePath,
          config: config);
    } catch (e) {
      return PdfAnnotationResult.error('Error downloading PDF: $e');
    }
  }

  /// Opens a PDF bundled as a Flutter asset in the native annotation editor.
  ///
  /// [assetPath] must match a key declared under `flutter → assets` in
  /// `pubspec.yaml`, e.g. `'assets/sample.pdf'`.
  ///
  /// - [savePath] — see [openPDF].
  /// - [config] — see [openPDF].
  static Future<PdfAnnotationResult> openFromAsset({
    required String assetPath,
    String? savePath,
    PDFAnnotationConfig? config,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      return openFromBytes(
          bytes: data.buffer.asUint8List(),
          savePath: savePath,
          config: config);
    } catch (e) {
      return PdfAnnotationResult.error(
          'Error loading asset "$assetPath": $e');
    }
  }
}
