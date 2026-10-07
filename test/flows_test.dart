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

    test('splits by item: each thing shared only by the people in it', () {
      // Snacks for ₹235, paid by you: a ₹80 omelette you and Rahul shared,
      // Rahul's ₹35 popcorn, Priya's ₹20 tea, and ₹100 of juice for you and
      // Priya.
      final flow = ExpenseFlow(ledgerWith())
        ..name.text = 'Snacks'
        ..amount.paise = 23500
        ..people.selected.addAll(['rahul', 'priya'])
        ..split.mode = SplitMode.items;
      final split = flow.split;
      expect(split.problem, 'Add what was bought to continue.');
      split.addItem()
        ..name = 'Omelette'
        ..paise = 8000
        ..people.addAll([me, 'rahul']);
      split.addItem()
        ..name = 'Popcorn'
        ..paise = 3500;
      expect(split.problem, 'Pick who shared “Popcorn”.');
      split.items.last.people.add('rahul');
      expect(split.problem, '₹120 still to assign.');
      split.addItem()
        ..paise = 2000
        ..people.add('priya');
      split.addItem()
        ..name = 'Juice'
        ..paise = 10000
        ..people.addAll(['priya', me]);
      expect(split.problem, isNull);
      expect(split.phrase, 'split by 4 items');

      final saved = flow.save().expenses.single;
      expect(saved.split, SplitMode.items);
      expect(saved.shares, {me: 9000, 'rahul': 7500, 'priya': 7000});
      expect(saved.items.map((i) => i.name), [
        'Omelette',
        'Popcorn',
        'Item 3',
        'Juice',
      ]);
      expect(saved.items.last.people, [me, 'priya'], reason: 'you first');

      final lines = flow.review.expand((s) => s).toList();
      expect(lines.map((l) => (l.label, l.value, l.detail)).take(4), [
        ('Omelette', '₹80', 'You, Rahul'),
        ('Popcorn', '₹35', 'Rahul'),
        ('Item 3', '₹20', 'Priya'),
        ('Juice', '₹100', 'You, Priya'),
      ]);
      expect(
        lines.singleWhere((l) => l.label == 'Rahul').detail,
        'Omelette, Popcorn',
      );

      // Editing it brings the items back as they were.
      final edit = ExpenseFlow(flow.save(), existing: saved);
      expect(edit.split.mode, SplitMode.items);
      expect(edit.split.items.map((i) => i.paise), [8000, 3500, 2000, 10000]);
      expect(edit.split.problem, isNull);
    });

    test('items stop counting someone who leaves the expense', () {
      final flow = dinner(ledgerWith())
        ..people.selected.add('priya')
        ..split.mode = SplitMode.items;
      flow.split.addItem()
        ..paise = 120000
        ..people.addAll(['rahul', 'priya']);
      flow.people.selected.remove('priya');
      expect(flow.save().expenses.single.shares, {me: 0, 'rahul': 120000});
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
      expect(flow.asks, contains(flow.settle));
      flow.settle.selected.add('e1');
      final saved = flow.save();
      expect(saved.balance('rahul'), 0);
      expect(saved.payments.single.settles, {'e1': 60000});
      expect(flow.review.expand((s) => s).map((l) => l.value), [
        '₹600',
        'Rahul owes you ₹600',
        'settled up',
      ]);
      expect(flow.review.first.single.detail, 'Paid in full');
    });

    /// Rahul owes ₹15 for a lollipop and ₹17.50 for nachos.
    Ledger snacks() => ledgerWith(
      expenses: [
        expense(id: 'lolly', name: 'Lollipop', amount: 3000),
        expense(id: 'nachos', name: 'Nachos', amount: 3500),
      ],
    );

    test('one payment pays off several expenses, in the order ticked', () {
      final flow = PaymentFlow(snacks(), Direction.received)
        ..amount.paise = 3100
        ..friend.selected = 'rahul';
      flow.settle.selected.addAll(['lolly', 'nachos']);
      expect(flow.settle.settles, {'lolly': 1500, 'nachos': 1600});
      expect(flow.settle.phrase, 'for Lollipop and Nachos');
      expect(flow.settle.problem, isNull);
      expect(flow.save().balance('rahul'), 150);
      expect(flow.save().expenseBalances('rahul'), {'lolly': 0, 'nachos': 150});
      expect(flow.review.first.map((l) => (l.label, l.value, l.detail)), [
        ('Lollipop', '₹15', 'Paid in full'),
        ('Nachos', '₹16', '₹1.50 still open'),
      ]);

      flow.settle.selected
        ..clear()
        ..addAll(['nachos', 'lolly']);
      expect(flow.settle.settles, {'nachos': 1750, 'lolly': 1350});
    });

    test('what the expenses don’t take goes toward the balance', () {
      final flow = PaymentFlow(snacks(), Direction.received)
        ..amount.paise = 4000
        ..friend.selected = 'rahul';
      flow.settle.selected.addAll(['lolly', 'nachos']);
      expect(flow.settle.leftOver, 750);
      expect(flow.save().payments.single.unassigned, 750);
      expect(flow.review.first.last.label, 'Toward the overall balance');
      expect(flow.save().balance('rahul'), -750);
    });

    test('editing keeps a payment’s split even after its expenses change', () {
      // Paid ₹31 as ₹15 + ₹16; then the lollipop turns out to be ₹80.
      final paid = payment(
        amount: 3100,
        settles: {'lolly': 1500, 'nachos': 1600},
      );
      final ledger = snacks()
          .put(
            expense: expense(id: 'lolly', name: 'Lollipop', amount: 8000),
          )
          .put(payment: paid);
      final flow = PaymentFlow(ledger, Direction.received, existing: paid);
      expect(flow.settle.settles, paid.settles);
      expect(flow.settle.problem, isNull);
      expect(flow.save().payment('p1')!.settles, paid.settles);

      // A new amount splits it again, by what is open now.
      flow.amount.paise = 3000;
      expect(flow.settle.settles, {'lolly': 3000, 'nachos': 0});
      expect(flow.settle.problem, startsWith('₹30 is used up before Nachos'));
    });

    test('an old payment wholly on one expense can be split again', () {
      // Saved before payments could pay toward several expenses.
      final old = payment(amount: 3100, expenseId: 'lolly');
      final flow = PaymentFlow(
        snacks().put(payment: old),
        Direction.received,
        existing: old,
      );
      expect(flow.settle.settles, {'lolly': 3100});
      flow.settle.selected.add('nachos');
      expect(flow.settle.settles, {'lolly': 1500, 'nachos': 1600});
      expect(flow.settle.problem, isNull);
    });

    test('a new friend or bill asks for the expenses again', () {
      final flow = PaymentFlow(snacks(), Direction.received)
        ..amount.paise = 3100
        ..friend.selected = 'rahul';
      flow.settle.selected.addAll(['lolly', 'nachos']);
      flow.settle.accept();
      expect(flow.settle.stale, isFalse);
      flow.bill.selected = 'goa';
      expect(flow.settle.stale, isTrue);
      flow.settle.accept();
      expect(flow.settle.settles, isEmpty, reason: 'none of Goa’s');

      // Back in General, the ticks still hold.
      flow.bill.selected = generalBill;
      expect(flow.settle.stale, isTrue);
      expect(flow.settle.settles, {'lolly': 1500, 'nachos': 1600});
    });

    test('editing for another friend splits by their share', () {
      // Dinner split by amount: Rahul ₹700, Priya ₹300.
      final dinner = expense(
        split: SplitMode.exact,
        parts: {me: 20000, 'rahul': 70000, 'priya': 30000},
      );
      final paid = payment(amount: 70000, expenseId: 'e1');
      final flow = PaymentFlow(
        ledgerWith(expenses: [dinner], payments: [paid]),
        Direction.received,
        existing: paid,
      )..friend.selected = 'priya';
      expect(flow.settle.stale, isTrue);
      expect(flow.settle.settles, {'e1': 30000});
      expect(flow.settle.leftOver, 40000);
      flow.friend.selected = 'rahul';
      expect(flow.settle.settles, {'e1': 70000});
    });

    test('an edit toward the balance notices a new friend after ticks', () {
      final paid = payment(amount: 3100);
      final flow = PaymentFlow(
        snacks().put(payment: paid),
        Direction.received,
        existing: paid,
      );
      flow.settle.selected.add('lolly');
      expect(flow.settle.stale, isFalse);
      flow.friend.selected = 'priya';
      expect(flow.settle.stale, isTrue);
    });

    test('a tick left with another friend doesn’t break the kept split', () {
      final paid = payment(
        amount: 3100,
        settles: {'lolly': 1500, 'nachos': 1600},
      );
      final ledger = snacks()
          .put(
            expense: expense(id: 'lolly', name: 'Lollipop', amount: 8000),
          )
          .put(
            expense: expense(
              id: 'chips',
              name: 'Chips',
              parts: {me: 1, 'priya': 1},
            ),
          )
          .put(payment: paid);
      final flow = PaymentFlow(ledger, Direction.received, existing: paid)
        ..friend.selected = 'priya';
      flow.settle.selected.add('chips');
      flow.friend.selected = 'rahul';
      expect(flow.settle.settles, paid.settles);
      expect(flow.settle.problem, isNull);
    });

    test('with no amount, only the amount question complains', () {
      final flow = PaymentFlow(snacks(), Direction.received)
        ..friend.selected = 'rahul';
      flow.settle.selected.add('lolly');
      expect(flow.settle.problem, isNull);
      flow.amount.paise = 100;
      expect(flow.settle.problem, isNull);
    });

    test('editing a payment for another friend drops its expenses', () {
      final paid = payment(
        amount: 3100,
        settles: {'lolly': 1500, 'nachos': 1600},
      );
      final flow = PaymentFlow(
        snacks().put(payment: paid),
        Direction.received,
        existing: paid,
      )..friend.selected = 'priya';
      expect(flow.settle.expenses(), isEmpty);
      expect(flow.settle.stale, isTrue);
      expect(flow.settle.settles, isEmpty);
      expect(flow.settle.phrase, 'toward the balance');
    });

    test('an expense the money runs out before is a problem', () {
      final flow = PaymentFlow(snacks(), Direction.received)
        ..amount.paise = 1000
        ..friend.selected = 'rahul';
      flow.settle.selected.addAll(['lolly', 'nachos']);
      expect(
        flow.settle.problem,
        '₹10 is used up before Nachos. Untick it, or tick it before the '
        'others.',
      );
      flow.settle.selected.remove('nachos');
      expect(flow.settle.problem, isNull);
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
      List<String> labels(PaymentFlow flow) => [
        for (final e in flow.settle.expenses()) e.choice.label,
      ];
      expect(labels(received), ['Dinner']);
      final sent = PaymentFlow(ledger, Direction.sent)
        ..friend.selected = 'rahul';
      expect(labels(sent), ['Cab']);
      received.bill.selected = 'goa';
      expect(labels(received), ['Goa hotel']);
    });

    test('always asks for the expense, with none picked by default', () {
      final flow = PaymentFlow(ledgerWith(), Direction.sent)
        ..amount.paise = 10000
        ..friend.selected = 'rahul';
      expect(flow.asks, [flow.amount, flow.friend, flow.bill, flow.settle]);
      expect(flow.settle.expenses(), isEmpty);
      expect(flow.settle.problem, isNull);
      expect(flow.settle.phrase, 'toward the balance');
      expect(flow.save().payments.single.settles, isEmpty);
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
      expect(flow.settle.problem, isNull);
      expect(flow.save().payment('p2')!.settles, {'e1': 10000});
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
      expect(flow.asks, contains(flow.settle));
      expect(flow.settle.selected, ['e1']);
      expect(flow.review.last.first.value, 'Rahul owes you ₹600');
      expect(flow.delete()!.ledger.payments, isEmpty);
    });
  });

  group('IncomeFlow', () {
    test('records money in with an optional note', () {
      final flow = IncomeFlow(ledgerWith())
        ..amount.paise = 500000
        ..from.selected = 'Rahul';
      expect(flow.note.problem, isNull, reason: 'the note is optional');
      expect(flow.note.phrase, 'no note');
      expect(flow.asks.map((a) => a.problem), everyElement(isNull));
      final saved = flow.save();
      expect(saved.incomes.single.from, 'Rahul');
      expect(saved.incomes.single.note, isNull);
      expect(saved.balance('rahul'), 0, reason: 'nobody owes anything');
      expect(flow.savedMessage, '₹5,000 from Rahul recorded');
      expect(flow.review.single.single.value, '₹5,000');
    });

    test('offers past givers first, then friends, then names typed in', () {
      final ledger = ledgerWith().put(
        income: Income(id: 'i1', from: 'Mom', amount: 100, date: day),
      );
      final flow = IncomeFlow(ledger);
      flow.from.selected = flow.from.creator!.create('Dad');
      expect(flow.from.choices().map((c) => c.label), [
        'Mom',
        'Priya',
        'Rahul',
        'Dad',
      ]);
      flow
        ..amount.paise = 10000000
        ..note.text = 'College fees';
      expect(flow.save().incomes.last.note, 'College fees');
    });

    test('editing replaces it, and it can be deleted', () {
      final income = Income(id: 'i1', from: 'Mom', amount: 100, date: day);
      final flow = IncomeFlow(
        ledgerWith().put(income: income),
        existing: income,
      )..amount.paise = 200;
      expect(flow.editing, isTrue);
      expect(flow.save().incomes.single.amount, 200);
      expect(flow.delete()!.ledger.incomes, isEmpty);
      expect(flow.delete()!.message, '₹1 from Mom deleted');
    });
  });

  group('CategoryFlow', () {
    test('asks whether the category counts in spending', () {
      final flow = CategoryFlow(ledgerWith())..name.text = 'Fees';
      expect(flow.asks, [flow.name, flow.counted]);
      expect(flow.counted.selected, 'yes');
      flow.counted.selected = 'no';
      expect(flow.save().categories.last.counted, isFalse);
    });

    test('an expense in an uncounted category says it is left out', () {
      final ledger = ledgerWith().put(
        category: const Category(id: 'fees', name: 'Fees', counted: false),
      );
      final flow = ExpenseFlow(ledger)
        ..name.text = 'Semester fees'
        ..amount.paise = 10000000
        ..category.selected = 'fees';
      final line = flow.review.last.single;
      expect(line.label, 'Not counted in your spending');
      expect(line.detail, 'Fees is left out');
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
