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

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
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
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: true,
          ),
        ),
      ),
      actions: [
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

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
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
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: const CalendarStyle(
                outsideDaysVisible: true,
                rangeHighlightColor: Color(0x332196F3),
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
