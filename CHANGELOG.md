## 1.2.0

* **Localization support** — native UI is now displayed in the device language. Supported: English (fallback), Arabic, Spanish, and Portuguese. No configuration needed; language is resolved automatically from the system locale.

## 1.1.0

* **Dedicated image placement screen** — tapping the image button now opens a focused single-page editor instead of overlaying on the scrollable PDF. Eliminates drag lag, snap-back glitches, and gesture conflicts with the scroll view.
* **Reduced memory usage for images** — large images are automatically downscaled to 2048px max dimension on load, and only one PDF page bitmap is held in memory during image placement. Fixes out-of-memory crashes with high-resolution images.
* **`initialPage` config option** — open the PDF at a specific zero-based page index via `PDFAnnotationConfig(initialPage: 2)`.
* **iOS annotation accuracy** — annotations now land on the correct page when zoomed or scrolled, using point-based page lookup instead of the viewport's "current page".
* **Multi-image workflow** — place multiple images across different pages in a single session. Navigate between pages, confirm each placement, and return all at once.

## 1.0.1

* Updated package description.

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
