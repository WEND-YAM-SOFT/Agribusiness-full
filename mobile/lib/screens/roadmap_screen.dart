import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/iso_calendar_picker.dart';

class RoadmapMilestone {
  final String id;
  final String title;
  final DateTime date;
  final Color color;

  RoadmapMilestone({
    required this.id,
    required this.title,
    required this.date,
    required this.color,
  });

  factory RoadmapMilestone.fromJson(Map<String, dynamic> json) {
    final colorValue = (json['color'] is int)
        ? json['color'] as int
        : int.tryParse((json['color'] ?? '').toString()) ?? Colors.blue.toARGB32();
    return RoadmapMilestone(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
      color: Color(colorValue),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'color': color.toARGB32(),
    };
  }
}

class RoadmapTask {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final Color color;
  final bool group;
  final List<RoadmapMilestone> milestones;
  final List<RoadmapTask> subTasks;

  RoadmapTask({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    this.group = false,
    this.milestones = const [],
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
        milestones: (json['milestones'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RoadmapMilestone.fromJson)
          .toList(),
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
      'milestones': milestones.map((m) => m.toJson()).toList(),
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

class _RoadmapGridPainter extends CustomPainter {
  _RoadmapGridPainter({required this.monthsTotal, required this.monthWidth});

  final int monthsTotal;
  final double monthWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final evenPaint = Paint()..color = Colors.grey.shade100;
    final oddPaint = Paint()..color = Colors.grey.shade200;
    final dashPaint = Paint()
      ..color = Colors.blueGrey.shade300
      ..strokeWidth = 1;

    for (var index = 0; index < monthsTotal; index += 1) {
      final left = monthWidth * index;
      final rect = Rect.fromLTWH(left, 0, monthWidth, size.height);
      canvas.drawRect(rect, index.isEven ? evenPaint : oddPaint);

      if (index > 0) {
        final x = left;
        var y = 0.0;
        while (y < size.height) {
          canvas.drawLine(Offset(x, y), Offset(x, (y + 4).clamp(0, size.height)), dashPaint);
          y += 8;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadmapGridPainter oldDelegate) {
    return oldDelegate.monthsTotal != monthsTotal || oldDelegate.monthWidth != monthWidth;
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
  double _zoom = 1.0;
  static const double _baseMonthWidth = 72;
  static const String _plansPrefsKey = 'roadmap.productionPlans';
  static const String _selectedPlanPrefsKey = 'roadmap.selectedPlanId';
  static const List<Color> _taskColors = [
    Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFFE53935),
    Color(0xFF00897B), Color(0xFFF4511E), Color(0xFF3949AB), Color(0xFF7CB342), Color(0xFF6D4C41),
    Color(0xFF00ACC1), Color(0xFF5E35B1), Color(0xFFC0CA33), Color(0xFFD81B60), Color(0xFF546E7A),
    Color(0xFF039BE5), Color(0xFF7E57C2), Color(0xFFFF7043), Color(0xFF26A69A), Color(0xFF8D6E63),
    Color(0xFFEF5350), Color(0xFFAB47BC), Color(0xFF66BB6A), Color(0xFFFFCA28), Color(0xFF29B6F6),
    Color(0xFFFF8A65), Color(0xFF9CCC65), Color(0xFF42A5F5), Color(0xFFA1887F), Color(0xFF26C6DA),
  ];

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

  int _monthSpan(DateTime start, DateTime end) {
    return ((end.year - start.year) * 12) + (end.month - start.month) + 1;
  }

  double _dateToMonthUnit(DateTime planStart, DateTime date, {bool endInclusive = false}) {
    final planMonthStart = DateTime(planStart.year, planStart.month, 1);
    final monthOffset = ((date.year - planMonthStart.year) * 12) + (date.month - planMonthStart.month);
    final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
    final numerator = (date.day - 1) + (endInclusive ? 1 : 0);
    final fraction = (numerator / daysInMonth).clamp(0.0, 1.0);
    return monthOffset + fraction;
  }

  double _monthWidth() => _baseMonthWidth * _zoom;

  double _timelineWidth(ProductionPlan plan) {
    return _monthSpan(plan.start, plan.end) * _monthWidth();
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
            onPressed: _plans.isEmpty ? null : _showDeleteAllPlansDialog,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Supprimer tous les plannings',
          ),
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
                        trailing: IconButton(
                          tooltip: 'Supprimer planning',
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _showDeletePlanDialog(p),
                        ),
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
                      onPressed: () => _showEditPlanDialog(plan),
                      icon: const Icon(Icons.edit_calendar),
                      label: const Text('Modifier planning'),
                    ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Zoom -',
                      onPressed: () => setState(() => _zoom = (_zoom - 0.1).clamp(0.1, 3.0)),
                      icon: const Icon(Icons.zoom_out),
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 0.1,
                        max: 3.0,
                        divisions: 29,
                        label: '${(_zoom * 100).toStringAsFixed(0)}%',
                        onChanged: (v) => setState(() => _zoom = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom +',
                      onPressed: () => setState(() => _zoom = (_zoom + 0.1).clamp(0.1, 3.0)),
                      icon: const Icon(Icons.zoom_in),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: plan.tasks.isEmpty
                ? const Center(child: Text('Ajoutez des tâches pour construire la roadmap'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final timelineWidth = _timelineWidth(plan).clamp(constraints.maxWidth, double.infinity);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: timelineWidth,
                          height: constraints.maxHeight,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _buildMonthHeader(plan),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: plan.tasks.map((t) => _buildTaskTile(t, plan)).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

    return SizedBox(
      key: const ValueKey('roadmap-header-timeline'),
      width: _timelineWidth(plan),
      child: Row(
        children: months.map((m) {
          final highlighted = plan.highlightedDates.any((d) => d.year == m.year && d.month == m.month);
          return Container(
            key: ValueKey('roadmap-month-${m.year}-${m.month}'),
            width: _monthWidth(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: highlighted ? Colors.amber.shade100 : Colors.blueGrey.shade50,
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
    final monthsTotal = _monthSpan(plan.start, plan.end);
    final startOffset = _dateToMonthUnit(plan.start, task.start).clamp(0.0, monthsTotal.toDouble());
    final endOffset = _dateToMonthUnit(plan.start, task.end, endInclusive: true).clamp(0.0, monthsTotal.toDouble());
    final barDuration = (endOffset - startOffset).clamp(0.12, monthsTotal.toDouble());

    return Card(
      margin: EdgeInsets.only(left: indent, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () => _showTaskActionsSheet(plan, task),
              child: Text(task.title, style: TextStyle(fontWeight: task.group ? FontWeight.w700 : FontWeight.w500)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              key: ValueKey('roadmap-task-timeline-${task.id}'),
              width: _timelineWidth(plan),
              height: 24,
              child: CustomPaint(
                painter: _RoadmapGridPainter(monthsTotal: monthsTotal, monthWidth: _monthWidth()),
                child: Stack(
                  children: [
                    Positioned(
                      key: ValueKey('roadmap-bar-${task.id}'),
                      left: _monthWidth() * startOffset,
                      top: 3,
                      child: Container(
                        width: _monthWidth() * barDuration,
                        height: 18,
                        decoration: BoxDecoration(color: task.color, borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                    ...task.milestones.map((m) {
                      final unit = _dateToMonthUnit(plan.start, m.date).clamp(0.0, monthsTotal.toDouble());
                      return Positioned(
                        left: (_monthWidth() * unit) - 7,
                        top: 1,
                        child: GestureDetector(
                          onTap: () => _showEditMilestoneDialog(plan, task, m),
                          onLongPress: () => _showDeleteMilestoneDialog(plan, task, m),
                          child: Icon(Icons.flag, size: 14, color: m.color),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${DateFormat('dd/MM/yyyy').format(task.start)} -> ${DateFormat('dd/MM/yyyy').format(task.end)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'Ajouter jalon',
              onPressed: () => _showAddMilestoneDialog(plan, task),
              icon: const Icon(Icons.flag_outlined, size: 18),
            ),
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
    Color selectedColor = _taskColors.first;
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
                  runSpacing: 8,
                  children: _taskColors
                      .map((c) => _colorDot(c, selectedColor, () => setDialogState(() => selectedColor = c)))
                      .toList(),
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
                        milestones: g.milestones,
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

  Future<void> _showEditPlanDialog(ProductionPlan plan) async {
    final nameCtrl = TextEditingController(text: plan.name);
    DateTimeRange range = DateTimeRange(start: plan.start, end: plan.end);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier planning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom du planning *')),
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
                  if (picked != null) setDialogState(() => range = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: nameCtrl.text.trim(),
                    start: range.start,
                    end: range.end,
                    tasks: current.tasks,
                    highlightedDates: current.highlightedDates,
                  );
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditTaskDialog(ProductionPlan plan, RoadmapTask task) async {
    final titleCtrl = TextEditingController(text: task.title);
    DateTimeRange range = DateTimeRange(start: task.start, end: task.end);
    Color selectedColor = task.color;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier tâche'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre *')),
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
                  runSpacing: 8,
                  children: _taskColors
                      .map((c) => _colorDot(c, selectedColor, () => setDialogState(() => selectedColor = c)))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final updated = RoadmapTask(
                  id: task.id,
                  title: titleCtrl.text.trim(),
                  start: range.start,
                  end: range.end,
                  color: selectedColor,
                  group: task.group,
                  milestones: task.milestones,
                  subTasks: task.subTasks,
                );
                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: current.name,
                    start: current.start,
                    end: current.end,
                    tasks: _replaceTask(current.tasks, updated),
                    highlightedDates: current.highlightedDates,
                  );
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  List<RoadmapTask> _replaceTask(List<RoadmapTask> tasks, RoadmapTask updated) {
    return tasks.map((t) {
      if (t.id == updated.id) {
        return updated;
      }
      if (t.subTasks.isEmpty) return t;
      return RoadmapTask(
        id: t.id,
        title: t.title,
        start: t.start,
        end: t.end,
        color: t.color,
        group: t.group,
        milestones: t.milestones,
        subTasks: _replaceTask(t.subTasks, updated),
      );
    }).toList();
  }

  Future<void> _showAddMilestoneDialog(ProductionPlan plan, RoadmapTask task) async {
    final titleCtrl = TextEditingController();
    DateTime date = task.start;
    Color selectedColor = task.color;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter jalon'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre du jalon *')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date du jalon'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                  trailing: const Icon(Icons.date_range),
                  onTap: () async {
                    final picked = await showIsoDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: plan.start,
                      lastDate: plan.end,
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _taskColors
                      .map((c) => _colorDot(c, selectedColor, () => setDialogState(() => selectedColor = c)))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final milestone = RoadmapMilestone(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim(),
                  date: date,
                  color: selectedColor,
                );
                final updatedTask = RoadmapTask(
                  id: task.id,
                  title: task.title,
                  start: task.start,
                  end: task.end,
                  color: task.color,
                  group: task.group,
                  milestones: [...task.milestones, milestone],
                  subTasks: task.subTasks,
                );
                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: current.name,
                    start: current.start,
                    end: current.end,
                    tasks: _replaceTask(current.tasks, updatedTask),
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

  Future<void> _showEditMilestoneDialog(ProductionPlan plan, RoadmapTask task, RoadmapMilestone milestone) async {
    final titleCtrl = TextEditingController(text: milestone.title);
    DateTime date = milestone.date;
    Color selectedColor = milestone.color;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier jalon'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre du jalon *')),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date du jalon'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                  trailing: const Icon(Icons.date_range),
                  onTap: () async {
                    final picked = await showIsoDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: plan.start,
                      lastDate: plan.end,
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _taskColors
                      .map((c) => _colorDot(c, selectedColor, () => setDialogState(() => selectedColor = c)))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                final updatedMilestones = task.milestones.where((m) => m.id != milestone.id).toList();
                final updatedTask = RoadmapTask(
                  id: task.id,
                  title: task.title,
                  start: task.start,
                  end: task.end,
                  color: task.color,
                  group: task.group,
                  milestones: updatedMilestones,
                  subTasks: task.subTasks,
                );
                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: current.name,
                    start: current.start,
                    end: current.end,
                    tasks: _replaceTask(current.tasks, updatedTask),
                    highlightedDates: current.highlightedDates,
                  );
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('Supprimer jalon'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final updatedMilestones = task.milestones.map((m) {
                  if (m.id != milestone.id) return m;
                  return RoadmapMilestone(
                    id: m.id,
                    title: titleCtrl.text.trim(),
                    date: date,
                    color: selectedColor,
                  );
                }).toList();
                final updatedTask = RoadmapTask(
                  id: task.id,
                  title: task.title,
                  start: task.start,
                  end: task.end,
                  color: task.color,
                  group: task.group,
                  milestones: updatedMilestones,
                  subTasks: task.subTasks,
                );
                setState(() {
                  final idx = _plans.indexWhere((p) => p.id == plan.id);
                  if (idx < 0) return;
                  final current = _plans[idx];
                  _plans[idx] = ProductionPlan(
                    id: current.id,
                    name: current.name,
                    start: current.start,
                    end: current.end,
                    tasks: _replaceTask(current.tasks, updatedTask),
                    highlightedDates: current.highlightedDates,
                  );
                });
                _savePlans();
                Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteTaskDialog(ProductionPlan plan, RoadmapTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer tâche'),
        content: Text('Supprimer "${task.title}" et ses sous-tâches ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      final idx = _plans.indexWhere((p) => p.id == plan.id);
      if (idx < 0) return;
      final current = _plans[idx];
      _plans[idx] = ProductionPlan(
        id: current.id,
        name: current.name,
        start: current.start,
        end: current.end,
        tasks: _removeTask(current.tasks, task.id),
        highlightedDates: current.highlightedDates,
      );
    });
    _savePlans();
  }

  Future<void> _showTaskActionsSheet(ProductionPlan plan, RoadmapTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Modifier tâche'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditTaskDialog(plan, task);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Supprimer tâche'),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteTaskDialog(plan, task);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteMilestoneDialog(ProductionPlan plan, RoadmapTask task, RoadmapMilestone milestone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer jalon'),
        content: Text('Supprimer le jalon "${milestone.title}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final updatedTask = RoadmapTask(
      id: task.id,
      title: task.title,
      start: task.start,
      end: task.end,
      color: task.color,
      group: task.group,
      milestones: task.milestones.where((m) => m.id != milestone.id).toList(),
      subTasks: task.subTasks,
    );

    setState(() {
      final idx = _plans.indexWhere((p) => p.id == plan.id);
      if (idx < 0) return;
      final current = _plans[idx];
      _plans[idx] = ProductionPlan(
        id: current.id,
        name: current.name,
        start: current.start,
        end: current.end,
        tasks: _replaceTask(current.tasks, updatedTask),
        highlightedDates: current.highlightedDates,
      );
    });
    _savePlans();
  }

  List<RoadmapTask> _removeTask(List<RoadmapTask> tasks, String taskId) {
    final out = <RoadmapTask>[];
    for (final t in tasks) {
      if (t.id == taskId) continue;
      out.add(
        RoadmapTask(
          id: t.id,
          title: t.title,
          start: t.start,
          end: t.end,
          color: t.color,
          group: t.group,
          milestones: t.milestones,
          subTasks: _removeTask(t.subTasks, taskId),
        ),
      );
    }
    return out;
  }

  Future<void> _showDeletePlanDialog(ProductionPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer planning'),
        content: Text('Supprimer le planning "${plan.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _plans.removeWhere((p) => p.id == plan.id);
      if (_selectedPlanId == plan.id) {
        _selectedPlanId = _plans.isEmpty ? null : _plans.first.id;
      }
    });
    _savePlans();
  }

  Future<void> _showDeleteAllPlansDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer tous les plannings'),
        content: const Text('Cette action supprimera tous les plannings et toutes les tâches. Continuer ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tout supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _plans.clear();
      _selectedPlanId = null;
    });
    _savePlans();
  }
}
