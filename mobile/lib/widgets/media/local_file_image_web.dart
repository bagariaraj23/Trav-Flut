import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class LocalFileImage extends StatefulWidget {
  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const LocalFileImage({
    super.key,
    required this.path,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  });

  @override
  State<LocalFileImage> createState() => _LocalFileImageState();
}

class _LocalFileImageState extends State<LocalFileImage> {
  late final Future<Uint8List> _bytes = XFile(widget.path).readAsBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            errorBuilder: widget.errorBuilder,
          );
        }
        if (snapshot.hasError && widget.errorBuilder != null) {
          return widget.errorBuilder!(
            context,
            snapshot.error!,
            snapshot.stackTrace ?? StackTrace.empty,
          );
        }
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
