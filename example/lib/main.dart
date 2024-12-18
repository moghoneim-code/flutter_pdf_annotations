import 'dart:developer';
import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
  }



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
            );
            if (result != null) {
              log(result.files.single.path!);
              await FlutterPdfAnnotations.openPDF(
                filePath: result.files.single.path!,
                savePath: result.files.single.path!.replaceAll('.pdf', '_annotated.pdf'),
                onFileSaved: (path) async {
                  await FlutterPdfAnnotations.openPDF(
                    filePath: result.files.single.path!.replaceAll('.pdf', '_annotated.pdf'),
                    savePath: result.files.single.path!.replaceAll('.pdf', '_annotated.pdf'),
                    onFileSaved: (path) async {
                      log('PDF saved at: $path');

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
