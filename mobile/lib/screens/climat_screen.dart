import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/bande.dart';
import '../providers/bandes_provider.dart';
import '../services/api_service.dart';

class ClimatScreen extends StatefulWidget {
  final Bande bande;

  const ClimatScreen({super.key, required this.bande});

  @override
  State<ClimatScreen> createState() => _ClimatScreenState();
}

class _ClimatScreenState extends State<ClimatScreen> {
  DateTime _date = DateTime.now();
  final TextEditingController _tempCtrl = TextEditingController();
  final TextEditingController _humiditeCtrl = TextEditingController();
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
    _tempCtrl.dispose();
    _humiditeCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerHistorique() async {
    try {
      final data = await ApiService.getRelevesClimat(widget.bande.id!);
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
    final temp = double.tryParse(_tempCtrl.text) ?? 0;
    final hum = double.tryParse(_humiditeCtrl.text) ?? 0;
    if (temp <= 0 && hum <= 0) return;

    setState(() => _loading = true);
    final ok = await context.read<BandesProvider>().ajouterReleveClimat(widget.bande.id!, {
      'date': _date.toIso8601String(),
      'temperature': temp,
      'humidite': hum,
      'observations': _obsCtrl.text.trim(),
    });

    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Relevé climat enregistré' : 'Erreur enregistrement')),
    );
    if (ok) {
      _tempCtrl.clear();
      _humiditeCtrl.clear();
      _obsCtrl.clear();
      await _chargerHistorique();
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: Text('Température/Humidité - ${widget.bande.nom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Température et Humidité', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('Date'),
            subtitle: Text(df.format(_date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(
            controller: _tempCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Température (°C)'),
          ),
          TextField(
            controller: _humiditeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Humidité (%)'),
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
          Text('Historique', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_historique.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun relevé climat'),
              ),
            )
          else
            ..._historique.map((row) {
              final date = row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.thermostat),
                  title: Text('T° ${(row['temperature'] ?? 0)} °C • H ${(row['humidite'] ?? 0)} %'),
                  subtitle: Text('${date != null ? df.format(date) : '-'}${(row['observations'] ?? '').toString().isNotEmpty ? ' • ${row['observations']}' : ''}'),
                ),
              );
            }),
        ],
      ),
    );
  }
}
