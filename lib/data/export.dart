import 'dart:convert';

import 'ledger.dart';

/// The whole ledger as JSON, in the format the app saves. `/import` reads it
/// back, so it doubles as a backup file.
String exportJson(Ledger ledger) =>
    const JsonEncoder.withIndent('  ').convert(ledger.toJson());

/// The columns of [exportCsv], in order.
const csvColumns = [
  'Date',
  'Type',
  'Description',
  'Category',
  'Group',
  'Amount',
  'Paid by',
  'Your share',
  'Shared with',
  'In your spending',
];

/// Every expense, payment and money in as CSV, oldest first, one row each,
/// for opening in a spreadsheet.
///
/// Amounts are rupees with two decimals and no symbol or grouping, so
/// spreadsheets read them as numbers. "Your share" is what an expense cost
/// you; "Shared with" lists everyone in it with their share. Starts with a
/// byte order mark so Excel reads names as UTF-8.
String exportCsv(Ledger ledger) {
  final rows = <({DateTime date, List<String> cells})>[];
  String names(Iterable<String> ids) => ids.map(ledger.nameOf).join(', ');
  String group(String billId) => ledger.bill(billId)?.name ?? '';

  for (final e in ledger.expenses) {
    final category = ledger.category(e.categoryId);
    final mine = e.shares[me] ?? 0;
    rows.add((
      date: e.date,
      cells: [
        _date(e.date),
        'Expense',
        e.name,
        category?.name ?? '',
        group(e.billId),
        _amount(e.amount),
        ledger.nameOf(e.payerId),
        _amount(mine),
        [
          for (final MapEntry(:key, :value) in e.shares.entries)
            '${ledger.nameOf(key)} ${_amount(value)}',
        ].join('; '),
        mine > 0 && (category?.counted ?? true) ? 'Yes' : 'No',
      ],
    ));
  }
  for (final p in ledger.payments) {
    final received = p.direction == Direction.received;
    final towards = [
      for (final id in p.settles.keys) ?ledger.expense(id)?.name,
    ];
    rows.add((
      date: p.date,
      cells: [
        _date(p.date),
        received ? 'Received' : 'Sent',
        [
          received
              ? 'From ${ledger.nameOf(p.friendId)}'
              : 'To ${ledger.nameOf(p.friendId)}',
          if (towards.isNotEmpty) 'for ${towards.join(', ')}',
        ].join(' '),
        '',
        group(p.billId),
        _amount(p.amount),
        received ? ledger.nameOf(p.friendId) : ledger.nameOf(me),
        '',
        names([p.friendId]),
        'No',
      ],
    ));
  }
  for (final i in ledger.incomes) {
    rows.add((
      date: i.date,
      cells: [
        _date(i.date),
        'Money in',
        i.note ?? '',
        '',
        '',
        _amount(i.amount),
        i.from,
        '',
        '',
        'No',
      ],
    ));
  }

  // Stable, so records on the same day keep their order within each type.
  final sorted = rows.indexed.toList()
    ..sort((a, b) {
      final byDate = a.$2.date.compareTo(b.$2.date);
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
  final lines = [
    csvColumns,
    for (final (_, row) in sorted) row.cells,
  ].map((cells) => cells.map(_cell).join(','));
  return '\uFEFF${lines.join('\r\n')}\r\n';
}

/// "between-2026-11-08.csv", for a file saved on [date].
String exportFileName(DateTime date, String extension) =>
    'between-${_date(date)}.$extension';

/// "2026-11-08".
String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// [paise] as "1200.50".
String _amount(int paise) =>
    '${paise < 0 ? '-' : ''}${paise.abs() ~/ 100}.'
    '${(paise.abs() % 100).toString().padLeft(2, '0')}';

/// [text] quoted for CSV when it needs to be. A leading `=`, `+`, `-` or `@`
/// gets an apostrophe so spreadsheets don't run it as a formula.
String _cell(String text) {
  final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(text) ? "'$text" : text;
  return RegExp(r'[",\r\n]').hasMatch(safe)
      ? '"${safe.replaceAll('"', '""')}"'
      : safe;
}
