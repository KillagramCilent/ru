import 'package:flutter/material.dart';

import '../../domain/entities/workspace.dart';

class WorkspaceDashboardScreen extends StatelessWidget {
  const WorkspaceDashboardScreen({
    super.key,
    required this.dashboard,
  });

  final WorkspaceDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final counts = dashboard.smartViewCounts;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(dashboard.workspace.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            dashboard.workspace.description.isEmpty ? 'Workspace dashboard' : dashboard.workspace.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountCard(title: 'Chats', value: dashboard.chatIds.length),
              _CountCard(title: 'Important', value: counts['important'] ?? 0),
              _CountCard(title: 'Mentions', value: counts['mentions_me'] ?? 0),
              _CountCard(title: 'Files & Media', value: counts['files_media'] ?? 0),
              _CountCard(title: 'Automation', value: counts['automation'] ?? 0),
              _CountCard(title: 'Pending/Failed', value: counts['failed_pending'] ?? 0),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Aggregated Smart Views', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(title: const Text('Important messages'), trailing: Text('${counts['important'] ?? 0}')),
                ListTile(title: const Text('Mentions me'), trailing: Text('${counts['mentions_me'] ?? 0}')),
                ListTile(title: const Text('Files & media'), trailing: Text('${counts['files_media'] ?? 0}')),
                ListTile(title: const Text('Automation-applied'), trailing: Text('${counts['automation'] ?? 0}')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Recent messages', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: dashboard.recentMessages
                  .take(24)
                  .map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(row['text']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Chat ${row['chat_id']} · ${row['sender_id'] ?? ''}'),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: const ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('AI Layer Placeholder'),
              subtitle: Text('Workspace-level AI insights will be available here.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.title, required this.value});

  final String title;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            Text(title),
          ],
        ),
      ),
    );
  }
}
