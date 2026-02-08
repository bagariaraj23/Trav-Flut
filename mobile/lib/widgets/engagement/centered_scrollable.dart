import 'package:flutter/material.dart';

/// A centered placeholder that can scroll when vertical space is tight
/// (e.g. in bottom sheets when the keyboard is open).
class CenteredScrollable extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  const CenteredScrollable({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

