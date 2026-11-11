import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/chat_media_item.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/media/media_gallery_viewer.dart';
import 'package:tripthread/widgets/media/media_seek.dart';

Future<void> openConversationMedia(
  BuildContext context,
  String conversationId,
  String mediaId,
) async {
  final api = context.read<ApiService>();
  final collected = <ChatMediaItem>[];
  String? cursor;
  var hasMore = true;
  var pages = 0;
  while (hasMore && pages < 8) {
    final response = await api.getConversationMedia(
      conversationId,
      limit: 24,
      cursor: cursor,
    );
    final page = response.data;
    if (page == null) break;
    collected.addAll(page.items);
    cursor = page.nextCursor;
    hasMore = page.hasMore;
    pages += 1;
    if (collected.any((item) => item.id == mediaId)) break;
  }
  if (!context.mounted || collected.isEmpty) return;
  final index = collected.indexWhere((item) => item.id == mediaId);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MediaGalleryViewer(
        initialIndex: index < 0 ? 0 : index,
        items: collected
            .map(
              (media) => GalleryMedia(
                id: media.id,
                url: media.url,
                isVideo: media.isVideo,
                sharedAt: media.createdAt,
              ),
            )
            .toList(),
      ),
    ),
  );
}

class ConversationMediaStrip extends StatefulWidget {
  const ConversationMediaStrip({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ConversationMediaStrip> createState() => _ConversationMediaStripState();
}

class _ConversationMediaStripState extends State<ConversationMediaStrip> {
  List<ChatMediaItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    final response = await api.getConversationMedia(
      widget.conversationId,
      limit: 6,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = response.data?.items ?? [];
    });
  }

  void _open(ChatMediaItem item) {
    final index = _items.indexWhere((media) => media.id == item.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaGalleryViewer(
          initialIndex: index < 0 ? 0 : index,
          items: _items
              .map(
                (media) => GalleryMedia(
                  id: media.id,
                  url: media.url,
                  isVideo: media.isVideo,
                  sharedAt: media.createdAt,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                'Media',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatMediaGridScreen(
                        conversationId: widget.conversationId,
                      ),
                    ),
                  );
                },
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        Builder(
          builder: (context) {
            final tile = (MediaQuery.sizeOf(context).width / 5.2).clamp(72.0, 120.0);
            return SizedBox(
          height: tile,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = _items[index];
              final preview = item.isVideo
                  ? buildVideoThumbnailUrl(item.url, maxWidth: 200)
                  : buildOptimizedImageUrl(item.url, width: 200);
              return GestureDetector(
                onTap: () => _open(item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: tile,
                    height: tile,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(imageUrl: preview, fit: BoxFit.cover),
                        if (item.isVideo)
                          const Icon(Icons.play_circle_outline, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class ChatMediaGridScreen extends StatefulWidget {
  const ChatMediaGridScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatMediaGridScreen> createState() => _ChatMediaGridScreenState();
}

class _ChatMediaGridScreenState extends State<ChatMediaGridScreen> {
  final List<ChatMediaItem> _items = [];
  final ScrollController _scroll = ScrollController();
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    final response = await api.getConversationMedia(
      widget.conversationId,
      limit: 24,
      cursor: _cursor,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      final page = response.data;
      if (page == null) {
        _hasMore = false;
        return;
      }
      _items.addAll(page.items);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    });
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaGalleryViewer(
          initialIndex: index,
          items: _items
              .map(
                (media) => GalleryMedia(
                  id: media.id,
                  url: media.url,
                  isVideo: media.isVideo,
                  sharedAt: media.createdAt,
                ),
              )
              .toList(),
          onNearEnd: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared media')),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = mediaGridColumns(constraints.maxWidth);
                return GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final item = _items[index];
                final preview = item.isVideo
                    ? buildVideoThumbnailUrl(item.url, maxWidth: 300)
                    : buildOptimizedImageUrl(item.url, width: 300);
                return GestureDetector(
                  onTap: () => _open(index),
                  child: CachedNetworkImage(imageUrl: preview, fit: BoxFit.cover),
                );
              },
            );
              },
            ),
    );
  }
}
