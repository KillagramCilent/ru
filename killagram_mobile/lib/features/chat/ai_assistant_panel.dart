import 'package:flutter/material.dart';

class AiAssistantPanel extends StatelessWidget {
  const AiAssistantPanel({
    super.key,
    required this.collapsed,
    required this.proEnabled,
    required this.loading,
    required this.output,
    required this.error,
    required this.onToggle,
    required this.onSummarize,
    required this.onGenerateReply,
    required this.onRewriteFormal,
    required this.onRewriteShort,
    required this.onRewriteClear,
    required this.onExtractTasks,
  });

  final bool collapsed;
  final bool proEnabled;
  final bool loading;
  final String? output;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onSummarize;
  final VoidCallback onGenerateReply;
  final VoidCallback onRewriteFormal;
  final VoidCallback onRewriteShort;
  final VoidCallback onRewriteClear;
  final VoidCallback onExtractTasks;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? 48 : 340,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: collapsed
          ? Center(
              child: IconButton(
                tooltip: 'Open AI panel',
                onPressed: onToggle,
                icon: const Icon(Icons.auto_awesome),
              ),
            )
          : Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('AI Assistant'),
                  trailing: IconButton(
                    tooltip: 'Collapse',
                    onPressed: onToggle,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
                const Divider(height: 1),
                if (!proEnabled)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FEATURE_LOCKED', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('AI Assistant requires Killagram Pro.'),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(onPressed: onSummarize, child: const Text('Summarize')),
                        FilledButton.tonal(onPressed: onGenerateReply, child: const Text('Reply suggestion')),
                        FilledButton.tonal(onPressed: onRewriteFormal, child: const Text('Rewrite formal')),
                        FilledButton.tonal(onPressed: onRewriteShort, child: const Text('Rewrite short')),
                        FilledButton.tonal(onPressed: onRewriteClear, child: const Text('Rewrite clear')),
                        FilledButton.tonal(onPressed: onExtractTasks, child: const Text('Extract tasks')),
                      ],
                    ),
                  ),
                if (loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        error != null && error!.isNotEmpty
                            ? error!
                            : (output == null || output!.isEmpty ? 'No AI output yet.' : output!),
                        style: TextStyle(color: error != null ? Colors.red : null),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
