import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DialCountry {
  final String name;
  final String code;

  const DialCountry(this.name, this.code);
}

const List<DialCountry> dialCountries = [
  DialCountry('Senegal', '+221'),
  DialCountry('Cote d\'Ivoire', '+225'),
  DialCountry('Mali', '+223'),
  DialCountry('Burkina Faso', '+226'),
  DialCountry('Cameroun', '+237'),
  DialCountry('Benin', '+229'),
  DialCountry('Togo', '+228'),
  DialCountry('Niger', '+227'),
  DialCountry('France', '+33'),
  DialCountry('Maroc', '+212'),
];

String phoneDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

String phonePairs(String value) {
  final digits = phoneDigits(value);
  if (digits.isEmpty) return '';
  final parts = <String>[];
  for (var i = 0; i < digits.length; i += 2) {
    parts.add(digits.substring(i, math.min(i + 2, digits.length)));
  }
  return parts.join(' ');
}

String formatInternationalPhone(String dialCode, String localInput) {
  final local = phonePairs(localInput);
  if (local.isEmpty) return dialCode;
  return '$dialCode $local';
}

bool isValidInternationalPhone(String value, {int minLocalDigits = 6}) {
  final match = RegExp(r'^\+(\d{1,4})\s*(.*)$').firstMatch(value.trim());
  if (match == null) return false;
  final localDigits = phoneDigits(match.group(2) ?? '');
  return localDigits.length >= minLocalDigits;
}

class PhonePairsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = phonePairs(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class InternationalPhoneField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;

  const InternationalPhoneField({
    super.key,
    required this.controller,
    this.labelText = 'Telephone',
    this.hintText,
  });

  @override
  State<InternationalPhoneField> createState() => _InternationalPhoneFieldState();
}

class _InternationalPhoneFieldState extends State<InternationalPhoneField> {
  late DialCountry _selected;
  late TextEditingController _localCtrl;

  @override
  void initState() {
    super.initState();
    final parsed = _parseExisting(widget.controller.text);
    _selected = parsed.$1;
    _localCtrl = TextEditingController(text: parsed.$2);
    _syncToExternal();
    _localCtrl.addListener(_syncToExternal);
  }

  @override
  void dispose() {
    _localCtrl.removeListener(_syncToExternal);
    _localCtrl.dispose();
    super.dispose();
  }

  (DialCountry, String) _parseExisting(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return (dialCountries.first, '');
    }

    final match = RegExp(r'^\+(\d{1,4})\s*(.*)$').firstMatch(raw);
    if (match == null) {
      return (dialCountries.first, phonePairs(raw));
    }

    final code = '+${match.group(1)}';
    final country = dialCountries.firstWhere(
      (c) => c.code == code,
      orElse: () => dialCountries.first,
    );
    return (country, phonePairs(match.group(2) ?? ''));
  }

  void _syncToExternal() {
    widget.controller.text = formatInternationalPhone(_selected.code, _localCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<DialCountry>(
          initialValue: _selected,
          decoration: const InputDecoration(labelText: 'Pays / Indicatif'),
          items: dialCountries
              .map(
                (c) => DropdownMenuItem<DialCountry>(
                  value: c,
                  child: Text('${c.name} (${c.code})'),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selected = v);
            _syncToExternal();
          },
        ),
        TextField(
          controller: _localCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            PhonePairsFormatter(),
          ],
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText ?? 'Ex: 77 12 34 56',
          ),
        ),
      ],
    );
  }
}
