import 'dart:developer';
import 'dart:io' as IO;
import 'package:flutter/material.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  late PdfViewerController _pdfViewerController;
  String? _currentPdfPath;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
  }

  Future<void> _handlePDFSelection() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        log('Original file path: $filePath');
        final savePath = filePath.replaceAll('.pdf', '_annotated.pdf');

        await FlutterPdfAnnotations.openPDF(
          filePath: filePath,
          savePath: savePath,
          onFileSaved: (path) async {
            if (path != null) {
              log('PDF saved at: $path');
              // First clear the current PDF
              setState(() {
                _currentPdfPath = null;
              });

              // Wait for the widget to rebuild
              await Future.delayed(const Duration(milliseconds: 100));

              if (!mounted) return;

              // Load the new PDF
              setState(() {
                _currentPdfPath = path;
              });

              // Reset the controller
              _pdfViewerController = PdfViewerController();
            }
          },
        );
      }
    } catch (e) {
      log('Error processing PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: _handlePDFSelection,
          child: const Icon(Icons.picture_as_pdf),
        ),
        appBar: AppBar(
          title: const Text('Plugin example app'),
          actions: [
            if (_currentPdfPath != null)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  // Force refresh
                  setState(() {
                    final currentPath = _currentPdfPath;
                    _currentPdfPath = null;
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        setState(() {
                          _currentPdfPath = currentPath;
                        });
                      }
                    });
                  });
                },
              ),
          ],
        ),
        body: _currentPdfPath == null
            ? const Center(child: Text('Click the FAB to select a PDF to annotate'))
            : SfPdfViewer.file(
          IO.File(_currentPdfPath!),
          key: ValueKey(_currentPdfPath),
          controller: _pdfViewerController,
          onDocumentLoaded: (details) {
            log('PDF loaded successfully');
          },
          onDocumentLoadFailed: (details) {
            log('PDF load failed: ${details.error}');
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }
}