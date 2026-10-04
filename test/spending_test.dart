import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/spending.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final october = DateTime(2026, 10);

  test('counts your share of each expense in the month', () {
    final ledger = ledgerWith(
      expenses: [
        // Split with Rahul: your half.
        expense(categoryId: 'travel'),
        // Just yours: all of it.
        expense(id: 'e2', amount: 30000, parts: {me: 1}),
        // Rahul paid and you sat out: not yours at all.
        expense(id: 'e3', payerId: 'rahul', parts: {'rahul': 1}),
        // You paid for Rahul alone: what he owes you, not spending.
        expense(id: 'e4', parts: {'rahul': 1}),
        // Last month.
        expense(id: 'e5', date: DateTime(2026, 9, 30)),
      ],
      payments: [payment(amount: 99900)],
    );
    final spending = Spending(ledger, october);
    expect(spending.total, 90000);
    expect(spending.items.map((i) => (i.expense.id, i.share)), [
      ('e1', 60000),
      ('e2', 30000),
    ]);
    expect(Spending(ledger, DateTime(2026, 9, 15)).total, 60000);
  });

  test('groups by category, with no category last', () {
    final ledger = ledgerWith(
      expenses: [
        expense(amount: 900000, parts: {me: 1}),
        expense(id: 'e2', amount: 20000, parts: {me: 1}, categoryId: 'rent'),
        expense(id: 'e3', amount: 50000, parts: {me: 1}, categoryId: 'travel'),
        expense(id: 'e4', amount: 20000, parts: {me: 1}, categoryId: 'travel'),
      ],
    );
    expect(Spending(ledger, october).byCategory, [
      (id: 'travel', amount: 70000),
      (id: 'rent', amount: 20000),
      (id: '', amount: 900000),
    ]);
  });

  test('breaks ties by name, and groups by bill', () {
    final ledger = ledgerWith(
      expenses: [
        expense(parts: {me: 1}, categoryId: 'travel'),
        expense(id: 'e2', parts: {me: 1}, categoryId: 'rent', billId: 'goa'),
      ],
    );
    final spending = Spending(ledger, october);
    expect(spending.byCategory.map((r) => r.id), ['rent', 'travel']);
    expect(spending.byBill.map((r) => r.id), [generalBill, 'goa']);
  });

  test('can stop part way through the month, to compare like for like', () {
    final ledger = ledgerWith(
      expenses: [
        expense(parts: {me: 1}, date: DateTime(2026, 10, 4, 23)),
        expense(id: 'e2', parts: {me: 1}, date: DateTime(2026, 10, 5)),
      ],
    );
    expect(Spending(ledger, october, throughDay: 4).total, 120000);
    expect(Spending(ledger, october, throughDay: 31).total, 240000);
  });

  test('names months', () {
    expect(monthName(october), 'October');
    expect(monthName(DateTime(2026, 1, 31)), 'January');
  });
}
