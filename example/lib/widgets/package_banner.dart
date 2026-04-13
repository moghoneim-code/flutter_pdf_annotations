import 'package:flutter/material.dart';

/// Displays the package name, a short description, and feature chips.
/// Shows a loading spinner while [busy] is true.
class PackageBanner extends StatelessWidget {
  final bool busy;

  const PackageBanner({super.key, required this.busy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.draw_rounded, color: cs.onPrimaryContainer, size: 18),
              const SizedBox(width: 8),
              Text(
                'flutter_pdf_annotations',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimaryContainer,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A Flutter plugin for native PDF annotation on iOS and Android. '
            'Tap any card below to try a feature, then expand "Show code" '
            'to see the exact API call.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onPrimaryContainer.withValues(alpha:0.85),
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _FeatureChip('Freehand drawing'),
              _FeatureChip('Highlighting'),
              _FeatureChip('Eraser'),
              _FeatureChip('Image stamps'),
              _FeatureChip('iOS & Android'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String label;
  const _FeatureChip(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.onPrimaryContainer.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}
