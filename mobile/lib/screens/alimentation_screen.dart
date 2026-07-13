import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/bande.dart';
import '../providers/bandes_provider.dart';
import '../services/api_service.dart';
import '../widgets/iso_calendar_picker.dart';

class AlimentationScreen extends StatefulWidget {
  final Bande bande;

  const AlimentationScreen({super.key, required this.bande});

  @override
  State<AlimentationScreen> createState() => _AlimentationScreenState();
}

class _AlimentationScreenState extends State<AlimentationScreen> {
  DateTime _date = DateTime.now();
  final TextEditingController _alimentationCtrl = TextEditingController();
  final TextEditingController _eauCtrl = TextEditingController();
  final TextEditingController _obsCtrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _historique = [];
  List<Map<String, dynamic>> _stocksAliment = [];
  String? _selectedAlimentStockId;

  @override
  void initState() {
    super.initState();
    _loadStocks();
    _chargerHistorique();
  }

  @override
  void dispose() {
    _alimentationCtrl.dispose();
    _eauCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStocks() async {
    try {
      final data = await ApiService.getStocks();
      if (!mounted) return;

      final normalized = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final aliments = normalized.where((s) => (s['categorie'] ?? '').toString() == 'aliment').toList();

      setState(() {
        _stocksAliment = aliments;
        if (_selectedAlimentStockId == null && _stocksAliment.isNotEmpty) {
          _selectedAlimentStockId = _stocksAliment.first['_id']?.toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stocksAliment = [];
        _selectedAlimentStockId = null;
      });
    }
  }

  String _stockNameById(String? id) {
    if (id == null || id.isEmpty) return '';
    for (final s in _stocksAliment) {
      if (s['_id']?.toString() == id) {
        return (s['nom'] ?? '').toString();
      }
    }
    return '';
  }

  Future<void> _chargerHistorique() async {
    try {
      final data = await ApiService.getSuivis(widget.bande.id!);
      if (!mounted) return;
      final all = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) => (row['alimentationKg'] as num? ?? 0) > 0)
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
    final alimentation = double.tryParse(_alimentationCtrl.text) ?? 0;
    final observations = _obsCtrl.text.trim();
    if (alimentation <= 0 || observations.isEmpty || _selectedAlimentStockId == null || _selectedAlimentStockId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne les champs obligatoires: alimentation, type et observations')),
      );
      return;
    }

    setState(() => _loading = true);
    final ok = await context.read<BandesProvider>().ajouterSuivi(widget.bande.id!, {
      'date': _date.toIso8601String(),
      'alimentationKg': alimentation,
      'alimentationStockId': _selectedAlimentStockId,
      'alimentationType': _stockNameById(_selectedAlimentStockId),
      'mortaliteJour': 0,
      'eauLitres': double.tryParse(_eauCtrl.text) ?? 0,
      'observations': observations,
    });

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Suivi alimentation enregistré' : 'Erreur enregistrement suivi alimentation')),
    );
    if (ok) {
      _alimentationCtrl.clear();
      _eauCtrl.clear();
      _obsCtrl.clear();
      await _loadStocks();
      await _chargerHistorique();
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: Text('Alimentation - ${widget.bande.nom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Enregistrer le suivi alimentation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('Date du suivi'),
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
            controller: _alimentationCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Alimentation (kg) *'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _selectedAlimentStockId,
            items: _stocksAliment
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s['_id']?.toString(),
                    child: Text('${s['nom']} (${s['quantiteActuelle']} ${s['unite']})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedAlimentStockId = v),
            decoration: const InputDecoration(labelText: 'Type d\'alimentation *'),
          ),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observations *'),
          ),
          TextField(
            controller: _eauCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Eau (litres) (optionnel)'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _enregistrer,
            icon: const Icon(Icons.save),
            label: Text(_loading ? 'Enregistrement...' : 'Enregistrer'),
          ),
          const SizedBox(height: 20),
          Text('Historique alimentation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_historique.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun suivi alimentation enregistré'),
              ),
            )
          else
            ..._historique.map((row) {
              final date = row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.restaurant),
                  title: Text('Alim: ${(row['alimentationKg'] ?? 0).toString()} kg • Eau: ${(row['eauLitres'] ?? 0).toString()} L'),
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
