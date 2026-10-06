import 'dart:convert';

import 'package:finance_tracker/data/import.dart';
import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/store.dart';
import 'package:finance_tracker/screens/import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// An import file with Rahul, a new friend Kavya, a Food category, a Goa
/// trip bill and the given records.
String file({
  List<Expense>? expenses,
  List<Payment> payments = const [],
  List<Income> incomes = const [],
}) => jsonEncode(
  Ledger(
    friends: const [
      Friend(id: 'f-rahul', name: 'rahul '),
      Friend(id: 'kavya', name: 'Kavya'),
    ],
    bills: [
      ...Ledger.empty.bills,
      Bill(id: 'trip', name: 'Goa Trip', created: day),
    ],
    categories: const [
      Category(id: 'food', name: 'Food'),
      Category(id: 'c-rent', name: 'RENT'),
    ],
    expenses:
        expenses ??
        [
          expense(
            id: 'x1',
            billId: 'trip',
            split: SplitMode.exact,
            amount: 90000,
            parts: {me: 30000, 'f-rahul': 30000, 'kavya': 30000},
            categoryId: 'food',
          ),
        ],
    payments: payments,
    incomes: incomes,
  ).toJson(),
);

void main() {
  group('previewImport', () {
    test('adds records, matching friends, categories and bills by name', () {
      final preview = previewImport(
        ledgerWith(expenses: [expense()]),
        file(
          payments: [
            payment(
              id: 'y1',
              friendId: 'kavya',
              billId: 'trip',
              amount: 30000,
            ).withSettles({'x1': 30000}),
          ],
          incomes: [Income(id: 'i1', from: 'Mom', amount: 500000, date: day)],
        ),
      );
      expect((preview.expenses, preview.payments, preview.incomes), (1, 1, 1));
      expect(preview.newFriends, ['Kavya']);
      expect(preview.newCategories, ['Food']);
      expect(preview.newBills, isEmpty, reason: 'Goa trip already exists');

      final ledger = preview.ledger;
      expect(ledger.friends.map((f) => f.name), ['Rahul', 'Priya', 'Kavya']);
      final added = ledger.expense('x1')!;
      expect(added.billId, 'goa');
      expect(added.parts.keys, {me, 'rahul', 'kavya'});
      expect(ledger.category(added.categoryId)!.name, 'Food');
      expect(ledger.balance('rahul'), 60000 + 30000);
      expect(ledger.balance('kavya'), 0);
      expect(ledger.expenses.first.name, 'Dinner', reason: 'kept as it was');
    });

    test('importing the same file twice adds nothing', () {
      final once = previewImport(ledgerWith(), file()).ledger;
      final twice = previewImport(once, file());
      expect(twice.isEmpty, isTrue);
      expect(twice.skipped, 1);
      expect(twice.newFriends, isEmpty);
      expect(twice.ledger.expenses, hasLength(1));
    });

    test('keeps a new record’s id unless it is taken', () {
      final ledger = previewImport(
        Ledger.empty.put(
          friend: const Friend(id: 'kavya', name: 'Asha'),
        ),
        file(),
      ).ledger;
      final kavya = ledger.friends.singleWhere((f) => f.name == 'Kavya');
      expect(kavya.id, isNot('kavya'));
      expect(ledger.expense('x1')!.parts.keys, contains(kavya.id));
    });

    test('a category left out of spending stays left out', () {
      final ledger = previewImport(
        Ledger.empty,
        jsonEncode(
          Ledger.empty
              .put(
                category: const Category(
                  id: 'college',
                  name: 'College',
                  counted: false,
                ),
              )
              .toJson(),
        ),
      ).ledger;
      expect(ledger.categories.single.counted, isFalse);
    });

    test('refuses a file that isn’t a ledger', () {
      expect(
        () => previewImport(Ledger.empty, 'not json'),
        throwsA(isA<ImportError>()),
      );
      expect(
        () => previewImport(Ledger.empty, '{"version": 99}'),
        throwsA(isA<ImportError>()),
      );
    });

    test('refuses records that don’t add up, saying which', () {
      String? problem(String source) {
        try {
          previewImport(Ledger.empty, source);
          return null;
        } on ImportError catch (error) {
          return error.message;
        }
      }

      expect(
        problem(
          file(
            expenses: [
              expense(
                id: 'x1',
                split: SplitMode.exact,
                amount: 90000,
                parts: {me: 30000, 'kavya': 30000},
              ),
            ],
          ),
        ),
        'The expense “Dinner” has parts that don’t add up to its amount.',
      );
      expect(
        problem(
          file(
            expenses: [
              expense(id: 'x1', parts: {'nobody': 1}),
            ],
          ),
        ),
        'The expense “Dinner” is split with someone unknown.',
      );
      expect(
        problem(
          file(
            payments: [payment(friendId: 'kavya', expenseId: 'missing')],
          ),
        ),
        contains('pays toward an expense that isn’t in the file'),
      );
      expect(
        problem(
          file(
            payments: [
              payment(friendId: 'kavya', amount: 100).withSettles({'x1': 200}),
            ],
          ),
        ),
        contains('puts more toward expenses than it is for'),
      );
    });
  });

  group('ImportScreen', () {
    Future<Store> open(
      WidgetTester tester,
      Future<String?> Function() pick,
    ) async {
      final store = Store(MemoryStorage(jsonEncode(ledgerWith().toJson())));
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImportScreen(store: store, pick: pick),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('shows what a file adds, then adds it with undo', (
      tester,
    ) async {
      final store = await open(tester, () async => file());
      expect(store.ledger.expenses, isEmpty);

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(find.text('1 expense'), findsOneWidget);
      expect(find.text('New friends (1)'), findsOneWidget);
      expect(find.text('Kavya'), findsOneWidget);
      expect(store.ledger.expenses, isEmpty, reason: 'nothing saved yet');

      await tester.tap(find.text('Add to my records'));
      await tester.pumpAndSettle();
      expect(store.ledger.expenses.single.id, 'x1');
      expect(find.text('Imported 1 expense'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.ledger.expenses, isEmpty);
    });

    testWidgets('says why a file can’t be imported', (tester) async {
      final store = await open(tester, () async => '{}');
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(find.text('This file isn’t a Between import file.'), findsOne);
      expect(find.text('Add to my records'), findsNothing);
      expect(store.ledger.expenses, isEmpty);
    });

    testWidgets('a file already imported has nothing new', (tester) async {
      final store = await open(tester, () async => file());
      await store.save(previewImport(store.ledger, file()).ledger, 'import');
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing new'), findsOneWidget);
      expect(find.text('Add to my records'), findsNothing);
    });
  });
}

extension on Payment {
  Payment withSettles(Map<String, int> settles) => Payment(
    id: id,
    friendId: friendId,
    direction: direction,
    amount: amount,
    billId: billId,
    settles: settles,
    date: date,
  );
}
