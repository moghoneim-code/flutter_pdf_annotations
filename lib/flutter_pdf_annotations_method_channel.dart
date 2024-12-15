import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_pdf_annotations_platform_interface.dart';

/// An implementation of [FlutterPdfAnnotationsPlatform] that uses method channels.
class MethodChannelFlutterPdfAnnotations extends FlutterPdfAnnotationsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pdf_annotations');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
