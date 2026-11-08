import 'dart:convert';

import 'package:finance_tracker/data/export.dart';
import 'package:finance_tracker/data/import.dart';
import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/store.dart';
import 'package:finance_tracker/screens/export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Rahul and Priya, a ₹1,200 Goa trip dinner in Travel split with Rahul, a
/// ₹200 payment from Rahul toward it, and ₹5,000 of pocket money.
Ledger sample() {
  final dinner = expense(
    billId: 'goa',
    categoryId: 'travel',
    date: DateTime(2026, 10, 2),
  );
  return ledgerWith(
    expenses: [dinner],
    payments: [payment(expenseId: dinner.id)],
  ).put(
    income: Income(
      id: 'i1',
      from: 'Mom',
      amount: 500000,
      date: DateTime(2026, 9, 30),
      note: 'Pocket money',
    ),
  );
}

/// [csv] split into rows of cells, for simple CSV with no quoted commas.
List<List<String>> rows(String csv) => [
  for (final line in csv.substring(1).trimRight().split('\r\n'))
    line.split(','),
];

void main() {
  group('exportCsv', () {
    test('has a header and one row per record, oldest first', () {
      final csv = exportCsv(sample());
      expect(csv, startsWith('\uFEFFDate,Type,Description,'));
      expect(csv, endsWith('\r\n'));
      final lines = csv.substring(1).trimRight().split('\r\n');
      expect(lines, hasLength(4));
      expect(lines[0], csvColumns.join(','));
      expect(lines[1], '2026-09-30,Money in,Pocket money,,,5000.00,Mom,,,No');
      expect(
        lines[2].split(','),
        [
          ...['2026-10-01', 'Received', 'From Rahul for Dinner', ''],
          ...['General', '200.00', 'Rahul', '', 'Rahul', 'No'],
        ],
        reason: 'the payment is dated 1 Oct, before the dinner',
      );
      expect(
        lines[3],
        [
          ...['2026-10-02', 'Expense', 'Dinner', 'Travel', 'Goa trip'],
          ...['1200.00', 'You', '600.00', 'You 600.00; Rahul 600.00', 'Yes'],
        ].join(','),
      );
    });

    test('expenses outside your spending say so', () {
      final ledger =
          ledgerWith(
            expenses: [
              expense(id: 'e1', categoryId: 'rent'),
              expense(
                id: 'e2',
                payerId: 'rahul',
                parts: {'rahul': 1, 'priya': 1},
              ),
            ],
          ).put(
            category: const Category(id: 'rent', name: 'Rent', counted: false),
          );
      final cells = rows(exportCsv(ledger));
      expect(cells[1].last, 'No', reason: 'Rent is left out of spending');
      expect(cells[2][7], '0.00', reason: 'you had no share');
      expect(cells[2].last, 'No');
    });

    test('quotes commas and quotes, and defuses formulas', () {
      final ledger = ledgerWith(
        expenses: [
          expense(id: 'e1', name: 'Tea, "masala"'),
          expense(id: 'e2', name: '=HYPERLINK("x")'),
        ],
      );
      final csv = exportCsv(ledger);
      expect(csv, contains(',"Tea, ""masala""",'));
      expect(csv, contains(',"\'=HYPERLINK(""x"")",'));
    });

    test('an empty ledger is just the header', () {
      expect(exportCsv(Ledger.empty), '\uFEFF${csvColumns.join(',')}\r\n');
    });
  });

  group('exportJson', () {
    test('imports back into an empty ledger with nothing lost', () {
      final ledger = sample();
      final back = previewImport(Ledger.empty, exportJson(ledger)).ledger;
      expect(
        jsonEncode(back.toJson()['expenses']),
        jsonEncode(ledger.toJson()['expenses']),
      );
      expect(back.payments.single.settles, {'e1': 20000});
      expect(back.incomes.single.note, 'Pocket money');
      expect(back.balance('rahul'), ledger.balance('rahul'));
    });

    test('importing it into the same ledger adds nothing', () {
      final ledger = sample();
      expect(previewImport(ledger, exportJson(ledger)).isEmpty, isTrue);
    });
  });

  test('exportFileName', () {
    expect(
      exportFileName(DateTime(2026, 11, 8), 'csv'),
      'between-2026-11-08.csv',
    );
  });

  group('ExportScreen', () {
    Future<void> open(
      WidgetTester tester,
      Future<bool> Function(String name, String mime, String text) save,
    ) async {
      final store = Store(MemoryStorage(jsonEncode(sample().toJson())));
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(store: store, save: save),
        ),
      );
    }

    testWidgets('saves a CSV and says so', (tester) async {
      final saved = <(String, String, String)>[];
      await open(tester, (name, mime, text) async {
        saved.add((name, mime, text));
        return true;
      });
      await tester.tap(find.text('Spreadsheet (CSV)'));
      await tester.pumpAndSettle();
      final (name, mime, text) = saved.single;
      expect(name, matches(RegExp(r'^between-\d{4}-\d\d-\d\d\.csv$')));
      expect(mime, 'text/csv');
      expect(text, contains('Dinner'));
      expect(find.text('Saved $name'), findsOneWidget);
    });

    testWidgets('saves JSON that imports back', (tester) async {
      String? json;
      await open(tester, (name, mime, text) async {
        expect(mime, 'application/json');
        json = text;
        return true;
      });
      await tester.tap(find.text('Between file (JSON)'));
      await tester.pumpAndSettle();
      expect(previewImport(Ledger.empty, json!).expenses, 1);
    });

    testWidgets('says nothing when the picker is cancelled', (tester) async {
      await open(tester, (name, mime, text) async => false);
      await tester.tap(find.text('Spreadsheet (CSV)'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('says when the file can’t be saved', (tester) async {
      await open(tester, (name, mime, text) async => throw Exception('disk'));
      await tester.tap(find.text('Spreadsheet (CSV)'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t save the file.'), findsOneWidget);
    });
  });
}
