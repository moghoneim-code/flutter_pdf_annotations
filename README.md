# flutter_pdf_annotations

A Flutter plugin for opening and annotating PDF files natively on iOS and Android.

The plugin presents a full-screen native editor with freehand drawing, highlighting,
image stamping, erasing, undo, color picker, and pen-size presets — then saves the
annotated PDF back to a file path of your choice.

## Features

- Freehand pen annotations with custom colour and stroke width
- Highlight tool with adjustable opacity
- Stamp images (signatures, logos, etc.) onto any page
- Erase individual annotations
- Undo stack
- Save annotated PDF to any writable path
- Share annotated PDF via the native share sheet
- Open PDFs from a file path, raw bytes, a URL, or a Flutter asset
- Typed result — distinguish success, user-cancel, and errors without try/catch

## Platform Support

| Android | iOS |
|---------|-----|
| API 21+ | iOS 14+ |

## Installation

```yaml
dependencies:
  flutter_pdf_annotations: ^1.0.0
```

## Platform Setup

### Android

No permissions are required for paths inside the app's own directories
(`getExternalFilesDir`, `filesDir`). If you intend to save to a custom
path outside those directories the path-traversal guard will reject it.

### iOS

Add usage descriptions to your `ios/Runner/Info.plist` if you allow the
user to pick images for stamping:

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
  savePath: '/path/to/annotated.pdf', // optional — auto-generated if omitted
  config: PDFAnnotationConfig(
    title: 'Review Contract',
    initialPenColor: Colors.red,
    initialHighlightColor: Colors.yellow.withOpacity(0.5),
    initialStrokeWidth: 3.0, // 3 → S, 8 → M, 18 → L
  ),
);
```

### With image stamps (e.g. a signature)

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
final Uint8List pdfBytes = ...; // from network, database, etc.

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
// pubspec.yaml must declare: assets: [assets/sample.pdf]

final result = await FlutterPdfAnnotations.openFromAsset(
  assetPath: 'assets/sample.pdf',
);
```

## API Reference

### `FlutterPdfAnnotations`

| Method | Description |
|--------|-------------|
| `openPDF` | Open a PDF from a file path |
| `openFromBytes` | Open a PDF from `Uint8List` |
| `openFromUrl` | Download and open a PDF from a URL |
| `openFromAsset` | Open a PDF bundled as a Flutter asset |

All methods return `Future<PdfAnnotationResult>`.

### `PdfAnnotationResult`

| Property | Type | Description |
|----------|------|-------------|
| `isSuccess` | `bool` | User saved the PDF |
| `savedPath` | `String?` | Output file path (non-null when `isSuccess`) |
| `isCancelled` | `bool` | User dismissed without saving |
| `isError` | `bool` | An error occurred |
| `error` | `String?` | Error description (non-null when `isError`) |

### `PDFAnnotationConfig`

| Parameter | Type | Description |
|-----------|------|-------------|
| `title` | `String?` | Navigation bar title |
| `initialPenColor` | `Color?` | Starting pen colour |
| `initialHighlightColor` | `Color?` | Starting highlight colour (include alpha) |
| `initialStrokeWidth` | `double?` | Starting stroke width (3 → S, 8 → M, 18 → L) |
| `imagesToInsert` | `List<Uint8List>?` | Images available for stamping |

## Contributing

Pull requests are welcome. Please open an issue first to discuss the change.

## License

[MIT](LICENSE) © 2025 Mohamed Ghoneim
