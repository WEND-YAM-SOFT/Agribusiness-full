import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> exportCsvToClipboard(
  BuildContext context, {
  required Future<String> Function() loader,
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final csv = await loader();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    final lineCount = '\n'.allMatches(csv).length;
    messenger.showSnackBar(
      SnackBar(content: Text('CSV "$label" copie dans le presse-papiers ($lineCount lignes).')),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Export CSV impossible: $e')),
    );
  }
}
