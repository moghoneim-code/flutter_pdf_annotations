import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdf_annotations/flutter_pdf_annotations.dart';

import 'pdf_preview_screen.dart';
import 'widgets/example_card.dart';
import 'widgets/package_banner.dart';
import 'widgets/result_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _savedPath;
  String? _lastMethod;
  bool _busy = false;

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String?> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    return result?.files.single.path;
  }

  /// Wraps any demo action: sets busy flag, shows result snackbars.
  Future<void> _run(
      String method, Future<PdfAnnotationResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() {
          _savedPath = result.savedPath;
          _lastMethod = method;
        });
      } else if (result.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelled — no file saved.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result.error}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── API demos ──────────────────────────────────────────────────────────────

  Future<PdfAnnotationResult> _demoBasic() async {
    final path = await _pickPdf();
    if (path == null) return PdfAnnotationResult.cancelled();
    return FlutterPdfAnnotations.openPDF(filePath: path);
  }

  Future<PdfAnnotationResult> _demoConfig() async {
    final path = await _pickPdf();
    if (path == null) return PdfAnnotationResult.cancelled();
    return FlutterPdfAnnotations.openPDF(
      filePath: path,

      config: const PDFAnnotationConfig(
        title: 'My Document',
        initialPenColor: Colors.indigo,
        initialHighlightColor: Color(0x8000BCD4), // cyan, 50 % alpha
        initialStrokeWidth: 3.0,
      ),
    );
  }

  Future<PdfAnnotationResult> _demoImages() async {
    final path = await _pickPdf();
    if (path == null) return PdfAnnotationResult.cancelled();

    final imgResult = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (imgResult == null) return PdfAnnotationResult.cancelled();

    final images = imgResult.files
        .where((f) => f.bytes != null)
        .map((f) => f.bytes!)
        .toList();
    if (images.isEmpty) return PdfAnnotationResult.cancelled();

    return FlutterPdfAnnotations.openPDF(
      filePath: path,
      config: PDFAnnotationConfig(
        title: 'Stamp Images',
        locale: PdfLocale.arabic,
        imagesToInsert: images,
      ),
    );
  }

  Future<PdfAnnotationResult> _demoUrl() async {
    if (!mounted) return PdfAnnotationResult.cancelled();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Downloading PDF…')));

    final result = await FlutterPdfAnnotations.openFromUrl(
      url: 'https://www.rd.usda.gov/sites/default/files/pdf-sample_0.pdf',
      config: const PDFAnnotationConfig(title: 'Remote PDF'),
    );

    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    return result;
  }

  Future<PdfAnnotationResult> _demoAsset() =>
      FlutterPdfAnnotations.openFromAsset(
        assetPath: 'assets/sample.pdf',

        config: const PDFAnnotationConfig(title: 'Asset PDF',),
      );

  Future<PdfAnnotationResult> _demoBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result?.files.single.bytes == null) return PdfAnnotationResult.cancelled();
    return FlutterPdfAnnotations.openFromBytes(
      bytes: result!.files.single.bytes!,
      config: const PDFAnnotationConfig(title: 'In-Memory PDF'),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('flutter_pdf_annotations'),
            actions: [
              if (_savedPath != null)
                IconButton(
                  icon: const Icon(Icons.preview_rounded),
                  tooltip: 'View last saved PDF',
                  onPressed: _openPreview,
                ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 4),
              PackageBanner(busy: _busy),
              if (_savedPath != null)
                ResultBanner(
                  path: _savedPath!,
                  method: _lastMethod!,
                  onView: _openPreview,
                  onCopy: () => _copyToClipboard(_savedPath!),
                ),
              const _SectionLabel('API Examples'),
              ExampleCard(
                icon: Icons.folder_open_rounded,
                color: const Color(0xFF2196F3),
                title: 'openPDF  —  local file',
                description:
                    'The simplest usage. Pick any PDF from the device and '
                    'open the annotation editor. Returns the saved-file path, '
                    'or null if the user cancels.',
                snippet: """final savedPath = await FlutterPdfAnnotations.openPDF(
  filePath: '/path/to/document.pdf',
);
// savedPath is null when the user taps Cancel""",
                busy: _busy,
                onTry: () => _run('openPDF', _demoBasic),
              ),
              ExampleCard(
                icon: Icons.tune_rounded,
                color: const Color(0xFF9C27B0),
                title: 'openPDF  +  PDFAnnotationConfig',
                description:
                    'Customise the editor defaults: toolbar title, pen color, '
                    'highlight color (include alpha for transparency), and '
                    'stroke width (3 → S, 8 → M, 18 → L).',
                snippet: """final savedPath = await FlutterPdfAnnotations.openPDF(
  filePath: filePath,
  config: const PDFAnnotationConfig(
    title: 'My Document',
    initialPenColor: Colors.indigo,
    initialHighlightColor: Color(0x8000BCD4), // 50 % alpha
    initialStrokeWidth: 3.0,
  ),
);""",
                busy: _busy,
                onTry: () => _run('openPDF + config', _demoConfig),
              ),
              ExampleCard(
                icon: Icons.add_photo_alternate_rounded,
                color: const Color(0xFF4CAF50),
                title: 'openPDF  +  imagesToInsert',
                description:
                    'Provide one or more images as Uint8List. An Image button '
                    'appears in the editor toolbar. The user can place, resize, '
                    'accept (✓) or delete (✕) each stamp on any page.',
                snippet: """final savedPath = await FlutterPdfAnnotations.openPDF(
  filePath: filePath,
  config: PDFAnnotationConfig(
    title: 'Stamp Images',
    imagesToInsert: [
      await File('signature.png').readAsBytes(),
    ],
  ),
);""",
                busy: _busy,
                onTry: () => _run('openPDF + images', _demoImages),
              ),
              ExampleCard(
                icon: Icons.cloud_download_rounded,
                color: const Color(0xFF00BCD4),
                title: 'openFromUrl',
                description:
                    'The plugin downloads the PDF from the given URL into a '
                    'temp file, then opens the editor. No manual HTTP request '
                    'needed. Requires INTERNET permission on Android.',
                snippet: """final savedPath = await FlutterPdfAnnotations.openFromUrl(
  url: 'https://example.com/document.pdf',
  config: const PDFAnnotationConfig(title: 'Remote PDF'),
);""",
                busy: _busy,
                onTry: () => _run('openFromUrl', _demoUrl),
              ),
              ExampleCard(
                icon: Icons.inventory_2_rounded,
                color: const Color(0xFFFF9800),
                title: 'openFromAsset',
                description:
                    'Open a PDF bundled with the app. The asset path must be '
                    'declared under flutter → assets in pubspec.yaml.',
                snippet: """// pubspec.yaml ─────────────────────
// flutter:
//   assets:
//     - assets/sample.pdf

final savedPath = await FlutterPdfAnnotations.openFromAsset(
  assetPath: 'assets/sample.pdf',
  config: const PDFAnnotationConfig(title: 'Asset PDF'),
);""",
                busy: _busy,
                onTry: () => _run('openFromAsset', _demoAsset),
              ),
              ExampleCard(
                icon: Icons.memory_rounded,
                color: const Color(0xFFF44336),
                title: 'openFromBytes',
                description:
                    'Pass a PDF already in memory as a Uint8List — useful '
                    'when the file comes from a network response, database '
                    'blob, or any in-process source.',
                snippet: """final bytes = await http.readBytes(Uri.parse(url));

final savedPath = await FlutterPdfAnnotations.openFromBytes(
  bytes: bytes,
  config: const PDFAnnotationConfig(title: 'In-Memory PDF'),
);""",
                busy: _busy,
                onTry: () => _run('openFromBytes', _demoBytes),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }

  void _openPreview() {
    if (_savedPath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          path: _savedPath!,
          method: _lastMethod!,
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Path copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

// ── Section label (local, only used on this screen) ───────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
