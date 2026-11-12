import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/app_feedback.dart';
import 'package:tripthread/utils/app_layout.dart';

class SafetyChoice {
  const SafetyChoice({
    required this.label,
    this.subtitle,
    this.action,
    this.clears = false,
    this.destructive = false,
  });

  final String label;
  final String? subtitle;
  final String? action;
  final bool clears;
  final bool destructive;
}

const _blockSubtitle =
    'Stops messages. They cannot follow you, open your profile, or be added to a trip or group you created.';

/// Actions the signed-in person can take toward [outgoing] (RESTRICT, BLOCK, or none).
List<SafetyChoice> safetyChoices(String? outgoing) {
  if (outgoing == 'BLOCK') {
    return const [SafetyChoice(label: 'Unblock', clears: true)];
  }
  if (outgoing == 'RESTRICT') {
    return const [
      SafetyChoice(label: 'Remove restriction', clears: true),
      SafetyChoice(
        label: 'Block',
        subtitle: _blockSubtitle,
        action: 'BLOCK',
        destructive: true,
      ),
    ];
  }
  return const [
    SafetyChoice(
      label: 'Restrict',
      subtitle: 'Neither of you can send messages. This chat stays.',
      action: 'RESTRICT',
    ),
    SafetyChoice(
      label: 'Block',
      subtitle: _blockSubtitle,
      action: 'BLOCK',
      destructive: true,
    ),
  ];
}

class SafetyChoiceList extends StatelessWidget {
  const SafetyChoiceList({
    super.key,
    required this.choices,
    required this.onSelected,
    this.enabled = true,
  });

  final List<SafetyChoice> choices;
  final ValueChanged<SafetyChoice> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final choice in choices)
          ListTile(
            enabled: enabled,
            title: Text(
              choice.label,
              style: choice.destructive ? TextStyle(color: error) : null,
            ),
            subtitle: choice.subtitle == null ? null : Text(choice.subtitle!),
            onTap: enabled ? () => onSelected(choice) : null,
          ),
      ],
    );
  }
}

/// Opens Restrict and Block for one person. Returns true when a change is saved.
Future<bool> showUserSafetySheet(
  BuildContext context, {
  required String userId,
  required String name,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => UserSafetySheet(userId: userId, name: name),
  );
  return changed == true;
}

class UserSafetySheet extends StatefulWidget {
  const UserSafetySheet({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  State<UserSafetySheet> createState() => _UserSafetySheetState();
}

class _UserSafetySheetState extends State<UserSafetySheet> {
  String? _outgoing;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response = await context.read<ApiService>().getSafetyPair(widget.userId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _outgoing = response.data?['outgoing'] as String?;
    });
  }

  Future<void> _apply(SafetyChoice choice) async {
    setState(() => _busy = true);
    final api = context.read<ApiService>();
    final response = choice.clears
        ? await api.clearSafety(widget.userId)
        : await api.setSafety(widget.userId, choice.action!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!response.success) {
      AppFeedback.showError(context, response.error ?? 'Could not update');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AppLayout.reading(
      context: context,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 12 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SafetyChoiceList(
                choices: safetyChoices(_outgoing),
                enabled: !_busy,
                onSelected: _apply,
              ),
          ],
        ),
      ),
    );
  }
}
