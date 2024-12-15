import 'dart:developer';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _flutterPdfAnnotationsPlugin = FlutterPdfAnnotations();

  @override
  void initState() {
    super.initState();
    loadImages();
  }

  final List<String> _imagesPath = [
    'assets/1.jpg',
    'assets/2.jpg',
    'assets/3.jpg',
  ];
  final List<Uint8List> _images = [];

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> loadImages() async {
    for (final imagePath in _imagesPath) {
      final ByteData data = await rootBundle.load(imagePath);
      final Uint8List bytes = data.buffer.asUint8List();
      _images.add(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            FlutterPdfAnnotations flutterPdfAnnotations = FlutterPdfAnnotations();

            FilePickerResult? result = await FilePicker.platform.pickFiles();
            if (result != null) {
              log(result.files.single.path!);
              await FlutterPdfAnnotations.openPDF(
                savePath: result.files.single.path!,
                filePath: result.files.single.path!,
                onFileSaved: (path) {
                  FlutterPdfAnnotations.openPDF(
                    savePath: path,
                    filePath: path,
                    onFileSaved: (path) {
                      log('File saved at: $path');
                    },
                  );
                },
              );
            }
          },
          child: const Icon(Icons.picture_as_pdf),
        ),
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: const Center(
          child: Text('Running on: '),
        ),
      ),
    );
  }
}
