import 'dart:convert';
import 'dart:io';

import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

void main() {
  group('Store', () {
    test('starts empty with only the General bill', () async {
      final store = Store(MemoryStorage());
      await store.load();
      expect(store.loadError, isNull);
      expect(store.ledger.bills.single.id, generalBill);
    });

    test('saves, reloads and undoes', () async {
      final storage = MemoryStorage();
      final store = Store(storage);
      await store.load();
      await store.save(ledgerWith(expenses: [expense()]), '“Dinner” added');
      expect(store.undoLabel, '“Dinner” added');

      final reloaded = Store(storage);
      await reloaded.load();
      expect(reloaded.ledger.expenses.single.name, 'Dinner');

      expect(await store.undo(), '“Dinner” added');
      expect(store.ledger.expenses, isEmpty);
      expect(decodeLedger(storage.json!).expenses, isEmpty);
      expect(await store.undo(), isNull);
    });

    test('a reload forgets undo history from before it', () async {
      final store = Store(MemoryStorage());
      await store.load();
      await store.save(ledgerWith(), 'Added friends');
      await store.load();
      expect(store.undoLabel, isNull);
    });

    test('reports unreadable data and never overwrites it', () async {
      final storage = MemoryStorage('{not json');
      final store = Store(storage);
      await store.load();
      expect(store.loadError, isNotNull);
      expect(storage.json, '{not json');
    });

    test('reads version 2 data, which had no categories', () {
      final json = ledgerWith(expenses: [expense()]).toJson()
        ..['version'] = 2
        ..remove('categories');
      final ledger = decodeLedger(jsonEncode(json));
      expect(ledger.categories, isEmpty);
      expect(ledger.expenses.single.categoryId, isNull);
      expect(ledger.balance('rahul'), 60000);
    });

    test('reads version 3 payments, which went wholly to one expense', () {
      final json = ledgerWith(expenses: [expense()]).toJson()
        ..['version'] = 3
        ..['payments'] = [
          {
            'id': 'p1',
            'friend': 'rahul',
            'direction': 'received',
            'amount': 70000,
            'bill': generalBill,
            'expense': 'e1',
            'date': day.toIso8601String(),
          },
          {
            'id': 'p2',
            'friend': 'rahul',
            'direction': 'received',
            'amount': 100,
            'bill': generalBill,
            'expense': null,
            'date': day.toIso8601String(),
          },
        ];
      final ledger = decodeLedger(jsonEncode(json));
      expect(ledger.payment('p1')!.settles, {'e1': 70000});
      expect(ledger.payment('p2')!.settles, isEmpty);
      expect(ledger.expenseBalances('rahul'), {'e1': -10000});
      expect(ledger.balance('rahul'), -10100);
    });

    test('refuses data from a newer version', () {
      expect(
        () => decodeLedger(jsonEncode({'version': 99})),
        throwsFormatException,
      );
    });
  });

  test('SqliteStorage keeps one row that survives reopening', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('between');
    addTearDown(() => dir.deleteSync(recursive: true));
    SqliteStorage open() => SqliteStorage(
      factory: databaseFactoryFfiNoIsolate,
      path: '${dir.path}/shared_expenses.db',
    );
    final first = open();
    expect(await first.read(), isNull);
    await first.write('{"a":1}');
    await first.write('{"a":2}');
    expect(await open().read(), '{"a":2}');
  });

  test('a failed save changes nothing', () async {
    final store = Store(_FailingStorage());
    await store.load();
    final before = store.ledger;
    await expectLater(
      store.save(ledgerWith(), 'Added friends'),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.ledger, same(before));
    expect(store.undoLabel, isNull);
  });

  group('version 1 data', () {
    // The snapshot format written by the first version of the app.
    final v1 = {
      'people': [
        {'id': 'me', 'name': 'You'},
        {'id': 'r', 'name': 'Rahul'},
        {'id': 'p', 'name': 'Priya'},
      ],
      'purchases': [
        {
          'id': 'lunch',
          'title': 'Lunch',
          'category': 'Other',
          'payerId': 'me',
          'date': '2026-09-01T12:00:00.000',
          'participantIds': ['me', 'r'],
          'items': [
            {
              'id': 'i1',
              'name': 'Lunch',
              'amount': 24000,
              'quantity': 1,
              'assignment': {
                'mode': 'equal',
                'values': {'me': 1, 'r': 1},
                'status': 'confirmed',
              },
            },
          ],
          'note': '',
        },
        {
          'id': 'groceries',
          'title': 'Groceries',
          'category': 'Other',
          'payerId': 'r',
          'date': '2026-09-02T12:00:00.000',
          'participantIds': ['me', 'r', 'p'],
          'items': [
            {
              'id': 'i1',
              'name': 'Rice',
              'amount': 60000,
              'quantity': 3,
              'assignment': {
                'mode': 'quantity',
                'values': {'me': 1, 'r': 2},
                'status': 'confirmed',
              },
            },
            {
              'id': 'i2',
              'name': 'Milk',
              'amount': 10000,
              'quantity': 1,
              'assignment': {
                'mode': 'proportion',
                'values': {'me': 2500, 'p': 7500},
                'status': 'confirmed',
              },
            },
          ],
          'note': '',
        },
        {
          'id': 'snacks',
          'title': 'Snacks',
          'category': 'Other',
          'payerId': 'me',
          'date': '2026-09-02T18:00:00.000',
          'participantIds': ['me', 'r', 'p'],
          'items': [
            {
              'id': 'i1',
              'name': 'Chips',
              'amount': 10000,
              'quantity': 1,
              'assignment': {
                'mode': 'equal',
                'values': {'r': 1, 'p': 1, 'me': 1},
                'status': 'confirmed',
              },
            },
            {
              'id': 'i2',
              'name': 'Juice',
              'amount': 9000,
              'quantity': 1,
              'assignment': {
                'mode': 'equal',
                'values': {'me': 1, 'r': 1},
                'status': 'unresolved',
              },
            },
          ],
          'note': '',
        },
        {
          'id': 'cake',
          'title': 'Cake',
          'category': 'Other',
          'payerId': 'me',
          'date': '2026-09-02T19:00:00.000',
          'participantIds': ['me', 'p'],
          'items': [
            {
              'id': 'i1',
              'name': 'Cake',
              'amount': 50000,
              'quantity': 1,
              'assignment': {
                'mode': 'quantity',
                'values': {'me': 0, 'p': 1},
                'status': 'confirmed',
              },
            },
          ],
          'note': '',
        },
        {
          'id': 'cab',
          'title': 'Cab',
          'category': 'Other',
          'payerId': 'p',
          'date': '2026-09-03T12:00:00.000',
          'participantIds': ['me', 'p'],
          'items': [
            {
              'id': 'i1',
              'name': 'Cab',
              'amount': 30000,
              'quantity': 1,
              'assignment': {
                'mode': 'equal',
                'values': {'me': 1},
                'status': 'confirmed',
              },
            },
          ],
          'note': '',
        },
      ],
      'transfers': [
        {
          'id': 't1',
          'counterpartyId': 'r',
          'direction': 'received',
          'amount': 12000,
          'portions': {'r': 12000},
          'date': '2026-09-04T12:00:00.000',
          'reservedPurchaseId': null,
          'allocations': [
            {'personId': 'r', 'purchaseId': 'lunch', 'amount': 12000},
          ],
          'note': '',
          'needsReview': false,
        },
        {
          'id': 't2',
          'counterpartyId': 'r',
          'direction': 'sent',
          'amount': 50000,
          'portions': {'r': 40000, 'p': 10000},
          'date': '2026-09-05T12:00:00.000',
          'reservedPurchaseId': null,
          'allocations': [
            {'personId': 'r', 'purchaseId': 'groceries', 'amount': 40000},
          ],
          'note': '',
          'needsReview': false,
        },
      ],
    };

    late Ledger ledger;
    setUp(() => ledger = decodeLedger(jsonEncode(v1)));

    test('breaks rounding ties by person id, as version 1 did', () {
      // ₹100 three ways: version 1 gave the extra paisa to "me", the
      // smallest id, even though Rahul was picked first.
      expect(ledger.expense('snacks-i1')!.shares, {
        me: 3334,
        'p': 3333,
        'r': 3333,
      });
    });

    test('turns a split by quantity of one unit into exact amounts', () {
      final cake = ledger.expense('cake')!;
      expect(cake.split, SplitMode.exact);
      expect(cake.shares, {me: 0, 'p': 50000});
    });

    test('keeps items version 1 had not counted, without counting them', () {
      final juice = ledger.expense('snacks-i2')!;
      expect(ledger.bill(juice.billId)!.name, 'Not split yet');
      expect(juice.owedBy('r'), 0);
    });

    test('keeps friends but not the owner', () {
      expect(ledger.friends.map((f) => f.name), ['Rahul', 'Priya']);
    });

    test('turns one-item purchases into General expenses', () {
      final lunch = ledger.expense('lunch')!;
      expect(lunch.billId, generalBill);
      expect(lunch.name, 'Lunch');
      expect(lunch.shares, {me: 12000, 'r': 12000});
    });

    test('turns multi-item purchases into a bill of expenses', () {
      expect(ledger.bill('groceries')!.name, 'Groceries');
      final rice = ledger.expense('groceries-i1')!;
      expect(rice.billId, 'groceries');
      expect(rice.split, SplitMode.quantity);
      expect(rice.payerId, 'r');
      final milk = ledger.expense('groceries-i2')!;
      expect(milk.shares, {me: 2500, 'p': 7500, 'r': 0});
    });

    test('adds a payer missing from the split without changing shares', () {
      final cab = ledger.expense('cab')!;
      expect(cab.split, SplitMode.exact);
      expect(cab.parts, {me: 30000, 'p': 0});
      expect(cab.owedBy('p'), -30000);
    });

    test('splits payments per friend and links what they settled', () {
      expect(ledger.payment('t1')!.settles.keys, ['lunch']);
      final toRahul = ledger.payment('t2-r')!;
      expect(toRahul.amount, 40000);
      expect(toRahul.direction, Direction.sent);
      expect(toRahul.billId, 'groceries');
      expect(toRahul.settles, isEmpty);
      expect(ledger.payment('t2-p')!.billId, generalBill);
    });

    test('keeps every balance the first version showed', () {
      // Rahul: lunch +120, rice −200, milk −25, chips +33.33,
      // received −120, sent +400. The unresolved juice does not count.
      expect(ledger.balance('r'), 12000 - 20000 - 2500 + 3333 - 12000 + 40000);
      // Priya: chips +33.33, cake +500, cab −300, sent +100. Rahul paid
      // for the milk.
      expect(ledger.balance('p'), 3333 + 50000 - 30000 + 10000);
    });
  });
}

class _FailingStorage implements Storage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String json) async =>
      throw const FileSystemException('Disk full');
}
