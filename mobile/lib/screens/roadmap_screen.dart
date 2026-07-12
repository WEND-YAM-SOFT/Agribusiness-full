import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/iso_calendar_picker.dart';

class RoadmapTask {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final Color color;
  final bool group;
  final List<RoadmapTask> subTasks;

  RoadmapTask({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    this.group = false,
    this.subTasks = const [],
  });

  factory RoadmapTask.fromJson(Map<String, dynamic> json) {
    final colorValue = (json['color'] is int)
        ? json['color'] as int
      : int.tryParse((json['color'] ?? '').toString()) ?? Colors.blue.toARGB32();
    return RoadmapTask(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      start: DateTime.tryParse((json['start'] ?? '').toString()) ?? DateTime.now(),
      end: DateTime.tryParse((json['end'] ?? '').toString()) ?? DateTime.now(),
      color: Color(colorValue),
      group: json['group'] == true,
      subTasks: (json['subTasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RoadmapTask.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'color': color.toARGB32(),
      'group': group,
      'subTasks': subTasks.map((t) => t.toJson()).toList(),
    };
  }
}

class ProductionPlan {
  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final List<RoadmapTask> tasks;
  final List<DateTime> highlightedDates;

  ProductionPlan({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.tasks = const [],
    this.highlightedDates = const [],
  });

  factory ProductionPlan.fromJson(Map<String, dynamic> json) {
    return ProductionPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      start: DateTime.tryParse((json['start'] ?? '').toString()) ?? DateTime.now(),
      end: DateTime.tryParse((json['end'] ?? '').toString()) ?? DateTime.now(),
      tasks: (json['tasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map( RoadmapTask.fromJson)
          .toList(),
      highlightedDates: (json['highlightedDates'] as List<dynamic>? ?? const [])
          .map((e) => DateTime.tryParse(e.toString()))
          .whereType<DateTime>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'highlightedDates': highlightedDates.map((d) => d.toIso8601String()).toList(),
    };
  }
}

class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  final List<ProductionPlan> _plans = [];
  String? _selectedPlanId;
  static const String _plansPrefsKey = 'roadmap.productionPlans';
  static const String _selectedPlanPrefsKey = 'roadmap.selectedPlanId';

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  ProductionPlan? get _selectedPlan {
    if (_selectedPlanId == null) return null;
    for (final p in _plans) {
      if (p.id == _selectedPlanId) return p;
    }
    return null;
  }

  Future<void> _loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_plansPrefsKey);
    final selected = prefs.getString(_selectedPlanPrefsKey);

    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return;
      final loaded = decoded
          .whereType<Map<String, dynamic>>()
          .map(ProductionPlan.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _plans
          ..clear()
          ..addAll(loaded);
        if (_plans.isEmpty) {
          _selectedPlanId = null;
        } else if (selected != null && _plans.any((p) => p.id == selected)) {
          _selectedPlanId = selected;
        } else {
          _selectedPlanId = _plans.first.id;
        }
      });
    } catch (_) {
      // Ignore malformed persisted roadmap data.
    }
  }

  Future<void> _savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plansPrefsKey, json.encode(_plans.map((p) => p.toJson()).toList()));
    if (_selectedPlanId != null && _selectedPlanId!.isNotEmpty) {
      await prefs.setString(_selectedPlanPrefsKey, _selectedPlanId!);
    } else {
      await prefs.remove(_selectedPlanPrefsKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _selectedPlan;
    final isWide = MediaQuery.of(context).size.width >= 960;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roadmap production'),
        actions: [
          IconButton(
            onPressed: _plans.length >= 5 ? null : _showCreatePlanDialog,
            icon: const Icon(Icons.add_chart),
            tooltip: 'Nouveau planning',
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                SizedBox(width: 280, child: _buildPlansPanel()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    child: _buildPlanDetails(plan),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                SizedBox(height: 250, child: _buildPlansPanel()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildPlanDetails(plan),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPlansPanel() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        children: [
          ListTile(
            title: const Text('Plannings', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${_plans.length}/5'),
            trailing: IconButton(
              onPressed: _plans.length >= 5 ? null : _showCreatePlanDialog,
              icon: const Icon(Icons.add),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _plans.isEmpty
                ? const Center(child: Text('Créez votre premier planning'))
                : ListView.builder(
                    itemCount: _plans.length,
                    itemBuilder: (context, index) {
                      final p = _plans[index];
                      final selected = p.id == _selectedPlanId;
                      return ListTile(
                        selected: selected,
                        title: Text(p.name),
                        subtitle: Text('${DateFormat('MM/yyyy').format(p.start)} - ${DateFormat('MM/yyyy').format(p.end)}'),
                        onTap: () {
                          setState(() => _selectedPlanId = p.id);
                          _savePlans();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDetails(ProductionPlan? plan) {
    if (plan == null) return const Card(child: Center(child: Text('Sélectionnez ou créez un planning')));

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Macro planning mensuel - ${DateFormat('yyyy').format(plan.start)} à ${DateFormat('yyyy').format(plan.end)}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showAddTaskDialog(plan, asSubtask: false),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Tâche'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showAddTaskDialog(plan, asSubtask: true),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Sous-tâche'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showHighlightDateDialog(plan),
                      icon: const Icon(Icons.flag),
                      label: const Text('Date clé'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildMonthHeader(plan),
          const Divider(height: 1),
          Expanded(
            child: plan.tasks.isEmpty
                ? const Center(child: Text('Ajoutez des tâches pour construire la roadmap'))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: plan.tasks.map((t) => _buildTaskTile(t, plan)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(ProductionPlan plan) {
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final months = <DateTime>[];
    final first = DateTime(plan.start.year, plan.start.month, 1);
    final last = DateTime(plan.end.year, plan.end.month, 1);
    var cursor = first;
    while (!cursor.isAfter(last)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: months.map((m) {
          final highlighted = plan.highlightedDates.any((d) => d.year == m.year && d.month == m.month);
          return Container(
            width: 90,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: highlighted ? Colors.amber.shade100 : Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: highlighted ? Colors.amber.shade700 : Colors.blueGrey.shade200),
            ),
            child: Column(
              children: [
                Text(DateFormat('MMM', localeTag).format(m).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${m.year}', style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaskTile(RoadmapTask task, ProductionPlan plan, {double indent = 0}) {
    final monthsTotal = ((plan.end.year - plan.start.year) * 12) + (plan.end.month - plan.start.month) + 1;
    final startOffset = ((task.start.year - plan.start.year) * 12) + (task.start.month - plan.start.month);
    final duration = ((task.end.year - task.start.year) * 12) + (task.end.month - task.start.month) + 1;

    return Card(
      margin: EdgeInsets.only(left: indent, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: TextStyle(fontWeight: task.group ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final unit = width / (monthsTotal <= 0 ? 1 : monthsTotal);
                final left = unit * startOffset.clamp(0, monthsTotal);
                final barWidth = unit * duration.clamp(1, monthsTotal);
                return SizedBox(
                  height: 18,
                  child: Stack(
                    children: [
                      Container(height: 18, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(9))),
                      Positioned(
                        left: left,
                        child: Container(
                          width: barWidth,
                          height: 18,
                          decoration: BoxDecoration(color: task.color, borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text('${DateFormat('MM/yyyy').format(task.start)} -> ${DateFormat('MM/yyyy').format(task.end)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (task.subTasks.isNotEmpty) ...task.subTasks.map((s) => _buildTaskTile(s, plan, indent: indent + 16)),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreatePlanDialog() async {
    final name = TextEditingController();
    DateTimeRange range = DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 365)));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouveau planning macro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom du planning *')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Période du planning'),
                subtitle: Text('${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}'),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showIsoDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    initialDateRange: range,
                  );
                  if (picked != null) {
                    final months = ((picked.end.year - picked.start.year) * 12) + (picked.end.month - picked.start.month) + 1;
                    if (months > 60) return;
                    setDialogState(() => range = picked);
                  }
                },
              ),
              const Text('Durée max: 5 ans', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (name.text.trim().isEmpty || _plans.length >= 5) return;
                final id = DateTime.now().microsecondsSinceEpoch.toString();
                final plan = ProductionPlan(id: id, name: name.text.trim(), start: range.start, end: range.end);
                setState(() {
                  _plans.add(plan);
                  _selectedPlanId = id;
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTaskDialog(ProductionPlan plan, {required bool asSubtask}) async {
    final title = TextEditingController();
    DateTimeRange range = DateTimeRange(start: plan.start, end: DateTime(plan.start.year, plan.start.month + 1, 1));
    Color selectedColor = Colors.blue;
    RoadmapTask? selectedGroup;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(asSubtask ? 'Nouvelle sous-tâche' : 'Nouvelle tâche'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Titre *')),
                if (asSubtask)
                  DropdownButtonFormField<RoadmapTask>(
                    initialValue: selectedGroup,
                    items: plan.tasks
                        .where((t) => t.group)
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.title)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedGroup = v),
                    decoration: const InputDecoration(labelText: 'Tâche de regroupement *'),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Période de la tâche'),
                  subtitle: Text('${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}'),
                  trailing: const Icon(Icons.date_range),
                  onTap: () async {
                    final picked = await showIsoDateRangePicker(
                      context: context,
                      firstDate: plan.start,
                      lastDate: plan.end,
                      initialDateRange: range,
                    );
                    if (picked != null) setDialogState(() => range = picked);
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _colorDot(Colors.blue, selectedColor, () => setDialogState(() => selectedColor = Colors.blue)),
                    _colorDot(Colors.green, selectedColor, () => setDialogState(() => selectedColor = Colors.green)),
                    _colorDot(Colors.orange, selectedColor, () => setDialogState(() => selectedColor = Colors.orange)),
                    _colorDot(Colors.purple, selectedColor, () => setDialogState(() => selectedColor = Colors.purple)),
                    _colorDot(Colors.red, selectedColor, () => setDialogState(() => selectedColor = Colors.red)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                if (asSubtask && selectedGroup == null) return;
                final task = RoadmapTask(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title.text.trim(),
                  start: range.start,
                  end: range.end,
                  color: selectedColor,
                  group: !asSubtask,
                );

                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  final tasks = [...current.tasks];

                  if (asSubtask) {
                    final gIndex = tasks.indexWhere((t) => t.id == selectedGroup!.id);
                    if (gIndex >= 0) {
                      final g = tasks[gIndex];
                      tasks[gIndex] = RoadmapTask(
                        id: g.id,
                        title: g.title,
                        start: g.start,
                        end: g.end,
                        color: g.color,
                        group: g.group,
                        subTasks: [...g.subTasks, task],
                      );
                    }
                  } else {
                    tasks.add(task);
                  }

                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: current.name,
                    start: current.start,
                    end: current.end,
                    tasks: tasks,
                    highlightedDates: current.highlightedDates,
                  );
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(Color color, Color selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected == color ? Colors.black : Colors.transparent, width: 2),
        ),
      ),
    );
  }

  Future<void> _showHighlightDateDialog(ProductionPlan plan) async {
    final picked = await showIsoDatePicker(
      context: context,
      initialDate: plan.start,
      firstDate: plan.start,
      lastDate: plan.end,
    );
    if (picked == null) return;

    setState(() {
      final idx = _plans.indexWhere((p) => p.id == plan.id);
      if (idx < 0) return;
      final current = _plans[idx];
      _plans[idx] = ProductionPlan(
        id: current.id,
        name: current.name,
        start: current.start,
        end: current.end,
        tasks: current.tasks,
        highlightedDates: [...current.highlightedDates, picked],
      );
    });
    _savePlans();
  }
}
