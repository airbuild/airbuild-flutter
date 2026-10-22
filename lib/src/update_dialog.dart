import 'package:flutter/material.dart';

import 'update_info.dart';

/// Signature for the callback invoked when the tester taps "Update".
typedef OnUpdateCallback = Future<void> Function();

/// Signature for the callback invoked when the tester taps "Later".
typedef OnLaterCallback = void Function();

/// Default update dialog shown by [AirBuild.checkForUpdates].
///
/// Displays the app icon (when [UpdateInfo.iconUrl] is available), the new
/// version, the file size, the release notes, and two buttons:
/// - **Update** — triggers the platform install flow.
/// - **Later** — dismisses the dialog.
///
/// The dialog is a standard [AlertDialog]. It disables the Update button and
/// shows a progress indicator while the install flow is running so the tester
/// cannot trigger it twice.
class UpdateDialog extends StatefulWidget {
  /// Creates an update dialog for the given [update].
  const UpdateDialog({
    super.key,
    required this.update,
    required this.onUpdate,
    this.onLater,
    this.appName,
  });

  /// The update to display.
  final UpdateInfo update;

  /// Called when the tester taps "Update". The dialog waits for this future
  /// before closing (unless it throws, in which case the dialog stays open and
  /// shows the error).
  final OnUpdateCallback onUpdate;

  /// Called when the tester taps "Later". Defaults to popping the dialog route.
  final OnLaterCallback? onLater;

  /// Optional app name shown in the dialog title. When omitted, the title just
  /// says "Update available".
  final String? appName;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          if (update.iconUrl != null && update.iconUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  update.iconUrl!,
                  width: 40,
                  height: 40,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Text(
              widget.appName != null
                  ? '${widget.appName} update available'
                  : 'Update available',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: [
            Text(
              'Version ${update.latestVersion ?? 'unknown'}'
              '${update.fileSizeDisplay.isNotEmpty ? '  -  ${update.fileSizeDisplay}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (update.releaseNotes != null &&
                update.releaseNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Release notes', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                update.releaseNotes!,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _onLater,
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _busy ? null : _onUpdate,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update'),
        ),
      ],
    );
  }

  Future<void> _onUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUpdate();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not start the update. Please try again.';
        });
      }
    }
  }

  void _onLater() {
    widget.onLater?.call();
    Navigator.of(context).maybePop(false);
  }
}

/// Convenience function that pushes [UpdateDialog] as a modal route and
/// awaits the result. Returns `true` if the tester accepted the update,
/// `false` if they dismissed it, or `null` if the dialog was closed another
/// way.
Future<bool?> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo update,
  required OnUpdateCallback onUpdate,
  OnLaterCallback? onLater,
  String? appName,
  bool barrierDismissible = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => UpdateDialog(
      update: update,
      onUpdate: onUpdate,
      onLater: onLater,
      appName: appName,
    ),
  );
}
