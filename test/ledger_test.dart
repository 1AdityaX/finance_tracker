import 'dart:convert';

import 'package:finance_tracker/data/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('shares', () {
    test('equal, quantity, percent and exact all add up to the amount', () {
      expect(expense(parts: {me: 1, 'rahul': 1, 'priya': 1}).shares, {
        me: 40000,
        'rahul': 40000,
        'priya': 40000,
      });
      expect(
        expense(
          quantity: 4,
          split: SplitMode.quantity,
          parts: {me: 1, 'rahul': 3},
        ).shares,
        {me: 30000, 'rahul': 90000},
      );
      expect(
        expense(
          amount: 10000,
          split: SplitMode.percent,
          parts: {me: 3333, 'rahul': 6667},
        ).shares,
        {me: 3333, 'rahul': 6667},
      );
      expect(
        expense(split: SplitMode.exact, parts: {me: 0, 'rahul': 120000}).shares,
        {me: 0, 'rahul': 120000},
      );
    });
  });

  group('balance', () {
    test('a friend owes their share when you paid', () {
      expect(ledgerWith(expenses: [expense()]).balance('rahul'), 60000);
    });

    test('you owe your share when the friend paid', () {
      final ledger = ledgerWith(expenses: [expense(payerId: 'rahul')]);
      expect(ledger.balance('rahul'), -60000);
    });

    test('expenses between other people do not count', () {
      final ledger = ledgerWith(
        expenses: [
          expense(payerId: 'priya', parts: {'priya': 1, 'rahul': 1}),
        ],
      );
      expect(ledger.balance('rahul'), 0);
      expect(ledger.balance('priya'), 0);
    });

    test('money received lowers what they owe, money sent what you owe', () {
      final ledger = ledgerWith(
        expenses: [
          expense(),
          expense(id: 'e2', payerId: 'rahul', amount: 40000),
        ],
        payments: [
          payment(amount: 20000),
          payment(id: 'p2', direction: Direction.sent, amount: 5000),
        ],
      );
      // 600 owed − 200 their share of e2 − 200 received + 50 sent.
      expect(ledger.balance('rahul'), 60000 - 20000 - 20000 + 5000);
    });

    test('balances() agrees with balance() for everyone', () {
      final ledger = ledgerWith(
        expenses: [
          expense(parts: {me: 1, 'rahul': 1, 'priya': 1}),
          expense(id: 'e2', billId: 'goa', payerId: 'priya', amount: 99999),
          expense(id: 'e3', payerId: 'rahul', parts: {'rahul': 1, 'priya': 1}),
        ],
        payments: [
          payment(),
          payment(id: 'p2', friendId: 'priya', billId: 'goa'),
        ],
      );
      for (final billId in [null, generalBill, 'goa']) {
        final all = ledger.balances(billId: billId);
        for (final id in ['rahul', 'priya']) {
          expect(all[id] ?? 0, ledger.balance(id, billId: billId));
          if (billId != null) {
            expect(
              ledger.billBalances(id)[billId] ?? 0,
              ledger.balance(id, billId: billId),
            );
          }
        }
      }
    });

    test('narrows to one bill or one expense', () {
      final ledger = ledgerWith(
        expenses: [
          expense(),
          expense(id: 'e2', billId: 'goa', amount: 40000),
        ],
        payments: [payment(billId: 'goa', expenseId: 'e2')],
      );
      expect(ledger.balance('rahul', billId: 'goa'), 0);
      expect(ledger.balance('rahul', billId: generalBill), 60000);
      expect(ledger.balance('rahul', expenseId: 'e2'), 0);
      expect(ledger.balance('rahul'), 60000);
    });
  });

  group('changes', () {
    test('put replaces by id or appends', () {
      final ledger = ledgerWith(expenses: [expense()]);
      final renamed = ledger.put(expense: expense(name: 'Lunch'));
      expect(renamed.expenses.single.name, 'Lunch');
      expect(ledger.expenses.single.name, 'Dinner', reason: 'immutable');
      expect(renamed.put(expense: expense(id: 'e2')).expenses, hasLength(2));
    });

    test('payments follow an expense that moves to another bill', () {
      final ledger = ledgerWith(
        expenses: [expense()],
        payments: [
          payment(expenseId: 'e1'),
          payment(id: 'p2'),
        ],
      ).put(expense: expense(billId: 'goa'));
      expect(ledger.payment('p1')!.billId, 'goa');
      expect(ledger.payment('p1')!.expenseId, 'e1');
      expect(ledger.payment('p2')!.billId, generalBill);
      expect(ledger.balance('rahul', billId: 'goa'), 60000 - 20000);
    });

    test('removing an expense keeps its payments in the balance', () {
      final ledger = ledgerWith(
        expenses: [expense()],
        payments: [payment(expenseId: 'e1')],
      ).removeExpense('e1');
      expect(ledger.payments.single.expenseId, isNull);
      expect(ledger.balance('rahul'), -20000);
    });

    test(
      'removing a bill removes its expenses and moves payments to General',
      () {
        final ledger = ledgerWith(
          expenses: [expense(billId: 'goa')],
          payments: [payment(billId: 'goa', expenseId: 'e1')],
        ).removeBill('goa');
        expect(ledger.bill('goa'), isNull);
        expect(ledger.expenses, isEmpty);
        expect(ledger.payments.single.billId, generalBill);
        expect(ledger.payments.single.expenseId, isNull);
      },
    );

    test('involves counts parts, payers and payments', () {
      expect(ledgerWith().involves('rahul'), isFalse);
      expect(ledgerWith(expenses: [expense()]).involves('rahul'), isTrue);
      expect(
        ledgerWith(
          expenses: [
            expense(payerId: 'priya', parts: {me: 1}),
          ],
        ).involves('priya'),
        isTrue,
      );
      expect(ledgerWith(payments: [payment()]).involves('rahul'), isTrue);
    });
  });

  test('lists recent friends first, then the rest by name', () {
    const asha = Friend(id: 'asha', name: 'asha');
    final ledger = Ledger(
      friends: const [rahul, asha, priya],
      bills: Ledger.empty.bills,
      expenses: [
        expense(parts: {me: 1, 'rahul': 1}),
        expense(
          id: 'e2',
          parts: {me: 1, 'priya': 1},
          date: day.add(const Duration(days: 1)),
        ),
      ],
      payments: const [],
    );
    expect(ledger.recentFriends.map((f) => f.id), ['priya', 'rahul', 'asha']);
  });

  test('lists General first, then the newest bills', () {
    final older = Bill(id: 'old', name: 'Old', created: DateTime(2020));
    final ledger = ledgerWith().put(bill: older);
    expect(ledger.billsInOrder.map((b) => b.id), [generalBill, 'goa', 'old']);
  });

  test('round-trips through JSON', () {
    final ledger = ledgerWith(
      expenses: [
        expense(
          split: SplitMode.quantity,
          quantity: 3,
          parts: {me: 1, 'rahul': 2},
        ),
      ],
      payments: [payment(expenseId: 'e1')],
    );
    final copy = Ledger.fromJson(
      (jsonDecode(jsonEncode(ledger.toJson())) as Map).cast<String, Object?>(),
    );
    expect(jsonEncode(copy.toJson()), jsonEncode(ledger.toJson()));
  });
}
