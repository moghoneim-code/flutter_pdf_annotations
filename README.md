# flutter_pdf_annotations

[![pub package](https://img.shields.io/pub/v/flutter_pdf_annotations.svg)](https://pub.dev/packages/flutter_pdf_annotations)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/moghoneim-code/flutter_pdf_annotations/blob/main/LICENSE)
[![platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](https://pub.dev/packages/flutter_pdf_annotations)

A Flutter plugin for opening and annotating PDF files natively on iOS and Android.

Presents a full-screen native editor with freehand drawing, highlighting, image stamping, erasing, undo, color picker, and pen-size presets — then saves the annotated PDF back to a file path of your choice.

## Features

| Feature | Description |
|---------|-------------|
| Freehand pen | Draw with custom colour and stroke width |
| Highlighter | Semi-transparent highlight with adjustable opacity |
| Image stamps | Place signatures, logos, or images — resize, accept, or delete |
| Eraser | Remove individual annotations |
| Undo | Step back through all annotation types |
| Save | Write the annotated PDF to any writable path |
| Share | Share via the native share sheet |
| Multiple sources | Open from file path, raw bytes, URL, or Flutter asset |
| Typed results | Distinguish success, cancellation, and errors without try/catch |

## Platform Support

| Android | iOS |
|---------|-----|
| API 21+ | iOS 14+ |

## Getting Started

### 1. Install

```yaml
dependencies:
  flutter_pdf_annotations: ^1.0.0
```

```bash
flutter pub get
```

### 2. Platform Setup

#### Android

No extra permissions or setup needed for paths inside the app's own directories (`getExternalFilesDir`, `filesDir`).

If you plan to download PDFs from the internet using `openFromUrl`, make sure your `AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

#### iOS

If you allow the user to pick images for stamping, add to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select images to insert into PDF annotations</string>
```

## Usage

### Open a local PDF

```dart
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';

final result = await FlutterPdfAnnotations.openPDF(
  filePath: '/path/to/document.pdf',
);

if (result.isSuccess) {
  print('Saved to: ${result.savedPath}');
} else if (result.isCancelled) {
  print('User cancelled');
} else {
  print('Error: ${result.error}');
}
```

### With configuration

```dart
final result = await FlutterPdfAnnotations.openPDF(
  filePath: '/path/to/document.pdf',
  savePath: '/path/to/annotated.pdf',
  config: PDFAnnotationConfig(
    title: 'Review Contract',
    initialPenColor: Colors.red,
    initialHighlightColor: Colors.yellow.withOpacity(0.5),
    initialStrokeWidth: 3.0,
  ),
);
```

### With image stamps

```dart
final signatureBytes = await File('signature.png').readAsBytes();

final result = await FlutterPdfAnnotations.openPDF(
  filePath: '/path/to/document.pdf',
  config: PDFAnnotationConfig(
    title: 'Sign Document',
    imagesToInsert: [signatureBytes],
  ),
);
```

### From raw bytes

```dart
final Uint8List pdfBytes = /* from network, database, etc. */;

final result = await FlutterPdfAnnotations.openFromBytes(
  bytes: pdfBytes,
  config: PDFAnnotationConfig(title: 'In-Memory PDF'),
);
```

### From a URL

```dart
final result = await FlutterPdfAnnotations.openFromUrl(
  url: 'https://example.com/document.pdf',
  config: PDFAnnotationConfig(title: 'Remote PDF'),
);
```

### From a Flutter asset

```dart
// Declare in pubspec.yaml:
//   flutter:
//     assets:
//       - assets/sample.pdf

final result = await FlutterPdfAnnotations.openFromAsset(
  assetPath: 'assets/sample.pdf',
);
```

## API Reference

### FlutterPdfAnnotations

| Method | Description |
|--------|-------------|
| `openPDF({filePath, savePath?, config?})` | Open a PDF from a local file path |
| `openFromBytes({bytes, savePath?, config?})` | Open a PDF from `Uint8List` bytes |
| `openFromUrl({url, savePath?, config?})` | Download and open a PDF from a URL |
| `openFromAsset({assetPath, savePath?, config?})` | Open a PDF bundled as a Flutter asset |

All methods return `Future<PdfAnnotationResult>`.

### PdfAnnotationResult

| Property | Type | Description |
|----------|------|-------------|
| `isSuccess` | `bool` | `true` when the user saved — `savedPath` is non-null |
| `savedPath` | `String?` | Output file path |
| `isCancelled` | `bool` | `true` when the user dismissed without saving |
| `isError` | `bool` | `true` when an error occurred |
| `error` | `String?` | Error description |

### PDFAnnotationConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | `String?` | `'PDF Annotations'` | Editor navigation bar title |
| `initialPenColor` | `Color?` | Red | Starting pen colour |
| `initialHighlightColor` | `Color?` | Yellow (50% opacity) | Starting highlight colour (include alpha) |
| `initialStrokeWidth` | `double?` | `8.0` (M) | Starting stroke width — `3.0` (S), `8.0` (M), `18.0` (L) |
| `imagesToInsert` | `List<Uint8List>?` | `null` | Images available for stamping (PNG, JPEG, etc.) |

## Contributing

Pull requests are welcome. Please open an issue first to discuss the change.

## License

[MIT](LICENSE) &copy; 2025 Mohamed Ghoneim
