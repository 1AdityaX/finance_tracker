import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/flows/flows.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Answers an expense flow: Dinner, ₹1,200, with Rahul, paid by you.
ExpenseFlow dinner(Ledger ledger) => ExpenseFlow(ledger)
  ..name.text = 'Dinner'
  ..amount.paise = 120000
  ..people.selected.add('rahul');

/// The review line that says who owes whom.
Line owesLine(CommandFlow flow) =>
    flow.review.expand((s) => s).singleWhere((l) => l.sign != 0);

void main() {
  group('ExpenseFlow', () {
    test('asks in the owner’s order with sensible defaults', () {
      final flow = ExpenseFlow(ledgerWith());
      expect(flow.asks, [
        flow.name,
        flow.category,
        flow.bill,
        flow.amount,
        flow.quantity,
        flow.people,
      ]);
      expect(flow.category.selected, '', reason: 'no category');
      expect(flow.bill.selected, generalBill);
      expect(flow.quantity.count, 1);
      expect(flow.name.problem, isNotNull);
      expect(flow.amount.problem, isNotNull);
      expect(flow.people.problem, isNull, reason: 'it can be just yours');
      expect(flow.people.phrase, 'just you');

      // Sharing it brings in who paid and how to split it.
      flow.people.selected.add('rahul');
      expect(flow.asks.skip(6), [flow.payer, flow.split]);
      expect(flow.payer.selected, me);
      expect(flow.split.mode, SplitMode.equal);
    });

    test('an expense that was just yours is all your spending', () {
      final flow = ExpenseFlow(ledgerWith())
        ..name.text = 'Coffee'
        ..amount.paise = 15000;
      expect(flow.asks.map((a) => a.problem), everyElement(isNull));
      final saved = flow.save().expenses.single;
      expect(saved.parts, {me: 1});
      expect(saved.payerId, me);
      expect(saved.personal, isTrue);
      expect(saved.categoryId, isNull);
      // Nothing to split, so the review only adds up the month.
      final lines = flow.review.expand((s) => s).toList();
      expect(lines.single.label, startsWith('Spent in '));
      expect(lines.single.value, '₹150');
    });

    test('a friend who paid is dropped with the friends', () {
      final flow = dinner(ledgerWith())..payer.selected = 'rahul';
      flow.people.selected.clear();
      expect(flow.save().expenses.single.payerId, me);
    });

    test('categories typed in are created only when saved and used', () {
      final flow = dinner(ledgerWith());
      flow.category.creator!.create('Unused');
      flow.category.selected = flow.category.creator!.create('Food');
      expect(flow.category.phrase, 'Food');
      final saved = flow.save();
      expect(saved.categories.map((c) => c.name), ['Travel', 'Rent', 'Food']);
      expect(saved.expenses.single.categoryId, saved.categories.last.id);
    });

    test('lists recently used categories first, then by name', () {
      final ledger = ledgerWith(expenses: [expense(categoryId: 'travel')]).put(
        category: const Category(id: 'food', name: 'food'),
      );
      final flow = ExpenseFlow(ledger);
      expect(flow.category.choices().map((c) => c.label), [
        'Travel',
        'food',
        'Rent',
        'No category',
      ]);
    });

    test('the date can be moved and is saved', () {
      final flow = dinner(ledgerWith())..date = DateTime(2026, 9, 3, 20);
      expect(flow.save().expenses.single.date, DateTime(2026, 9, 3, 20));
      expect(flow.review.last.single.label, 'Spent in September');
    });

    test('saves an equal split and says who owes what', () {
      final flow = dinner(ledgerWith());
      expect(flow.asks.map((a) => a.problem), everyElement(isNull));
      final saved = flow.save();
      expect(saved.expenses.single.shares, {me: 60000, 'rahul': 60000});
      expect(saved.balance('rahul'), 60000);
      expect(flow.savedMessage, '“Dinner” added');
      final owes = flow.review.expand((s) => s).firstWhere((l) => l.sign != 0);
      expect(owes.label, 'Rahul owes you');
      expect(owes.value, '₹600');
    });

    test('offers splitting by quantity only when there is more than one', () {
      final flow = dinner(ledgerWith());
      expect(flow.split.modes, isNot(contains(SplitMode.quantity)));
      flow.quantity.count = 4;
      expect(flow.split.modes, contains(SplitMode.quantity));
      expect(flow.split.mode, SplitMode.quantity, reason: 'the default');
      flow.split.values[SplitMode.quantity]!['rahul'] = 3;
      flow.quantity.count = 1;
      expect(
        flow.split.problem,
        startsWith('Splitting by quantity needs more than one unit.'),
        reason: 'a changed quantity must not quietly change the split',
      );
      flow.split.mode = SplitMode.equal;
      expect(flow.split.problem, isNull);
    });

    test('the equal-split chip counts only people still in it', () {
      final flow = dinner(ledgerWith())
        ..people.selected.add('priya')
        ..split.excluded.add('priya');
      expect(flow.split.phrase, 'split equally by 2');
      flow.people.selected.remove('priya');
      expect(flow.split.phrase, 'split equally');
    });

    test('the review says what you owe a payer who sat out', () {
      final flow = dinner(ledgerWith())
        ..payer.selected = 'rahul'
        ..split.excluded.add('rahul');
      final owes = owesLine(flow);
      expect(owes.label, 'You owe Rahul');
      expect(owes.value, '₹1,200');
    });

    test('gives the one person left blank whatever remains', () {
      final flow = dinner(ledgerWith())
        ..quantity.count = 4
        ..split.mode = SplitMode.quantity
        ..split.values[SplitMode.quantity]!['rahul'] = 3;
      expect(flow.split.filler, me);
      expect(flow.split.parts, {me: 1, 'rahul': 3});
      expect(flow.save().balance('rahul'), 90000);
    });

    test('explains a split that does not add up', () {
      final flow = dinner(ledgerWith())..split.mode = SplitMode.exact;
      flow.split.values[SplitMode.exact]!
        ..[me] = 50000
        ..['rahul'] = 50000;
      expect(flow.split.problem, '₹200 still to assign.');
      flow.split.values[SplitMode.exact]!['rahul'] = 90000;
      expect(flow.split.problem, '₹200 more than the total.');
      flow.split.mode = SplitMode.percent;
      flow.split.values[SplitMode.percent]![me] = 2500;
      expect(flow.split.problem, isNull, reason: 'Rahul gets the other 75%');
      flow.split.mode = SplitMode.exact;
      expect(
        flow.split.values[SplitMode.exact]!['rahul'],
        90000,
        reason: 'switching modes keeps typed values',
      );
    });

    test('lets you leave yourself out of an equal split', () {
      final flow = dinner(ledgerWith())..split.excluded.add(me);
      expect(flow.save().balance('rahul'), 120000);
      flow.split.excluded.add('rahul');
      expect(flow.split.problem, 'Include at least one person.');
    });

    test('only offers payers who are in the expense', () {
      final flow = dinner(ledgerWith())..payer.selected = 'rahul';
      expect(flow.payer.problem, isNull);
      flow.people.selected.remove('rahul');
      expect(flow.payer.problem, isNotNull);
    });

    test('creates new friends and bills only when saved and used', () {
      final flow = ExpenseFlow(ledgerWith())
        ..name.text = 'Taxi'
        ..amount.paise = 50000;
      flow.bill.selected = flow.bill.creator!.create('Mumbai');
      flow.people.selected.add(flow.people.creator!.create('Asha'));
      flow.people.creator!.create('Unused');
      final saved = flow.save();
      expect(saved.bills.map((b) => b.name), contains('Mumbai'));
      expect(saved.friends.map((f) => f.name), ['Rahul', 'Priya', 'Asha']);
      expect(saved.expenses.single.billId, isNot(generalBill));
    });

    test('a bill preset skips the bill question', () {
      final flow = ExpenseFlow(ledgerWith(), billId: 'goa');
      expect(flow.bill.selected, 'goa');
      expect(flow.preset, {flow.bill});
    });

    test('editing starts from the saved answers and replaces the record', () {
      final original = expense(
        quantity: 3,
        split: SplitMode.quantity,
        parts: {me: 1, 'rahul': 2},
        payerId: 'rahul',
      );
      final flow = ExpenseFlow(
        ledgerWith(expenses: [original]),
        existing: original,
      );
      expect(flow.editing, isTrue);
      expect(flow.people.selected, ['rahul']);
      expect(flow.split.parts, {me: 1, 'rahul': 2});
      flow.amount.paise = 90000;
      final saved = flow.save();
      expect(saved.expenses.single.id, original.id);
      expect(saved.balance('rahul'), -30000);
      expect(flow.delete()!.ledger.expenses, isEmpty);
    });

    test('editing shows what was paid toward the expense', () {
      final original = expense();
      final paid = payment(amount: 20000, expenseId: 'e1');
      final flow = ExpenseFlow(
        ledgerWith(expenses: [original], payments: [paid]),
        existing: original,
      );
      expect(owesLine(flow).detail, startsWith('₹200 paid so far'));
      final wrongWay = payment(
        direction: Direction.sent,
        amount: 90000,
        expenseId: 'e1',
      );
      final other = ExpenseFlow(
        ledgerWith(expenses: [original], payments: [wrongWay]),
        existing: original,
      );
      expect(owesLine(other).detail, startsWith('Overall'));
    });

    test('editing keeps a payer who sat out an equal split', () {
      final original = expense(payerId: 'rahul', parts: {me: 1, 'priya': 1});
      final flow = ExpenseFlow(
        ledgerWith(expenses: [original]),
        existing: original,
      );
      expect(flow.people.selected, unorderedEquals(['rahul', 'priya']));
      expect(flow.split.excluded, {'rahul'});
      expect(flow.asks.map((a) => a.problem), everyElement(isNull));
    });
  });

  group('PaymentFlow', () {
    test('received money lowers what the friend owes', () {
      final ledger = ledgerWith(expenses: [expense()]);
      final flow = PaymentFlow(ledger, Direction.received)
        ..amount.paise = 60000
        ..friend.selected = 'rahul';
      expect(flow.asks, contains(flow.expense));
      flow.expense.selected = 'e1';
      final saved = flow.save();
      expect(saved.balance('rahul'), 0);
      expect(saved.payments.single.expenseId, 'e1');
      expect(flow.review.expand((s) => s).map((l) => l.value), [
        'Rahul owes you ₹600',
        'settled up',
      ]);
    });

    test('only lists expenses this payment can settle', () {
      final ledger = ledgerWith(
        expenses: [
          expense(),
          expense(id: 'e2', name: 'Cab', payerId: 'rahul'),
          expense(id: 'e3', name: 'Goa hotel', billId: 'goa'),
        ],
      );
      final received = PaymentFlow(ledger, Direction.received)
        ..friend.selected = 'rahul';
      expect(received.expense.choices().map((c) => c.label), [
        'Dinner',
        'Not for a particular expense',
      ]);
      final sent = PaymentFlow(ledger, Direction.sent)
        ..friend.selected = 'rahul';
      expect(sent.expense.choices().first.label, 'Cab');
      received.bill.selected = 'goa';
      expect(received.expense.choices().first.label, 'Goa hotel');
    });

    test('always asks for the expense, with none picked by default', () {
      final flow = PaymentFlow(ledgerWith(), Direction.sent)
        ..amount.paise = 10000
        ..friend.selected = 'rahul';
      expect(flow.asks, [flow.amount, flow.friend, flow.bill, flow.expense]);
      expect(
        flow.expense.choices().single.label,
        'Not for a particular expense',
      );
      expect(flow.expense.problem, isNull);
      expect(flow.save().payments.single.expenseId, isNull);
      expect(flow.save().balance('rahul'), 10000);
    });

    test('editing an overpaid payment keeps its expense', () {
      final p1 = payment(amount: 60000, expenseId: 'e1');
      final p2 = payment(id: 'p2', amount: 10000, expenseId: 'e1');
      final flow = PaymentFlow(
        ledgerWith(expenses: [expense()], payments: [p1, p2]),
        Direction.received,
        existing: p2,
      );
      expect(flow.expense.problem, isNull);
      expect(flow.save().payment('p2')!.expenseId, 'e1');
    });

    test('a friend preset skips the friend question', () {
      final flow = PaymentFlow(ledgerWith(), Direction.sent, friendId: 'rahul');
      expect(flow.preset, {flow.friend});
    });

    test('editing measures balances without the payment itself', () {
      final p = payment(amount: 60000, expenseId: 'e1');
      final flow = PaymentFlow(
        ledgerWith(expenses: [expense()], payments: [p]),
        Direction.received,
        existing: p,
      );
      expect(flow.asks, contains(flow.expense));
      expect(flow.expense.selected, 'e1');
      expect(flow.review.first.first.value, 'Rahul owes you ₹600');
      expect(flow.delete()!.ledger.payments, isEmpty);
    });
  });

  group('BillFlow and FriendFlow', () {
    test('reject names already in use, ignoring case', () {
      final bill = BillFlow(ledgerWith())..name.text = 'goa TRIP';
      expect(bill.name.problem, 'You already have a bill called “goa TRIP”.');
      final friend = FriendFlow(ledgerWith())..name.text = ' rahul ';
      expect(friend.name.problem, isNotNull);
      expect(FriendFlow(ledgerWith(), existing: rahul).name.problem, isNull);
    });

    test('save straight from their only question', () {
      final flow = BillFlow(ledgerWith())..name.text = 'Flat';
      expect(flow.hasReview, isFalse);
      expect(flow.save().bills.last.name, 'Flat');
      final rename = FriendFlow(ledgerWith(), existing: rahul)
        ..name.text = 'Rahul K';
      expect(rename.save().friend('rahul')!.name, 'Rahul K');
    });
  });

  test('names reads naturally', () {
    expect(names(['A']), 'A');
    expect(names(['A', 'B']), 'A and B');
    expect(names(['A', 'B', 'C']), 'A, B and C');
    expect(names(['A', 'B', 'C', 'D']), 'A, B and 2 others');
  });
}
