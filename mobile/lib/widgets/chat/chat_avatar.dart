import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tripthread/utils/user_display_labels.dart';

class ChatAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? username;
  final String? name;
  final String? email;
  final double radius;
  final VoidCallback? onTap;

  const ChatAvatar({
    super.key,
    this.avatarUrl,
    this.username,
    this.name,
    this.email,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = userAvatarInitial(username: username, name: name);
    final hasImage = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: _getAvatarColor(initial),
      backgroundImage: hasImage ? CachedNetworkImageProvider(avatarUrl!) : null,
      child: !hasImage
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }
    return avatar;
  }

  Color _getAvatarColor(String initial) {
    final colors = [
      Colors.blue.shade700,
      Colors.indigo.shade700,
      Colors.teal.shade700,
      Colors.green.shade700,
      Colors.orange.shade800,
      Colors.red.shade700,
      Colors.pink.shade700,
      Colors.purple.shade700,
    ];
    final index = initial.isEmpty ? 0 : initial.codeUnitAt(0) % colors.length;
    return colors[index];
  }
}
