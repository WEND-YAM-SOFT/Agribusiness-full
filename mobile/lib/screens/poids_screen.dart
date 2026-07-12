import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/bande.dart';
import '../providers/bandes_provider.dart';
import '../services/api_service.dart';
import '../widgets/iso_calendar_picker.dart';

class PoidsScreen extends StatefulWidget {
  final Bande bande;

  const PoidsScreen({super.key, required this.bande});

  @override
  State<PoidsScreen> createState() => _PoidsScreenState();
}

class _PoidsScreenState extends State<PoidsScreen> {
  DateTime _date = DateTime.now();
  final TextEditingController _poidsCtrl = TextEditingController();
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
    _poidsCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerHistorique() async {
    try {
      final data = await ApiService.getRelevesPoids(widget.bande.id!);
      if (!mounted) return;
      setState(() {
        _historique = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _historique = []);
    }
  }

  Future<void> _enregistrer() async {
    final poids = double.tryParse(_poidsCtrl.text) ?? 0;
    if (poids <= 0) return;

    setState(() => _loading = true);
    final ok = await context.read<BandesProvider>().ajouterRelevePoids(widget.bande.id!, {
      'date': _date.toIso8601String(),
      'poidsMotenG': poids,
      'observations': _obsCtrl.text.trim(),
    });

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Prise de poids enregistrée' : 'Erreur enregistrement')),
    );
    if (ok) {
      _poidsCtrl.clear();
      _obsCtrl.clear();
      await _chargerHistorique();
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: Text('Poids - ${widget.bande.nom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Enregistrer une prise de poids', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('Date'),
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
            controller: _poidsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Poids moyen (g) *'),
          ),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observations'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _enregistrer,
            icon: const Icon(Icons.save),
            label: Text(_loading ? 'Enregistrement...' : 'Enregistrer'),
          ),
          const SizedBox(height: 20),
          Text('Historique des relevés', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_historique.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun relevé de poids'),
              ),
            )
          else
            ..._historique.map((row) {
              final date = row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.monitor_weight),
                  title: Text('${(row['poidsMotenG'] ?? 0).toString()} g'),
                  subtitle: Text('${date != null ? df.format(date) : '-'}${(row['observations'] ?? '').toString().isNotEmpty ? ' • ${row['observations']}' : ''}'),
                ),
              );
            }),
        ],
      ),
    );
  }
}
