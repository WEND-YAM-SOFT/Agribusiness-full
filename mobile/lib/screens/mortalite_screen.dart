import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/bande.dart';
import '../providers/bandes_provider.dart';
import '../services/api_service.dart';
import '../widgets/iso_calendar_picker.dart';

class MortaliteScreen extends StatefulWidget {
  final Bande bande;

  const MortaliteScreen({super.key, required this.bande});

  @override
  State<MortaliteScreen> createState() => _MortaliteScreenState();
}

class _MortaliteScreenState extends State<MortaliteScreen> {
  DateTime _date = DateTime.now();
  final TextEditingController _mortaliteCtrl = TextEditingController(text: '0');
  final TextEditingController _obsCtrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _historique = [];

  @override
  void initState() {
    super.initState();
    _chargerHistorique();
  }

  @override
  void dispose() {
    _mortaliteCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerHistorique() async {
    try {
      final data = await ApiService.getSuivis(widget.bande.id!);
      if (!mounted) return;
      final all = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) => (row['mortaliteJour'] as num? ?? 0) > 0)
          .toList();
      all.sort((a, b) => DateTime.tryParse((b['date'] ?? '').toString())
          .toString()
          .compareTo(DateTime.tryParse((a['date'] ?? '').toString()).toString()));
      setState(() => _historique = all);
    } catch (_) {
      if (!mounted) return;
      setState(() => _historique = []);
    }
  }

  Future<void> _enregistrer() async {
    final mortalite = int.tryParse(_mortaliteCtrl.text) ?? -1;
    if (mortalite <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La mortalité du jour doit être supérieure à 0')),
      );
      return;
    }

    setState(() => _loading = true);
    final ok = await context.read<BandesProvider>().ajouterMortalite(widget.bande.id!, {
      'date': _date.toIso8601String(),
      'mortaliteJour': mortalite,
      'observations': _obsCtrl.text.trim(),
    });

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Mortalité enregistrée' : 'Erreur enregistrement mortalité')),
    );
    if (ok) {
      _mortaliteCtrl.text = '0';
      _obsCtrl.clear();
      await _chargerHistorique();
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: Text('Mortalité - ${widget.bande.nom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Enregistrer la mortalité du jour', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('Date de déclaration'),
            subtitle: Text(df.format(_date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showIsoDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(
            controller: _mortaliteCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Mortalité du jour *'),
          ),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observations (optionnel)'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _enregistrer,
            icon: const Icon(Icons.save),
            label: Text(_loading ? 'Enregistrement...' : 'Enregistrer'),
          ),
          const SizedBox(height: 20),
          Text('Historique mortalité', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_historique.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune mortalité enregistrée'),
              ),
            )
          else
            ..._historique.map((row) {
              final date = row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.health_and_safety, color: Colors.redAccent),
                  title: Text('Mortalité: ${(row['mortaliteJour'] ?? 0).toString()}'),
                  subtitle: Text(
                    '${date != null ? df.format(date) : '-'}${(row['observations'] ?? '').toString().isNotEmpty ? ' • ${row['observations']}' : ''}',
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
