## 0.0.1

* Initial release.
* Open local PDF files for freehand annotation, highlighting, and image insertion.
* Android implementation using `PdfRenderer` with custom `DrawingView` overlay.
* iOS implementation using `PDFKit` with ink annotations and CoreGraphics flattening.
* Support for opening PDFs from file path, raw bytes, URL, or Flutter asset.
* Configurable initial pen/highlight color and stroke width via `PDFAnnotationConfig`.
* Save annotated PDF to a specified path; share via native share sheet.
* Floating annotation toolbar with draw, highlight, erase, color picker, and size presets.
