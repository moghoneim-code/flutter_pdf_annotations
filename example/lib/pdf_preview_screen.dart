import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfPreviewScreen extends StatelessWidget {
  final String path;
  final String method;

  const PdfPreviewScreen({
    super.key,
    required this.path,
    required this.method,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved PDF Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy file path',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Path copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PathBanner(path: path, method: method),
          Expanded(
            child: SfPdfViewer.file(File(path), key: ValueKey(path)),
          ),
        ],
      ),
    );
  }
}

class _PathBanner extends StatelessWidget {
  final String path;
  final String method;

  const _PathBanner({required this.path, required this.method});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved via: $method',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            path,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: cs.onPrimaryContainer.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}
