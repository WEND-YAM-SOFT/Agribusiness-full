import 'package:intl/intl.dart';

String formatAmount(num value) {
  final rounded = value.round();
  return NumberFormat.decimalPattern('fr_FR').format(rounded);
}

String formatAmountFcfa(num value) {
  return '${formatAmount(value)} FCFA';
}
