import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/bande.dart';
import '../services/api_service.dart';

class BandeDashboardScreen extends StatefulWidget {
  final Bande bande;
  const BandeDashboardScreen({super.key, required this.bande});

  @override
  State<BandeDashboardScreen> createState() => _BandeDashboardScreenState();
}

class _BandeDashboardScreenState extends State<BandeDashboardScreen> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.getSuiviDashboardBande(widget.bande.id!);
      if (mounted) {
        setState(() {
          data = d;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Dashboard cycle ${widget.bande.nom}')),
        body: const Center(child: Text('Impossible de charger les données')),
      );
    }

    final growth = data!['growth'] as List<dynamic>;
    final theoriqueGrowth = data!['theoriqueGrowth'] as List<dynamic>? ?? const [];
    final conso = data!['conso'] as List<dynamic>;
    final theoriqueConso = data!['theoriqueConso'] as List<dynamic>? ?? const [];
    final mortality = data!['mortaliteJour'] as List<dynamic>;
    final forecast7j = data!['forecast7j'] as List<dynamic>? ?? const [];
    final eventsPrevisionnels = data!['eventsPrevisionnels'] as List<dynamic>? ?? const [];
    final perf = data!['performance'] as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: Text('Dashboard cycle ${widget.bande.nom}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _perfChip('Effectif initial', '${perf['effectifInitial'] ?? 0}'),
              _perfChip('Effectif restant', '${perf['effectifRestant'] ?? 0}'),
              _perfChip('Mortalité cumulée', '${(perf['mortaliteCumulee'] ?? 0).toStringAsFixed(2)} %'),
              _perfChip('Conso cumulée', '${(perf['consommationCumuleeKg'] ?? 0).toStringAsFixed(2)} kg'),
              _perfChip('Poids final', '${(perf['poidsMoyenFinal'] ?? 0).toStringAsFixed(0)} g'),
              _perfChip('Écart poids théorique', '${(perf['ecartPoidsTheoriquePct'] ?? 0).toStringAsFixed(2)} %'),
              _perfChip('Écart conso théorique', '${(perf['ecartConsoTheoriquePct'] ?? 0).toStringAsFixed(2)} %'),
            ],
          ),
          const SizedBox(height: 12),
          _cardChart('Courbe de croissance (réel vs théorique)', _lineChart(growth, 'poids', Colors.green, second: theoriqueGrowth, secondYKey: 'poids', secondColor: Colors.orange)),
          _cardChart('Consommation cumulée (réel vs théorique)', _lineChart(conso, 'cumulKg', Colors.brown, second: theoriqueConso, secondYKey: 'cumulKg', secondColor: Colors.blueGrey)),
          _cardChart('Mortalité par jour', _barChart(mortality, 'mortalite', Colors.red)),
          _forecastCard(forecast7j, eventsPrevisionnels),
        ],
      ),
    );
  }

  Widget _forecastCard(List<dynamic> forecast7j, List<dynamic> events) {
    if (forecast7j.isEmpty && events.isEmpty) {
      return const SizedBox.shrink();
    }

    final horizon = forecast7j.isNotEmpty ? forecast7j.last as Map<String, dynamic> : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Prévisionnel 7 jours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (horizon != null)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text('Poids projeté: ${_fmt(horizon['poidsProjete'], digits: 0)} g'),
                  Text('Conso cumulée projetée: ${_fmt(horizon['consoCumulProjeteeKg'])} kg'),
                  Text('Mortalité/j projetée: ${_fmt(horizon['mortaliteJourProjetee'])}'),
                ],
              ),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Événements prévisionnels', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...events.map((e) {
                final evt = e as Map<String, dynamic>;
                final sev = (evt['severite'] ?? '').toString();
                final color = sev == 'haute' ? Colors.red : Colors.orange;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text((evt['message'] ?? '').toString())),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _perfChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.green.shade50,
    );
  }

  Widget _cardChart(String title, Widget chart) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: chart),
          ],
        ),
      ),
    );
  }

  Widget _lineChart(
    List<dynamic> raw,
    String yKey,
    Color color, {
    List<dynamic>? second,
    String? secondYKey,
    Color? secondColor,
  }) {
    if (raw.isEmpty) return const Center(child: Text('Pas de données'));

    final spots = <FlSpot>[];
    for (var i = 0; i < raw.length; i++) {
      final age = (raw[i]['age'] ?? (i + 1)).toDouble();
      spots.add(FlSpot(age, (raw[i][yKey] ?? 0).toDouble()));
    }

    final secondSpots = <FlSpot>[];
    if (second != null && secondYKey != null && second.isNotEmpty) {
      for (var i = 0; i < second.length; i++) {
        final age = (second[i]['age'] ?? (i + 1)).toDouble();
        secondSpots.add(FlSpot(age, (second[i][secondYKey] ?? 0).toDouble()));
      }
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(spots: spots, isCurved: true, color: color, barWidth: 3, dotData: const FlDotData(show: false)),
          if (secondSpots.isNotEmpty)
            LineChartBarData(
              spots: secondSpots,
              isCurved: true,
              color: secondColor ?? Colors.orange,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              dashArray: [6, 4],
            ),
        ],
      ),
    );
  }

  Widget _barChart(List<dynamic> raw, String yKey, Color color) {
    if (raw.isEmpty) return const Center(child: Text('Pas de données'));

    final bars = <BarChartGroupData>[];
    for (var i = 0; i < raw.length; i++) {
      final age = (raw[i]['age'] ?? i).toInt();
      bars.add(
        BarChartGroupData(
          x: age,
          barRods: [
            BarChartRodData(toY: (raw[i][yKey] ?? 0).toDouble(), color: color, width: 8)
          ],
        ),
      );
    }

    return BarChart(BarChartData(barGroups: bars));
  }

  String _fmt(dynamic value, {int digits = 2}) {
    if (value is num) return value.toStringAsFixed(digits);
    return '0';
  }
}
