import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

class LikedByScreen extends StatefulWidget {
  final String entityType;
  final String entityId;

  const LikedByScreen({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  State<LikedByScreen> createState() => _LikedByScreenState();
}

class _LikedByScreenState extends State<LikedByScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreUsers();
    }
  }

  Future<void> _loadUsers() async {
    final provider = context.read<EngagementProvider>();
    await provider.getLikeUsers(widget.entityType, widget.entityId, 1);
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    final provider = context.read<EngagementProvider>();
    await provider.getLikeUsers(widget.entityType, widget.entityId, _currentPage);
    setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked by'),
      ),
      body: Consumer<EngagementProvider>(
        builder: (context, provider, child) {
          final users = provider.getLikeUsersList('${widget.entityType}:${widget.entityId}');
          final isLoading = provider.isLoadingUsers('${widget.entityType}:${widget.entityId}');
          final error = provider.error;

          if (isLoading && users.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(error),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadUsers,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No likes yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _currentPage = 1;
              await _loadUsers();
            },
            child: ListView.builder(
              controller: _scrollController,
              itemCount: users.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == users.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: user.avatarUrl != null
                        ? CachedNetworkImageProvider(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            user.name?.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(fontSize: 18),
                          )
                        : null,
                  ),
                  title: Text(user.name ?? 'Unknown'),
                  subtitle: user.username != null
                      ? Text('@${user.username}')
                      : null,
                  trailing: OutlinedButton(
                    onPressed: () {
                      // TODO: Implement follow functionality
                    },
                    child: const Text('Follow'),
                  ),
                  onTap: () {
                    context.push('/profile/${user.id}');
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

