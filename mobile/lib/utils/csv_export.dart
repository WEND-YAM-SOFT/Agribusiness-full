import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportCsvToClipboard(
  BuildContext context, {
  required Future<String> Function() loader,
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final csv = await loader();
    final safeName = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final filename = '${safeName.isEmpty ? 'export' : safeName}_${DateTime.now().toIso8601String().split('T').first}.csv';

    bool shared = false;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsString(csv, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        text: 'Export CSV - $label',
        subject: 'Export CSV - $label',
      );
      shared = true;
    } catch (_) {
      shared = false;
    }

    if (!shared) {
      await Clipboard.setData(ClipboardData(text: csv));
    }

    if (!context.mounted) return;
    final lineCount = '\n'.allMatches(csv).length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'CSV "$label" exporte en fichier et partage ($lineCount lignes).'
              : 'CSV "$label" copie dans le presse-papiers ($lineCount lignes).',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Export CSV impossible: $e')),
    );
  }
}
