import 'dart:developer';
import 'dart:io' as IO;
import 'package:flutter/material.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:typed_data';

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

  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  Uint8List _file = Uint8List(0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            try {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
                withData: true, // Ensure we get the file data
              );

              if (result != null && result.files.single.bytes != null) {
                // First set the initial file
                setState(() {
                  _file = result.files.single.bytes!;
                });

                final filePath = result.files.single.path;
                if (filePath != null) {
                  log(filePath);

                  final savePath = filePath.replaceAll('.pdf', '_annotated.pdf');

                  await FlutterPdfAnnotations.openPDF(
                    filePath: filePath,
                    savePath: savePath,
                    onFileSaved: (path) async {
                      if (path != null) {
                        final file = IO.File(path);
                        if (await file.exists()) {
                          final bytes = await file.readAsBytes();
                          setState(() {
                            _file = bytes;
                          });
                        }
                      }
                    },
                  );
                }
              }
            } catch (e) {
              log('Error processing PDF: $e');
              // Handle error appropriately - maybe show a snackbar
            }
          },
          child: const Icon(Icons.picture_as_pdf),
        ),
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: _file.isEmpty
            ? const Center(child: Text('No PDF selected'))
            : SfPdfViewer.memory(
          _file,
          key: _pdfViewerKey,
        ),
      ),
    );
  }
}