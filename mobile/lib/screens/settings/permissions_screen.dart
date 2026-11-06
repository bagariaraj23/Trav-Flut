import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_permissions.dart';
import 'package:tripthread/utils/app_theme.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final Map<AppPermissionKind, PermissionStatus> _status = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final next = <AppPermissionKind, PermissionStatus>{};
    for (final item in AppPermissions.details) {
      next[item.kind] = await AppPermissions.status(item.kind);
    }
    if (!mounted) return;
    setState(() {
      _status
        ..clear()
        ..addAll(next);
      _loading = false;
    });
  }

  Future<void> _onAction(AppPermissionInfo item, PermissionStatus status) async {
    if (status.isPermanentlyDenied || status.isRestricted) {
      await AppPermissions.openSettings();
      return;
    }
    await AppPermissions.ensure(item.kind);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions and data'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: AppLayout.reading(
        context: context,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'TripThread asks for these only when a feature needs them. You can change them here or in the system settings.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final item in AppPermissions.details) ...[
                    _PermissionCard(
                      info: item,
                      status: _status[item.kind] ?? PermissionStatus.denied,
                      onAction: () => _onAction(
                        item,
                        _status[item.kind] ?? PermissionStatus.denied,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'DATA STORED WITH TRIPTHREAD',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.1,
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your profile, trips, messages, and the photos or videos you upload are stored so the people you share them with can see them. A place you confirm on the map is saved with that trip entry. TripThread does not read your location, camera, or library in the background.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final AppPermissionInfo info;
  final PermissionStatus status;
  final VoidCallback onAction;

  const _PermissionCard({
    required this.info,
    required this.status,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allowed = status.isGranted || status.isLimited;
    final blocked = status.isPermanentlyDenied || status.isRestricted;
    final label = allowed
        ? (status.isLimited ? 'Limited access' : 'Allowed')
        : blocked
        ? 'Blocked'
        : 'Not allowed';
    final action = allowed ? 'Manage' : blocked ? 'Open Settings' : 'Allow';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(info.icon, color: scheme.onSurface),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    info.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: allowed ? AppTheme.live : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              info.dataUse,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: allowed ? () => AppPermissions.openSettings() : onAction,
                child: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
