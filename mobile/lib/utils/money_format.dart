import 'package:intl/intl.dart';

String formatAmount(num value) {
  final rounded = value.round();
  return NumberFormat.decimalPattern('fr_FR').format(rounded);
}

String formatAmountFcfa(num value) {
  return '${formatAmount(value)} FCFA';
}

String formatCompactNumber(num value) {
  final abs = value.abs().toDouble();
  final sign = value < 0 ? '-' : '';

  if (abs < 1000) return '$sign${abs.toStringAsFixed(0)}';
  if (abs < 1000000) return '$sign${(abs / 1000).toStringAsFixed(abs >= 100000 ? 0 : 1)}k';
  if (abs < 1000000000) return '$sign${(abs / 1000000).toStringAsFixed(abs >= 100000000 ? 0 : 1)}M';
  return '$sign${(abs / 1000000000).toStringAsFixed(abs >= 100000000000 ? 0 : 1)}B';
}

String formatCompactFcfa(num value) {
  return '${formatCompactNumber(value)} FCFA';
}
