## 1.0.0

* Initial stable release.
* Open PDFs from file path, raw bytes, URL, or Flutter asset.
* Freehand pen annotations with custom colour, stroke width, and eraser.
* Highlight tool with adjustable opacity.
* Image stamping — place, resize, and confirm/delete image overlays per page.
* Undo stack for all annotation types.
* Save annotated PDF to a caller-specified path; auto-generated path when omitted.
* Share annotated PDF via the native share sheet.
* Typed result API (`PdfAnnotationResult`) — distinguish success, cancellation, and errors without try/catch.
* `PDFAnnotationConfig` for initial pen colour, highlight colour, stroke width, and image assets.
* Android implementation using `PdfRenderer` with a custom `DrawingView` overlay.
* iOS implementation using `PDFKit` with ink annotations and CoreGraphics flattening.
* Platform interface (`FlutterPdfAnnotationsPlatform`) for testability and future platform support.
* Temp files created for `openFromBytes` / `openFromUrl` / `openFromAsset` are automatically deleted after the session.
* 10-minute session timeout — Dart `Future` never hangs indefinitely.
