import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/app_feedback.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 10) {
      AppFeedback.showError(
        context,
        'Write at least a few words so we can help.',
      );
      return;
    }

    setState(() => _sending = true);
    final user = context.read<AuthProvider>().currentUser;
    final response = await context.read<ApiService>().sendSupportMessage(
      message: text,
      email: user?.email,
      name: user?.name,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (response.success) {
      setState(() => _sent = true);
      return;
    }
    AppFeedback.showError(
      context,
      response.error ?? 'Could not send your message.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Contact support')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Tell us what went wrong. Your note is emailed to the TripThread team.',
                  style: theme.textTheme.bodyLarge,
                ),
                if (user?.email != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'We will reply to ${user!.email}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (_sent)
                  Text(
                    'Sent. We will reply by email.',
                    style: theme.textTheme.titleMedium,
                  )
                else ...[
                  TextField(
                    controller: _message,
                    minLines: 6,
                    maxLines: 10,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'What happened?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? 'Sending…' : 'Send'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
