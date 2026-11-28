import 'package:flutter/material.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/widgets/feed/final_post_feed_card.dart';

/// Shows how a trip final post or direct user post will look on the home feed
/// before publish. Callers supply publish / save-draft handlers.
class PostPreviewScreen extends StatefulWidget {
  final TripFinalPost post;
  final Future<bool> Function() onPublish;
  final Future<bool> Function() onSaveDraft;
  final String title;

  const PostPreviewScreen({
    super.key,
    required this.post,
    required this.onPublish,
    required this.onSaveDraft,
    this.title = 'Preview',
  });

  @override
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action, {required bool popHome}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (popHome) {
      Navigator.of(context).pop({'published': true});
    } else {
      Navigator.of(context).pop({'saved': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutLabel = widget.post.isDirectPost
        ? 'Postcard'
        : switch (widget.post.templateChoice) {
            FinalPostTemplateChoice.mapFirst => 'Map',
            FinalPostTemplateChoice.threadReel => 'Threads',
            FinalPostTemplateChoice.postcard => 'Postcard',
          };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              'This is how your $layoutLabel card will look on Home.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FinalPostFeedCard(
            post: widget.post,
            previewMode: true,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(widget.onSaveDraft, popHome: false),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(widget.onPublish, popHome: true),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Publish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
