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
    path: ../flutter_pdf_annotations
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
import 'package:flutter/material.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PDFViewerScreen extends StatelessWidget {
  final String pdfPath;

  const PDFViewerScreen({Key? key, required this.pdfPath}) : super(key: key);

  Future<void> _openPDF(BuildContext context) async {
    final directory = await getApplicationDocumentsDirectory();
    final savePath = path.join(directory.path, 'annotated_${DateTime.now().millisecondsSinceEpoch}.pdf');

    try {
      await FlutterPdfAnnotations.openPDF(
        filePath: pdfPath,
        savePath: savePath,
        onFileSaved: (savedPath) {
          if (savedPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF saved at: $savedPath')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save PDF')),
            );
          }
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Viewer')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _openPDF(context),
          child: const Text('Open PDF'),
        ),
      ),
    );
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

