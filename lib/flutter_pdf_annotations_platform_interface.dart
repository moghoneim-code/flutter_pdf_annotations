import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The outcome of a PDF annotation session.
///
/// Exactly one of [isSuccess], [isCancelled], or [isError] is true.
///
/// ```dart
/// final result = await FlutterPdfAnnotations.openPDF(filePath: path);
///
/// if (result.isSuccess) {
///   print('Saved to ${result.savedPath}');
/// } else if (result.isCancelled) {
///   print('User cancelled');
/// } else {
///   print('Error: ${result.error}');
/// }
/// ```
class PdfAnnotationResult {
  /// The path of the saved annotated PDF.
  ///
  /// Non-null only when [isSuccess] is `true`.
  final String? savedPath;

  /// Whether the user closed the editor without saving.
  final bool cancelled;

  /// A human-readable description of the error.
  ///
  /// Non-null only when [isError] is `true`.
  final String? error;

  const PdfAnnotationResult._({
    this.savedPath,
    this.cancelled = false,
    this.error,
  });

  /// Creates a successful result with the path of the saved PDF.
  factory PdfAnnotationResult.success(String path) =>
      PdfAnnotationResult._(savedPath: path);

  /// Creates a result representing user cancellation (no file saved).
  factory PdfAnnotationResult.cancelled() =>
      const PdfAnnotationResult._(cancelled: true);

  /// Creates an error result with a human-readable [message].
  factory PdfAnnotationResult.error(String message) =>
      PdfAnnotationResult._(error: message);

  /// `true` when the user saved the PDF. [savedPath] is non-null.
  bool get isSuccess => savedPath != null;

  /// `true` when the user dismissed the editor without saving.
  bool get isCancelled => cancelled && savedPath == null && error == null;

  /// `true` when an error prevented the operation from completing.
  /// [error] contains a description.
  bool get isError => error != null;

  @override
  String toString() {
    if (isSuccess) return 'PdfAnnotationResult.success($savedPath)';
    if (isCancelled) return 'PdfAnnotationResult.cancelled()';
    return 'PdfAnnotationResult.error($error)';
  }
}

/// Optional configuration for the PDF annotation editor.
///
/// Pass an instance to any `FlutterPdfAnnotations` method via the `config`
/// parameter to pre-configure the editor's initial state.
///
/// ```dart
/// FlutterPdfAnnotations.openPDF(
///   filePath: path,
///   config: PDFAnnotationConfig(
///     title: 'Review Contract',
///     initialPenColor: Colors.red,
///     initialHighlightColor: Colors.yellow.withOpacity(0.5),
///     initialStrokeWidth: 3.0,
///   ),
/// );
/// ```
/// Language used for the native annotation editor UI.
///
/// Pass to [PDFAnnotationConfig.locale]. When omitted the device locale
/// is used, falling back to [PdfLocale.english] for unsupported languages.
enum PdfLocale {
  english('en'),
  arabic('ar'),
  spanish('es'),
  portuguese('pt');

  /// BCP-47 language tag sent to the native side.
  final String code;
  const PdfLocale(this.code);
}

class PDFAnnotationConfig {
  /// Title displayed in the editor's navigation bar.
  ///
  /// Defaults to `'PDF Annotations'` when omitted.
  final String? title;

  /// Initial pen colour. Include the desired alpha channel in the value.
  ///
  /// Defaults to red when omitted.
  final Color? initialPenColor;

  /// Initial highlight colour.
  ///
  /// Include the desired alpha channel for transparency, e.g.
  /// `Colors.yellow.withOpacity(0.5)`.
  final Color? initialHighlightColor;

  /// Initial stroke width.
  ///
  /// The nearest preset is selected automatically:
  /// `3.0` → S, `8.0` → M, `18.0` → L. Defaults to M when omitted.
  final double? initialStrokeWidth;

  /// Images that the user can stamp onto PDF pages.
  ///
  /// Each element is raw image bytes (PNG, JPEG, etc.) as a [Uint8List].
  /// An **Image** button appears in the toolbar when this list is non-empty.
  /// The user can place, resize, accept (✓) or delete (✕) each stamp.
  final List<Uint8List>? imagesToInsert;

  /// Zero-based page index to open initially.
  ///
  /// For example, `initialPage: 2` opens the third page. Out-of-range values
  /// are clamped to the valid range (falls back to the first page).
  final int initialPage;

  /// Language for the editor UI.
  ///
  /// When `null` the device locale is used, falling back to [PdfLocale.english]
  /// if the device language is not supported.
  final PdfLocale? locale;

  const PDFAnnotationConfig({
    this.title,
    this.initialPenColor,
    this.initialHighlightColor,
    this.initialStrokeWidth,
    this.imagesToInsert,
    this.initialPage = 0,
    this.locale,
  });

  /// Serialises config fields to pass over the method channel.
  Map<String, dynamic> toMap() => {
        if (title != null) 'title': title,
        // toSigned(32) ensures the value fits in Int32 on both native platforms
        if (initialPenColor != null)
          'initialPenColor': initialPenColor!.toARGB32().toSigned(32),
        if (initialHighlightColor != null)
          'initialHighlightColor':
              initialHighlightColor!.toARGB32().toSigned(32),
        if (initialStrokeWidth != null) 'initialStrokeWidth': initialStrokeWidth,
        if (initialPage != 0) 'initialPage': initialPage,
        if (locale != null) 'locale': locale!.code,
      };
}

/// Abstract platform interface for the `flutter_pdf_annotations` plugin.
///
/// Consumers should use [FlutterPdfAnnotations] rather than this class
/// directly. Override [instance] in tests to inject a mock implementation.
abstract class FlutterPdfAnnotationsPlatform extends PlatformInterface {
  /// Constructs a platform implementation. Subclasses must call `super()`.
  FlutterPdfAnnotationsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPdfAnnotationsPlatform? _instance;

  /// The active platform implementation, or `null` if not yet set.
  ///
  /// [FlutterPdfAnnotations] falls back to the built-in method-channel
  /// implementation when this is `null`.
  static FlutterPdfAnnotationsPlatform? get instance => _instance;

  /// Override the platform implementation.
  ///
  /// Useful in unit tests:
  /// ```dart
  /// FlutterPdfAnnotationsPlatform.instance = MockPdfAnnotationsPlatform();
  /// ```
  static set instance(FlutterPdfAnnotationsPlatform? platform) {
    if (platform != null) PlatformInterface.verifyToken(platform, _token);
    _instance = platform;
  }

  /// Opens [filePath] in the native annotation editor.
  ///
  /// See [FlutterPdfAnnotations.openPDF] for full documentation.
  Future<PdfAnnotationResult> openPDF({
    required String filePath,
    String? savePath,
    PDFAnnotationConfig? config,
  });
}
