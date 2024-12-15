import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_pdf_annotations_method_channel.dart';

abstract class FlutterPdfAnnotationsPlatform extends PlatformInterface {
  /// Constructs a FlutterPdfAnnotationsPlatform.
  FlutterPdfAnnotationsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPdfAnnotationsPlatform _instance = MethodChannelFlutterPdfAnnotations();

  /// The default instance of [FlutterPdfAnnotationsPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterPdfAnnotations].
  static FlutterPdfAnnotationsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterPdfAnnotationsPlatform] when
  /// they register themselves.
  static set instance(FlutterPdfAnnotationsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
