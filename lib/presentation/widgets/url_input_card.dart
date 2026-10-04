import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onAnalyze;

  const UrlInputCard({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onAnalyze,
  });

  Future<void> _pasteFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    if (data?.text != null && data!.text!.isNotEmpty) {
      controller.text = data.text!.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace pegado desde el portapapeles'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Enlace del video o audio',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !isLoading,
                    decoration: InputDecoration(
                      hintText: 'Pega la URL aquí (YouTube, TikTok, Twitter, Instagram...)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => controller.clear(),
                            )
                          : null,
                    ),
                    onSubmitted: (_) => onAnalyze(),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : () => _pasteFromClipboard(context),
                  icon: const Icon(Icons.paste_rounded),
                  label: const Text('Pegar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isLoading ? null : onAnalyze,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.analytics_outlined),
                  label: Text(isLoading ? 'Analizando...' : 'Analizar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
