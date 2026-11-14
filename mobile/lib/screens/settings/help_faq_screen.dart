import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/screens/settings/help_topics.dart';
import 'package:tripthread/utils/app_layout.dart';

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key, this.initialTopic});

  final String? initialTopic;

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<HelpTopic> _visible(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return helpTopics;
    return [
      for (final topic in helpTopics)
        if (topic.title.toLowerCase().contains(needle) ||
            topic.items.any(
              (item) =>
                  item.question.toLowerCase().contains(needle) ||
                  item.answer.toLowerCase().contains(needle),
            ))
          HelpTopic(
            id: topic.id,
            title: topic.title,
            items: topic.title.toLowerCase().contains(needle)
                ? topic.items
                : topic.items
                    .where(
                      (item) =>
                          item.question.toLowerCase().contains(needle) ||
                          item.answer.toLowerCase().contains(needle),
                    )
                    .toList(),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topics = _visible(_search.text);
    final searching = _search.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Help and FAQ')),
      body: AppLayout.reading(
        context: context,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search help',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Short answers for how TripThread works.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            if (topics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No matches. Try a shorter word, such as block, trip, or comment.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            else
              for (final topic in topics)
                _HelpSection(
                  topic: topic,
                  expanded: searching || topic.id == widget.initialTopic,
                ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.topic, required this.expanded});

  final HelpTopic topic;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('${topic.id}-$expanded'),
        initiallyExpanded: expanded,
        title: Text(
          topic.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final item in topic.items) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.question,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.answer,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

void showSafetyInfo(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restrict and Block'),
      content: SingleChildScrollView(
        child: Text(
          safetyHelpPreview,
          style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                height: 1.35,
              ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push('/settings/help?topic=safety');
          },
          child: const Text('Read the full guide'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: TextButton.styleFrom(foregroundColor: scheme.primary),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
