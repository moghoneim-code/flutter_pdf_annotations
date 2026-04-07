import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A card demonstrating one API call.
///
/// Shows an icon, title, description, and a collapsible code snippet.
/// The [onTry] button triggers the live demo.
class ExampleCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String snippet;
  final bool busy;
  final VoidCallback? onTry;

  const ExampleCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.snippet,
    required this.busy,
    this.onTry,
  });

  @override
  State<ExampleCard> createState() => _ExampleCardState();
}

class _ExampleCardState extends State<ExampleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),

            // ── Description ─────────────────────────────────────────────────
            const SizedBox(height: 10),
            Text(
              widget.description,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            // ── Show code toggle ─────────────────────────────────────────────
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Hide code' : 'Show code',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Code block ──────────────────────────────────────────────────
            if (_expanded) ...[
              const SizedBox(height: 8),
              _CodeBlock(snippet: widget.snippet),
            ],

            // ── Try it button ────────────────────────────────────────────────
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: widget.busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Try it'),
                onPressed: widget.busy ? null : widget.onTry,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dark code block with copy button ─────────────────────────────────────────

class _CodeBlock extends StatefulWidget {
  final String snippet;
  const _CodeBlock({required this.snippet});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.snippet));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 48, 12),
            child: Text(
              widget.snippet,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.6,
                color: Color(0xFFCDD6F4),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
                color: _copied
                    ? const Color(0xFFA6E3A1)
                    : const Color(0xFF6C7086),
              ),
              tooltip: _copied ? 'Copied!' : 'Copy',
              onPressed: _copy,
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
