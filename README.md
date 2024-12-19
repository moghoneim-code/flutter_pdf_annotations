# flutter_pdf_annotations

A Flutter plugin for viewing and annotating PDF documents with support for both iOS and Android. This plugin allows users to draw, highlight, and make annotations on PDF documents with a rich set of tools.

## Features

- View PDF documents
- Draw annotations with customizable pen colors and sizes
- Save annotated PDFs
- Cross-platform support (iOS & Android)
- Modern UI with floating toolbar
- Color picker for annotations
- Adjustable pen thickness
- Undo functionality
- Support for both portrait and landscape orientations

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_pdf_annotations:
    git:
      url:https://github.com/moghoneim-code/flutter_pdf_annotations.git
```

### Platform-specific setup

#### Android

Add the following permission to your Android Manifest (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

#### iOS

No additional setup required.

### Usage

```dart
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';

// Open and annotate a PDF
await FlutterPdfAnnotations.openPDF(
  filePath: '/path/to/source.pdf',
  savePath: '/path/to/save/annotated.pdf',
  onFileSaved: (savedPath) {
    if (savedPath != null) {
      print('PDF saved successfully at: $savedPath');
    } else {
      print('Failed to save PDF');
    }
  },
);
```

### Example

```dart
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
```

## Features

### Drawing Tools
- Toggle drawing mode
- Color picker for annotations
- Adjustable pen thickness
- Undo last annotation

### Navigation
- Page navigation (next/previous)
- Save/Cancel options
- Modern floating toolbar

### UI Components
- Floating toolbar with drawing tools
- Color picker dialog
- Pen size slider
- Navigation buttons

## Screenshots

[Add your screenshots here]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Issues and Feedback

Please file issues and feedback using the [GitHub Issues](https://github.com/moghoneim-code/flutter_pdf_annotations/issues).

## Author

Mohamed Ghoneim
- Email: mghoneam7@gmail.com
- GitHub: [@moghoneim-code](https://github.com/moghoneim-code)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

