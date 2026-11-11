import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/chat_media_item.dart';
import 'package:tripthread/services/api_service.dart';

class SafetyPersonTile extends StatelessWidget {
  const SafetyPersonTile({
    super.key,
    required this.name,
    required this.detail,
    required this.undoLabel,
    required this.onUndo,
  });

  final String name;
  final String detail;
  final String undoLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(name),
      subtitle: Text(detail),
      trailing: TextButton(onPressed: onUndo, child: Text(undoLabel)),
    );
  }
}

class SafetyListScreen extends StatefulWidget {
  const SafetyListScreen({super.key});

  @override
  State<SafetyListScreen> createState() => _SafetyListScreenState();
}

class _SafetyListScreenState extends State<SafetyListScreen> {
  final List<SafetyPerson> _blocked = [];
  final List<SafetyPerson> _restricted = [];
  String? _blockedCursor;
  String? _restrictedCursor;
  bool _blockedMore = true;
  bool _restrictedMore = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBoth();
  }

  Future<void> _loadBoth() async {
    await Future.wait([
      _load(action: 'BLOCK', reset: true),
      _load(action: 'RESTRICT', reset: true),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load({required String action, bool reset = false}) async {
    final blocked = action == 'BLOCK';
    if (blocked && !_blockedMore && !reset) return;
    if (!blocked && !_restrictedMore && !reset) return;
    final api = context.read<ApiService>();
    final response = await api.listSafetyPeople(
      action: action,
      cursor: reset ? null : (blocked ? _blockedCursor : _restrictedCursor),
    );
    if (!mounted || response.data == null) return;
    setState(() {
      final page = response.data!;
      final target = blocked ? _blocked : _restricted;
      if (reset) target.clear();
      target.addAll(page.people);
      if (blocked) {
        _blockedCursor = page.nextCursor;
        _blockedMore = page.hasMore;
      } else {
        _restrictedCursor = page.nextCursor;
        _restrictedMore = page.hasMore;
      }
    });
  }

  Future<void> _undo(SafetyPerson person, String action) async {
    final api = context.read<ApiService>();
    final response = await api.clearSafety(person.id);
    if (!mounted) return;
    if (!response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.error ?? 'Could not update')),
      );
      return;
    }
    setState(() {
      (action == 'BLOCK' ? _blocked : _restricted)
          .removeWhere((item) => item.id == person.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked and restricted')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _SectionTitle('Blocked'),
                if (_blocked.isEmpty)
                  const ListTile(title: Text('No blocked people')),
                for (final person in _blocked)
                  SafetyPersonTile(
                    name: person.label,
                    detail: 'Blocked',
                    undoLabel: 'Unblock',
                    onUndo: () => _undo(person, 'BLOCK'),
                  ),
                if (_blockedMore && _blocked.isNotEmpty)
                  TextButton(
                    onPressed: () => _load(action: 'BLOCK'),
                    child: const Text('More blocked'),
                  ),
                const _SectionTitle('Restricted'),
                if (_restricted.isEmpty)
                  const ListTile(title: Text('No restricted people')),
                for (final person in _restricted)
                  SafetyPersonTile(
                    name: person.label,
                    detail: 'Restricted',
                    undoLabel: 'Remove restriction',
                    onUndo: () => _undo(person, 'RESTRICT'),
                  ),
                if (_restrictedMore && _restricted.isNotEmpty)
                  TextButton(
                    onPressed: () => _load(action: 'RESTRICT'),
                    child: const Text('More restricted'),
                  ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
