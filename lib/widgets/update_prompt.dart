import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

const String _skippedVersionKey = 'skipped_update_version';

Future<void> checkForUpdates(
  BuildContext context, {
  bool manual = false,
}) async {
  AppUpdate? result;
  try {
    result = await UpdateService.check();
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates.')),
      );
    }
    return;
  }
  if (!context.mounted) return;

  if (result == null) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KinChat is up to date.')),
      );
    }
    return;
  }

  final available = result;
  final prefs = await SharedPreferences.getInstance();
  if (!manual && prefs.getString(_skippedVersionKey) == available.version) {
    return;
  }
  if (!context.mounted) return;

  final notes = available.notes.trim();
  final download = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('KinChat ${available.version} is available'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A newer version is ready to download.'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                notes,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Download'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;

  if (download != true) {
    await prefs.setString(_skippedVersionKey, available.version);
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(available.downloadUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!context.mounted) return;
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: available.downloadUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download link copied.')),
      );
    }
  }
}
