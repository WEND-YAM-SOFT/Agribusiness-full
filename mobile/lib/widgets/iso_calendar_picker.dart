import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

Future<DateTime?> showIsoDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Choisir une date',
}) async {
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => _IsoDatePickerDialog(
      title: title,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

Future<DateTimeRange?> showIsoDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String title = 'Choisir un intervalle',
}) async {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (dialogContext) => _IsoDateRangePickerDialog(
      title: title,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
    ),
  );
}

class _IsoDatePickerDialog extends StatefulWidget {
  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _IsoDatePickerDialog({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_IsoDatePickerDialog> createState() => _IsoDatePickerDialogState();
}

class _IsoDatePickerDialogState extends State<_IsoDatePickerDialog> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDate;
    _focusedDay = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = width > 560 ? 420.0 : width - 36;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: TableCalendar<void>(
          locale: locale,
          firstDay: DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day),
          lastDay: DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day),
          focusedDay: _focusedDay,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
          startingDayOfWeek: StartingDayOfWeek.monday,
          weekNumbersVisible: true,
          selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
          },
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(fontWeight: FontWeight.w700),
            leftChevronIcon: Icon(Icons.chevron_left, color: cs.primary),
            rightChevronIcon: Icon(Icons.chevron_right, color: cs.primary),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600) ?? const TextStyle(fontWeight: FontWeight.w600),
            weekendStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: cs.error) ?? TextStyle(fontWeight: FontWeight.w700, color: cs.error),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: true,
            weekendTextStyle: TextStyle(color: cs.error),
            selectedDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.35), shape: BoxShape.circle),
            weekNumberTextStyle: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700) ?? TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedDay = DateTime.now();
              _focusedDay = _selectedDay;
            });
          },
          child: const Text('Aujourd\'hui'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedDay),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _IsoDateRangePickerDialog extends StatefulWidget {
  final String title;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  const _IsoDateRangePickerDialog({
    required this.title,
    required this.firstDate,
    required this.lastDate,
    this.initialDateRange,
  });

  @override
  State<_IsoDateRangePickerDialog> createState() => _IsoDateRangePickerDialogState();
}

class _IsoDateRangePickerDialogState extends State<_IsoDateRangePickerDialog> {
  late DateTime _focusedDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialDateRange?.start;
    _rangeEnd = widget.initialDateRange?.end;
    _focusedDay = widget.initialDateRange?.start ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = width > 560 ? 420.0 : width - 36;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TableCalendar<void>(
              locale: locale,
              firstDay: DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day),
              lastDay: DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
              startingDayOfWeek: StartingDayOfWeek.monday,
              weekNumbersVisible: true,
              rangeStartDay: _rangeStart,
              rangeEndDay: _rangeEnd,
              rangeSelectionMode: RangeSelectionMode.toggledOn,
              onRangeSelected: (start, end, focusedDay) {
                setState(() {
                  _rangeStart = start;
                  _rangeEnd = end;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(fontWeight: FontWeight.w700),
                leftChevronIcon: Icon(Icons.chevron_left, color: cs.primary),
                rightChevronIcon: Icon(Icons.chevron_right, color: cs.primary),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600) ?? const TextStyle(fontWeight: FontWeight.w600),
                weekendStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: cs.error) ?? TextStyle(fontWeight: FontWeight.w700, color: cs.error),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: true,
                weekendTextStyle: TextStyle(color: cs.error),
                rangeHighlightColor: cs.primary.withValues(alpha: 0.15),
                rangeStartDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                rangeEndDecoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                withinRangeDecoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                todayDecoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.35), shape: BoxShape.circle),
                weekNumberTextStyle: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700) ?? TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _rangeStart == null
                  ? 'Sélectionnez une date de début'
                  : _rangeEnd == null
                      ? 'Sélectionnez une date de fin'
                      : 'Du ${_rangeStart!.day}/${_rangeStart!.month}/${_rangeStart!.year} au ${_rangeEnd!.day}/${_rangeEnd!.month}/${_rangeEnd!.year}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final now = DateTime.now();
            setState(() {
              _rangeStart = now;
              _rangeEnd = now;
              _focusedDay = now;
            });
          },
          child: const Text('Aujourd\'hui'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _rangeStart = null;
              _rangeEnd = null;
            });
          },
          child: const Text('Réinitialiser'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: (_rangeStart != null && _rangeEnd != null)
              ? () => Navigator.of(context).pop(DateTimeRange(start: _rangeStart!, end: _rangeEnd!))
              : null,
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
