import 'package:flutter/material.dart';

/// Web stand-in for the native Mapbox pin picker.
///
/// mapbox_maps_flutter 2.x ships Android and iOS implementations only.
/// Place search on the thread still works through the API.
class MapPickerModal extends StatelessWidget {
  final String? initialPlaceName;
  final double? initialLat;
  final double? initialLng;

  const MapPickerModal({
    super.key,
    this.initialPlaceName,
    this.initialLat,
    this.initialLng,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick on map'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.map_outlined, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Dropping a pin runs in the iOS and Android apps.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Search for a place instead. The rest of the trip — creating it, the thread, chat, and expenses — works here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to search'),
            ),
          ],
        ),
      ),
    );
  }
}
