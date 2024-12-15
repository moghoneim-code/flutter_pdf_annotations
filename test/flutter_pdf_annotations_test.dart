import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations_platform_interface.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterPdfAnnotationsPlatform
    with MockPlatformInterfaceMixin
    implements FlutterPdfAnnotationsPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterPdfAnnotationsPlatform initialPlatform = FlutterPdfAnnotationsPlatform.instance;

  test('$MethodChannelFlutterPdfAnnotations is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterPdfAnnotations>());
  });

  test('getPlatformVersion', () async {
    FlutterPdfAnnotations flutterPdfAnnotationsPlugin = FlutterPdfAnnotations();
    MockFlutterPdfAnnotationsPlatform fakePlatform = MockFlutterPdfAnnotationsPlatform();
    FlutterPdfAnnotationsPlatform.instance = fakePlatform;

    expect(await flutterPdfAnnotationsPlugin.getPlatformVersion(), '42');
  });
}
