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
      const Color(0xFFC2692A),
      const Color(0xFF5C7F67),
      const Color(0xFF7B5EA7),
      const Color(0xFF4A7FA5),
      const Color(0xFFB45309),
      const Color(0xFF78716C),
      const Color(0xFF9A3412),
      const Color(0xFF44403C),
    ];
    final index = initial.isEmpty ? 0 : initial.codeUnitAt(0) % colors.length;
    return colors[index];
  }
}
