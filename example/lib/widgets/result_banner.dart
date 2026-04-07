import 'package:flutter/material.dart';

/// Shown after a successful annotation — displays the saved path and
/// provides quick-access buttons to view or copy it.
class ResultBanner extends StatelessWidget {
  final String path;
  final String method;
  final VoidCallback onView;
  final VoidCallback onCopy;

  const ResultBanner({
    super.key,
    required this.path,
    required this.method,
    required this.onView,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved via $method',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  path,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: Colors.green,
            tooltip: 'Copy path',
            onPressed: onCopy,
          ),
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}
