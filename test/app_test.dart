import 'dart:convert';

import 'package:finance_tracker/cloud/account.dart';
import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/spending.dart';
import 'package:finance_tracker/data/store.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/screens/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<Store> pumpApp(
  WidgetTester tester, [
  Ledger? ledger,
  Account? account,
]) async {
  final store = Store(
    MemoryStorage(ledger == null ? null : jsonEncode(ledger.toJson())),
  );
  await store.load();
  await tester.pumpWidget(BetweenApp(store: store, account: account));
  await tester.pumpAndSettle();
  return store;
}

extension on WidgetTester {
  /// Scrolls the main list until [finder] is built and on screen.
  Future<void> reveal(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
    }
    await ensureVisible(finder.last);
    await pumpAndSettle();
  }

  /// Taps [text], scrolling the main list to it first when needed.
  Future<void> tapText(String text) async {
    await reveal(find.text(text));
    await tap(find.text(text).last);
    await pumpAndSettle();
  }

  Future<void> type(String text) async {
    await enterText(find.byType(TextField).last, text);
    await pumpAndSettle();
  }

  Future<void> next() => tapText('Continue');
}

void main() {
  testWidgets('first run explains the app and starts an expense', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      find.text('Track your spending and split costs, one question at a time.'),
      findsOneWidget,
    );
    await tester.tapText('Add your first expense');
    expect(find.text('What was it for?'), findsOneWidget);
  });

  testWidgets('/expense asks one question at a time and saves', (tester) async {
    final store = await pumpApp(tester);
    await tester.tapText('/expense');

    expect(find.text('What was it for?'), findsOneWidget);
    await tester.next();
    expect(find.text('Type a name to continue.'), findsOneWidget);
    await tester.type('Pizza');
    expect(find.text('Type a name to continue.'), findsNothing);
    await tester.next();

    // Categories are the user's own: typing one offers to add it.
    expect(find.text('Which category is it?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Food');
    await tester.pumpAndSettle();
    await tester.tapText('New category “Food”');

    // The bill is asked even with only General, which Continue accepts;
    // typing a name offers to start a new bill.
    expect(find.text('Which group is it part of?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Goa');
    await tester.pumpAndSettle();
    expect(find.text('New group “Goa”'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.next();

    expect(find.text('How much did it cost?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'in General'), findsOneWidget);
    await tester.type('1200');
    await tester.next();

    expect(find.text('How many units?'), findsOneWidget);
    await tester.tap(find.byTooltip('One more'));
    await tester.tap(find.byTooltip('One more'));
    await tester.tap(find.byTooltip('One more'));
    await tester.pumpAndSettle();
    await tester.next();

    expect(find.text('Who shared it with you?'), findsOneWidget);
    await tester.type('Rahul');
    await tester.tapText('Add “Rahul” as a friend');
    await tester.next();

    expect(find.text('Who paid?'), findsOneWidget);
    await tester.tapText('You'); // Picking moves on by itself.

    // With 4 units the split starts by quantity.
    expect(find.text('How do you want to split it?'), findsOneWidget);
    await tester.tap(find.byTooltip('One more for Rahul'));
    await tester.pumpAndSettle();
    expect(find.text('All 4 units assigned'), findsOneWidget);
    await tester.next();

    expect(find.text('Look right?'), findsOneWidget);
    expect(find.text('Rahul owes you'), findsOneWidget);
    expect(find.text('₹300'), findsWidgets);
    // The answers so far read like a sentence.
    for (final phrase in ['Pizza', 'Food', 'in General', '₹1,200', '4 units']) {
      expect(find.widgetWithText(ActionChip, phrase), findsOneWidget);
    }
    await tester.tapText('Add expense');

    expect(store.ledger.expenses.single.shares.values, [90000, 30000]);
    expect(store.ledger.categories.single.name, 'Food');
    expect(
      store.ledger.expenses.single.categoryId,
      store.ledger.categories.single.id,
    );
    expect(find.text('“Pizza” added'), findsOneWidget);
    expect(find.textContaining('Rahul owes you'), findsWidgets);
  });

  testWidgets('an expense can be split item by item', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Snacks');
    await tester.next();
    await tester.next(); // No category.
    await tester.next(); // General.
    await tester.type('100');
    await tester.next();
    await tester.next(); // 1 unit.
    await tester.tapText('Rahul');
    await tester.next();
    await tester.tapText('You');

    await tester.tapText('By item');
    await tester.reveal(find.text('“Item 1” needs an amount.'));
    expect(find.text('“Item 1” needs an amount.'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(Card),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Omelette');
    await tester.enterText(fields.at(1), '80');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'You').first);
    await tester.tap(find.widgetWithText(FilterChip, 'Rahul').first);
    await tester.pumpAndSettle();
    expect(find.text('₹40 each'), findsOneWidget);
    await tester.reveal(find.text('₹20 still to assign.'));
    expect(find.text('₹20 still to assign.'), findsOneWidget);

    await tester.tapText('Add item');
    await tester.enterText(fields.at(2), 'Tea');
    await tester.enterText(fields.at(3), '20');
    await tester.pumpAndSettle();
    final rahul = find.widgetWithText(FilterChip, 'Rahul').last;
    await tester.ensureVisible(rahul);
    await tester.pumpAndSettle();
    await tester.tap(rahul);
    await tester.pumpAndSettle();
    await tester.reveal(find.text('All ₹100 assigned'));
    expect(find.text('All ₹100 assigned'), findsOneWidget);
    await tester.next();

    expect(find.text('Omelette, Tea'), findsOneWidget);
    expect(find.text('Rahul owes you'), findsOneWidget);
    await tester.tapText('Add expense');
    final saved = store.ledger.expenses.single;
    expect(saved.shares, {me: 4000, 'rahul': 6000});
    expect(saved.items.map((i) => i.name), ['Omelette', 'Tea']);
  });

  testWidgets('back returns to the previous question with answers kept', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next();
    await tester.next();
    await tester.type('500');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Which group is it part of?'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Which category is it?'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsWidgets);

    // The system back gesture does the same.
    await tester.next();
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('What was it for?'), findsOneWidget);
  });

  testWidgets('tapping an answer revises it and returns to the review', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    await tester.type('900');
    await tester.next();
    await tester.next();
    await tester.tapText('Rahul');
    await tester.next();
    await tester.tapText('You');
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, '₹900'));
    await tester.pumpAndSettle();
    await tester.type('1500');
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);
    expect(find.text('₹750'), findsWidgets);
    await tester.tapText('Add expense');
    expect(store.ledger.balance('rahul'), 75000);
  });

  /// Answers /expense up to its review: Pizza, ₹900, with Rahul, you paid.
  Future<void> toReview(WidgetTester tester) async {
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    await tester.type('900');
    await tester.next();
    await tester.next();
    await tester.tapText('Rahul');
    await tester.next();
    await tester.tapText('You');
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);
  }

  testWidgets('back never shows a review that no longer adds up', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await toReview(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'split equally'));
    await tester.pumpAndSettle();
    await tester.tapText('By amount');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('How do you want to split it?'), findsOneWidget);
  });

  testWidgets('back from a revised split returns to the review', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await toReview(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'split equally'));
    await tester.pumpAndSettle();
    await tester.tapText('By amount');
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Look right?'), findsOneWidget);
    expect(find.text('₹700'), findsWidgets);
  });

  testWidgets('re-picking the same answer is not an edit', (tester) async {
    await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Dinner');
    await tester.tap(find.widgetWithText(ActionChip, 'in General'));
    await tester.pumpAndSettle();
    await tester.tapText('General');
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('changing an answer from the review returns to it once', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await toReview(tester);
    await tester.tap(find.widgetWithText(ActionChip, '₹900'));
    await tester.pumpAndSettle();
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to split it?'), findsOneWidget);
  });

  testWidgets('someone added after an exact split is asked about', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await toReview(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'split equally'));
    await tester.pumpAndSettle();
    await tester.tapText('By amount');
    await tester.enterText(find.byType(TextField).first, '900');
    await tester.pumpAndSettle();
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'with Rahul'));
    await tester.pumpAndSettle();
    await tester.tapText('Priya');
    await tester.next();
    expect(find.text('How do you want to split it?'), findsOneWidget);
  });

  testWidgets('a quick second Enter does not skip the next question', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    await tester.enterText(find.byType(TextField), '900');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('How many units?'), findsOneWidget);
  });

  testWidgets('an edit left with Back is still saved', (tester) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Dinner');
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Dinner'));
    await tester.pumpAndSettle();
    await tester.type('Lunch');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tapText('Save changes');
    expect(store.ledger.expenses.single.name, 'Lunch');
  });

  testWidgets('the step count leaves out questions already answered', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tapText('/expense');
    // Who paid and how to split only come in once friends share it.
    expect(find.text('1 of 6'), findsOneWidget);
  });

  testWidgets('closing asks only when answers would be lost', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsOneWidget, reason: 'nothing to lose');

    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tapText('Keep editing');
    expect(find.text('Which category is it?'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tapText('Discard');
    expect(store.ledger.expenses, isEmpty);
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('a bill made first shows on home', (tester) async {
    await pumpApp(tester);
    await tester.tapText('/group');
    await tester.type('Goa trip');
    await tester.tapText('Create group');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Goa trip'), findsOneWidget);
  });

  testWidgets('a friend’s activity shows what is settled', (tester) async {
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(),
          expense(id: 'e2', name: 'Cab', amount: 40000),
        ],
        payments: [
          payment(amount: 60000, expenseId: 'e1'),
          payment(id: 'p2', amount: 5000, expenseId: 'e2'),
        ],
      ),
    );
    await tester.tapText('Rahul');
    expect(find.textContaining('settled'), findsWidgets);
    expect(find.textContaining('₹150 left'), findsOneWidget);
  });

  testWidgets('a friend page lists what is still open, and when', (
    tester,
  ) async {
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(),
          expense(id: 'e2', name: 'Cab', amount: 40000),
          expense(id: 'e3', name: 'Lunch', amount: 30000, payerId: 'rahul'),
        ],
        payments: [
          payment(amount: 60000, expenseId: 'e1'),
          payment(id: 'p2', amount: 5000, expenseId: 'e2'),
          payment(id: 'p3', amount: 1000),
        ],
      ),
    );
    await tester.tapText('Rahul');
    expect(find.text('Still open'), findsOneWidget);
    // Dinner is settled, so only the Cab, the Lunch Rahul paid for, and the
    // payment not linked to anything are listed.
    expect(find.textContaining('₹50 of ₹200 paid'), findsOneWidget);
    expect(find.textContaining('you owe'), findsOneWidget);
    expect(find.text('Not linked to an expense'), findsOneWidget);
    expect(find.textContaining('of ₹600 paid'), findsNothing);
  });

  testWidgets('the keyboard stays with the next typed answer', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next(); // No category.
    // Search the bill list, pick from the keyboard, land on the amount.
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'goa');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('How much did it cost?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'in Goa trip'), findsOneWidget);
    final amount = tester.widget<TextField>(find.byType(TextField));
    expect(amount.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('/bill opens the new bill, ready for its first expense', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/group');
    await tester.type('Flat');
    await tester.tapText('Create group');
    expect(find.text('No expenses yet.'), findsOneWidget);
    await tester.tapText('Add expense');
    await tester.type('Rent');
    await tester.next();
    expect(find.widgetWithText(ActionChip, 'in Flat'), findsOneWidget);
  });

  testWidgets('/receive links the payment to an expense', (tester) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('/receive');
    expect(find.text('How much did you receive?'), findsOneWidget);
    await tester.type('600');
    await tester.next();
    expect(find.text('owes you ₹600'), findsWidgets);
    await tester.tapText('Rahul');
    await tester.tapText('General');
    expect(find.text('Which expenses is it for?'), findsOneWidget);
    expect(find.text('All ₹600 goes toward the overall balance.'), findsOne);
    await tester.tapText('Dinner'); // Ticking stays on the page.
    expect(find.text('₹600, paid in full'), findsOneWidget);
    expect(find.text('All ₹600 goes to these expenses.'), findsOneWidget);
    await tester.next();
    expect(find.text('Paid in full'), findsOneWidget);
    expect(find.text('settled up'), findsWidgets);
    await tester.tapText('Record ₹600 received');
    expect(store.ledger.payments.single.settles, {'e1': 60000});
    expect(store.ledger.balance('rahul'), 0);
    expect(find.text('You’re all settled up.'), findsOneWidget);
  });

  testWidgets('a save builds on the latest ledger, not a stale copy', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('/group');
    // Something changes the ledger while the flow is open.
    await store.save(store.ledger.removeExpense('e1'), 'Deleted');
    await tester.type('Flat');
    await tester.tapText('Create group');
    expect(store.ledger.expenses, isEmpty);
    expect(store.ledger.bills.map((b) => b.name), contains('Flat'));
  });

  testWidgets('/sent lowers what you owe', (tester) async {
    final store = await pumpApp(
      tester,
      ledgerWith(expenses: [expense(payerId: 'rahul')]),
    );
    await tester.tapText('/sent');
    expect(find.text('How much did you send?'), findsOneWidget);
    await tester.type('600');
    await tester.next();
    expect(find.text('you owe ₹600'), findsOneWidget);
    await tester.tapText('Rahul');
    await tester.tapText('General');
    await tester.tapText('Dinner');
    await tester.next();
    await tester.tapText('Record ₹600 sent');
    expect(store.ledger.balance('rahul'), 0);
    expect(find.text('₹600 to Rahul recorded'), findsOneWidget);
  });

  testWidgets('/friend adds a friend', (tester) async {
    final store = await pumpApp(tester);
    await tester.tapText('Type a command');
    await tester.enterText(find.byType(TextField), 'friend');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('What’s your friend’s name?'), findsOneWidget);
    await tester.type('Asha');
    await tester.tapText('Add friend');
    expect(store.ledger.friends.single.name, 'Asha');
    expect(find.text('Asha'), findsOneWidget);
  });

  testWidgets('/undo reverts the last change', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/group');
    await tester.type('Flat');
    await tester.tapText('Create group');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'undo');
    await tester.pumpAndSettle();
    expect(find.text('Undo: “Flat” created'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(store.ledger.bills.map((b) => b.name), isNot(contains('Flat')));
    expect(find.text('Undid: “Flat” created'), findsOneWidget);
  });

  testWidgets('an unreadable save shows an error and can retry', (
    tester,
  ) async {
    final storage = MemoryStorage('{broken');
    final store = Store(storage);
    await store.load();
    await tester.pumpWidget(BetweenApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Your records couldn’t be opened'), findsOneWidget);
    storage.json = jsonEncode(ledgerWith().toJson());
    await tester.tapText('Try again');
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('commas in an amount are digit grouping', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Rent');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    await tester.type('12,000');
    expect(find.text('12000'), findsOneWidget);
  });

  testWidgets('typing a slash command filters and runs it', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('/friend'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'gr');
    await tester.pumpAndSettle();
    expect(find.text('/group'), findsOneWidget);
    expect(find.text('/expense'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('What should the group be called?'), findsOneWidget);
    await tester.type('goa TRIP');
    await tester.tapText('Create group');
    expect(find.text('You already have a group called “goa TRIP”.'), findsOne);
  });

  testWidgets('undo removes a new bill and closes its screen', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/group');
    await tester.type('Flat');
    await tester.tapText('Create group');
    expect(store.ledger.bills.map((b) => b.name), contains('Flat'));
    await tester.tapText('Undo');
    expect(store.ledger.bills.map((b) => b.name), isNot(contains('Flat')));
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('an expense opens on its review and can be deleted', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Dinner');
    expect(find.text('Edit expense'), findsOneWidget);
    expect(find.text('Tap an answer above to change it.'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(store.ledger.expenses, isEmpty);
    expect(find.text('“Dinner” deleted'), findsOneWidget);
    await tester.tapText('Undo');
    expect(store.ledger.expenses, hasLength(1));
  });

  testWidgets('a friend page records a payment with the friend filled in', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Rahul');
    expect(find.text('Rahul owes you ₹600.'), findsOneWidget);
    await tester.tapText('Received');
    await tester.type('100');
    await tester.next();
    expect(find.text('Which group is it for?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'from Rahul'), findsOneWidget);
    await tester.tapText('General');
    await tester.next(); // Not for any expense in particular.
    await tester.tapText('Record ₹100 received');
    expect(store.ledger.balance('rahul'), 50000);
    expect(find.text('Rahul owes you ₹500.'), findsOneWidget);
  });

  testWidgets('a bill page adds expenses to that bill', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('Goa trip');
    await tester.tapText('Add expense');
    await tester.type('Hotel');
    await tester.next();
    await tester.next(); // No category.
    expect(find.text('How much did it cost?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'in Goa trip'), findsOneWidget);
    await tester.type('3000');
    await tester.next();
    await tester.next();
    await tester.tapText('Priya');
    await tester.next();
    await tester.tapText('Priya');
    await tester.next();
    await tester.tapText('Add expense');
    expect(store.ledger.expenses.single.billId, 'goa');
    expect(find.text('₹3,000'), findsWidgets);
  });

  testWidgets('a friend can be renamed, and removed once unused', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Rahul');
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Rename');
    await tester.type('Rahul K');
    await tester.tapText('Save name');
    expect(store.ledger.friend('rahul')!.name, 'Rahul K');
    expect(find.text('Rahul K'), findsWidgets);

    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Remove friend');
    expect(find.textContaining('can’t be removed'), findsOneWidget);
    expect(store.ledger.friend('rahul'), isNotNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tapText('Priya');
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Remove friend');
    expect(store.ledger.friend('priya'), isNull);
    expect(find.text('Priya removed'), findsOneWidget);
  });

  testWidgets('deleting a bill takes its expenses, and undo brings both', (
    tester,
  ) async {
    final store = await pumpApp(
      tester,
      ledgerWith(
        expenses: [expense(billId: 'goa', name: 'Hotel')],
      ),
    );
    await tester.tapText('Goa trip');
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Delete group');
    expect(store.ledger.bill('goa'), isNull);
    expect(store.ledger.expenses, isEmpty);
    expect(find.text('“Goa trip” and its expense deleted'), findsOneWidget);
    await tester.tapText('Undo');
    expect(store.ledger.expense('e1')!.billId, 'goa');
  });

  testWidgets('General has no rename or delete', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tapText('General');
    expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
  });

  testWidgets('a landscape phone with the keyboard up does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Pizza');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(find.text('How much did it cost?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screens fit small phones at large text sizes', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('/expense');
    await tester.type('A long expense name');
    await tester.next();
    await tester.next(); // No category.
    await tester.next();
    await tester.type('1200');
    await tester.next();
    await tester.next();
    await tester.tapText('Rahul');
    await tester.next();
    await tester.tapText('You');
    await tester.tapText('By amount');
    await tester.next();
    expect(find.textContaining('still to assign'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expense that was just yours skips who paid and the split', (
    tester,
  ) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tapText('/expense');
    await tester.type('Coffee');
    await tester.next();
    await tester.tapText('Travel'); // Picking moves on by itself.
    await tester.next();
    await tester.type('150');
    await tester.next();
    await tester.next();
    expect(find.text('Who shared it with you?'), findsOneWidget);
    await tester.next();

    expect(find.text('Look right?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'just you'), findsOneWidget);
    expect(find.textContaining('owes'), findsNothing);
    expect(find.textContaining('Spent in '), findsOneWidget);
    await tester.tapText('Add expense');
    final saved = store.ledger.expenses.single;
    expect(saved.personal, isTrue);
    expect(saved.categoryId, 'travel');
  });

  testWidgets('personal spending alone moves past the welcome', (tester) async {
    await pumpApp(tester, Ledger.empty.put(expense: expense(parts: {me: 1})));
    expect(find.text('Add your first expense'), findsNothing);
    expect(find.text('Spent in ${monthName(DateTime.now())}'), findsOneWidget);
  });

  testWidgets('the review’s date can be moved to another day', (tester) async {
    final store = await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Dinner');
    await tester.tapText('Change');
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '01/15/2025');
    await tester.tapText('OK');
    expect(find.text(shortDate(DateTime(2025, 1, 15))), findsOneWidget);
    await tester.tapText('Save changes');
    expect(store.ledger.expenses.single.date, DateTime(2025, 1, 15));
  });

  testWidgets('spending shows the month by category and narrows the list', (
    tester,
  ) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(
            name: 'Train',
            amount: 50000,
            parts: {me: 1},
            categoryId: 'travel',
            date: thisMonth,
          ),
          expense(
            id: 'e2',
            name: 'Flat',
            amount: 200000,
            parts: {me: 1},
            categoryId: 'rent',
            date: thisMonth,
          ),
          // Split with Rahul: only your ₹600 is spending.
          expense(id: 'e3', name: 'Dinner', date: thisMonth),
          expense(
            id: 'e4',
            name: 'Old',
            amount: 100000,
            parts: {me: 1},
            date: lastMonth,
          ),
        ],
      ),
    );
    expect(find.text('Most on Rent'), findsOneWidget);
    await tester.tapText('Spent in ${monthName(now)}');

    final month = monthName(now);
    expect(find.text('You’ve spent ₹3,100 so far in $month.'), findsOneWidget);
    expect(find.text('₹2,100 more than this time last month'), findsOneWidget);
    // Shares of the month, with no category last whatever its size.
    for (final share in ['65%', '16%', '19%']) {
      expect(find.text(share), findsOneWidget);
    }
    await tester.reveal(find.text('Dinner'));
    expect(
      find.text('your share of ₹1,200 · ${shortDate(thisMonth)}'),
      findsOne,
    );

    await tester.tapText('Rent');
    expect(find.text('Flat'), findsOneWidget);
    expect(find.text('Train'), findsNothing);
    await tester.tapText('Show all');
    await tester.reveal(find.text('Train'));
    expect(find.text('Train'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(
      find.text('You spent ₹1,000 in ${monthName(lastMonth)}.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
  });

  testWidgets('/spending opens from the command bar', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'spe');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing spent in ${monthName(DateTime.now())} yet.'),
      findsOneWidget,
    );
  });

  testWidgets('categories can be added, renamed and deleted', (tester) async {
    final store = await pumpApp(
      tester,
      ledgerWith(expenses: [expense(categoryId: 'travel')]),
    );
    await tester.tapText('Spent in ${monthName(DateTime.now())}');
    await tester.tap(find.byTooltip('Categories'));
    await tester.pumpAndSettle();
    expect(find.text('1 expense'), findsOneWidget);

    await tester.tapText('New category');
    await tester.type('rent');
    await tester.next();
    expect(find.text('You already have a category called “rent”.'), findsOne);
    await tester.type('Food');
    await tester.next();
    expect(find.text('Count it in your spending?'), findsOneWidget);
    await tester.tapText('Yes, count it'); // Picking saves.
    expect(store.ledger.categories.map((c) => c.name), contains('Food'));

    // Each category has its own page, with edit and delete in its menu.
    await tester.tapText('Travel');
    expect(find.text('1 expense'), findsNothing);
    expect(find.textContaining('in all, 1 expense'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Edit');
    await tester.type('Trips');
    await tester.next();
    await tester.tapText('No, leave it out');
    expect(store.ledger.category('travel')!.name, 'Trips');
    expect(store.ledger.category('travel')!.counted, isFalse);
    expect(find.textContaining('not counted in your spending'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tapText('Delete category');
    expect(
      find.text('“Trips” deleted. Its expense now has no category.'),
      findsOneWidget,
    );
    expect(store.ledger.expenses.single.categoryId, isNull);
    await tester.tapText('Undo');
    expect(store.ledger.expenses.single.categoryId, 'travel');
  });

  testWidgets('the review’s date is its own button for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('Dinner');
    final card = tester.getSemantics(find.text('Dinner').last);
    expect(card.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(find.bySemanticsLabel(RegExp(r'^Date: .*\. Change$')), findsOne);
    semantics.dispose();
  });

  testWidgets('a narrowed list follows the rows on screen', (tester) async {
    final now = DateTime.now();
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(
            name: 'Flat',
            parts: {me: 1},
            categoryId: 'rent',
            date: DateTime(now.year, now.month),
          ),
          expense(
            id: 'e2',
            name: 'Snack',
            parts: {me: 1},
            date: DateTime(now.year, now.month - 1),
          ),
        ],
      ),
    );
    await tester.tapText('Spent in ${monthName(now)}');
    // One category this month: no bar, but still a full-size target.
    final row = find.ancestor(
      of: find.text('Rent'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    await tester.tapText('Rent');
    expect(find.text('Show all'), findsOneWidget);

    // Last month has no Rent row, so nothing is narrowed there.
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsNothing);
    await tester.reveal(find.text('Snack'));
    expect(find.text('Snack'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsOneWidget);
  });

  testWidgets('one payment can pay off several expenses', (tester) async {
    // Rahul owes ₹15 for a lollipop and ₹17.50 for nachos, and sends ₹31.
    final store = await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(id: 'lolly', name: 'Lollipop', amount: 3000),
          expense(id: 'nachos', name: 'Nachos', amount: 3500),
        ],
      ),
    );
    await tester.tapText('/receive');
    await tester.type('31');
    await tester.next();
    await tester.tapText('Rahul');
    await tester.tapText('General');
    await tester.tapText('Lollipop');
    await tester.tapText('Nachos');
    // Ticked first, the lollipop is paid in full.
    expect(find.text('1st · ₹15, paid in full'), findsOneWidget);
    expect(find.text('2nd · ₹16 of ₹17.50, ₹1.50 left'), findsOneWidget);
    await tester.next();

    expect(
      find.widgetWithText(ActionChip, 'for Lollipop and Nachos'),
      findsOne,
    );
    expect(find.text('₹1.50 still open'), findsOneWidget);
    await tester.tapText('Record ₹31 received');
    expect(store.ledger.payments.single.settles, {
      'lolly': 1500,
      'nachos': 1600,
    });
    expect(store.ledger.balance('rahul'), 150);

    await tester.tapText('Rahul');
    expect(find.text('Rahul owes you ₹1.50.'), findsOneWidget);
    expect(find.textContaining('for Lollipop and Nachos'), findsOneWidget);
    expect(find.textContaining('₹1.50 left'), findsOneWidget);
  });

  testWidgets('a payment can’t continue with an expense it runs out before', (
    tester,
  ) async {
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [
          expense(id: 'lolly', name: 'Lollipop', amount: 3000),
          expense(id: 'nachos', name: 'Nachos', amount: 3500),
        ],
      ),
    );
    await tester.tapText('/receive');
    await tester.type('10');
    await tester.next();
    await tester.tapText('Rahul');
    await tester.tapText('General');
    await tester.tapText('Lollipop');
    await tester.tapText('Nachos');
    expect(find.text('2nd · Nothing left for this'), findsOneWidget);
    await tester.next();
    expect(find.text('Which expenses is it for?'), findsOneWidget);
    expect(find.textContaining('is used up before Nachos'), findsOneWidget);
  });

  testWidgets('changing the bill from the review asks for expenses again', (
    tester,
  ) async {
    await pumpApp(tester, ledgerWith(expenses: [expense()]));
    await tester.tapText('/receive');
    await tester.type('600');
    await tester.next();
    await tester.tapText('Rahul');
    await tester.tapText('General');
    await tester.tapText('Dinner');
    await tester.next();
    expect(find.text('Look right?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'in General'));
    await tester.pumpAndSettle();
    await tester.tapText('Goa trip');
    expect(find.text('Which expenses is it for?'), findsOneWidget);
    await tester.next();
    expect(find.widgetWithText(ActionChip, 'toward the balance'), findsOne);
  });

  testWidgets('a bill lists payments toward its expenses', (tester) async {
    await pumpApp(
      tester,
      ledgerWith(
        expenses: [expense(id: 'hotel', name: 'Hotel', billId: 'goa')],
        // Recorded in General, but toward Goa trip's hotel.
        payments: [payment(amount: 60000, expenseId: 'hotel')],
      ),
    );
    await tester.tapText('Goa trip');
    expect(find.text('Rahul sent you'), findsOneWidget);
    expect(find.textContaining('for Hotel'), findsOneWidget);
  });

  testWidgets('back from the expenses page keeps the ticks', (tester) async {
    final store = await pumpApp(
      tester,
      ledgerWith(
        expenses: [expense()],
        payments: [payment(amount: 60000, expenseId: 'e1')],
      ),
    );
    await tester.tapText('Rahul sent you');
    await tester.tap(find.widgetWithText(ActionChip, 'from Rahul'));
    await tester.pumpAndSettle();
    await tester.tapText('Priya');
    expect(find.text('Which expenses is it for?'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tapText('Rahul');
    await tester.next();
    expect(find.widgetWithText(ActionChip, 'for Dinner'), findsOneWidget);
    await tester.tapText('Change');
    await tester.tapText('Cancel');
    await tester.tapText('Save changes');
    expect(store.ledger.payments.single.settles, {'e1': 60000});
  });

  group('backup to Google', () {
    testWidgets('asks first, then notes it at the end once backed up', (
      tester,
    ) async {
      final account = FakeAccount();
      await pumpApp(tester, ledgerWith(), account);
      final spending = tester.getTopLeft(find.text('Spending')).dy;
      expect(
        tester.getTopLeft(find.text('Back up to Google')).dy,
        lessThan(spending),
      );

      await tester.tapText('Back up to Google');
      expect(account.state, SyncState.synced);
      await tester.reveal(find.text('Backed up to Google'));
      expect(find.text('aditya@example.com'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Backed up to Google')).dy,
        greaterThan(tester.getTopLeft(find.text('Recent')).dy),
      );
    });

    testWidgets('says why signing in failed', (tester) async {
      final account = FakeAccount()
        ..failure = const SignInFailure('Couldn’t sign in.');
      await pumpApp(tester, ledgerWith(), account);
      await tester.tapText('Back up to Google');
      expect(find.text('Couldn’t sign in.'), findsOneWidget);
      expect(account.state, SyncState.signedOut);
    });

    testWidgets('a fresh install offers to restore', (tester) async {
      final account = FakeAccount();
      await pumpApp(tester, null, account);
      await tester.tapText('Restore from Google');
      expect(account.state, SyncState.synced);
      expect(find.text('Restore from Google'), findsNothing);
    });

    testWidgets('signing out keeps every record', (tester) async {
      final account = FakeAccount()..state = SyncState.synced;
      final store = await pumpApp(
        tester,
        ledgerWith(expenses: [expense()]),
        account,
      );
      await tester.tapText('Backed up to Google');
      await tester.tapText('Sign out');
      expect(account.state, SyncState.signedOut);
      expect(store.ledger.expenses, hasLength(1));
      // The invitation to back up is back at the top.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 3000),
        3000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Back up to Google'), findsOneWidget);
    });

    testWidgets('a failed sync can be tried again', (tester) async {
      final account = FakeAccount()..state = SyncState.failed;
      await pumpApp(tester, ledgerWith(), account);
      expect(find.textContaining('safe on this phone'), findsOneWidget);
      await tester.tapText('Couldn’t back up');
      expect(account.state, SyncState.synced);
    });

    testWidgets('without Firebase there is no backup row', (tester) async {
      await pumpApp(tester, ledgerWith());
      expect(find.text('Back up to Google'), findsNothing);
      expect(find.text('Backup'), findsNothing);
    });
  });

  testWidgets('/income records money nobody owes back', (tester) async {
    final store = await pumpApp(tester, ledgerWith());
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'income');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('How much did you get?'), findsOneWidget);
    await tester.type('1,00,000');
    await tester.next();
    await tester.type('Mom');
    await tester.tapText('From “Mom”');
    await tester.type('College fees');
    await tester.next();
    expect(find.text('Mom gave you'), findsOneWidget);
    await tester.tapText('Record ₹1,00,000');
    expect(store.ledger.incomes.single.note, 'College fees');
    expect(find.text('You’re all settled up.'), findsOneWidget);
    await tester.reveal(find.text('Mom gave you'));
    expect(find.text('Mom gave you'), findsOneWidget);
  });

  testWidgets('college fees paid with money from home don’t swamp spending', (
    tester,
  ) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    await pumpApp(
      tester,
      ledgerWith(
            expenses: [
              expense(
                name: 'Groceries',
                amount: 200000,
                parts: {me: 1},
                date: thisMonth,
              ),
              expense(
                id: 'e2',
                name: 'Semester fees',
                amount: 10000000,
                parts: {me: 1},
                categoryId: 'fees',
                date: thisMonth,
              ),
            ],
          )
          .put(
            category: const Category(id: 'fees', name: 'Fees', counted: false),
          )
          .put(
            income: Income(
              id: 'i1',
              from: 'Mom',
              amount: 10000000,
              date: thisMonth,
              note: 'College fees',
            ),
          ),
    );
    await tester.tapText('Spent in ${monthName(now)}');
    expect(
      find.text('You’ve spent ₹2,000 so far in ${monthName(now)}.'),
      findsOneWidget,
    );
    expect(find.text('₹1,00,000 came in'), findsOneWidget);
    expect(find.text('Plus ₹1,00,000 not counted'), findsOneWidget);
    await tester.reveal(find.text('Not counted in spending'));
    await tester.reveal(find.text('Semester fees'));
    expect(find.text('Semester fees'), findsOneWidget);
    await tester.reveal(find.text('Money in'));
    await tester.reveal(find.text('Mom gave you'));
    expect(find.textContaining('College fees'), findsWidgets);
  });

  testWidgets('home lists categories, each with its own page', (tester) async {
    final store = await pumpApp(
      tester,
      ledgerWith(expenses: [expense(categoryId: 'travel')]),
    );
    await tester.reveal(find.text('Categories'));
    await tester.tapText('Travel');
    expect(find.textContaining('in all, 1 expense'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);

    // Adding from here fills in the category.
    await tester.tapText('Add expense');
    await tester.type('Train');
    await tester.next();
    expect(find.text('Which group is it part of?'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Travel'), findsOneWidget);
    await tester.next();
    await tester.type('300');
    await tester.next();
    await tester.next();
    await tester.next();
    await tester.tapText('Add expense');
    expect(store.ledger.expenses.last.categoryId, 'travel');
  });

  testWidgets('/categories opens every category', (tester) async {
    await pumpApp(tester, ledgerWith());
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'categories');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('Your categories'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });
}

/// An account that signs in at once, as aditya@example.com.
class FakeAccount extends Account {
  @override
  SyncState state = SyncState.signedOut;

  /// When set, signing in throws it.
  SignInFailure? failure;

  @override
  String? get email =>
      state == SyncState.signedOut ? null : 'aditya@example.com';

  @override
  Future<bool> signIn() async {
    if (failure case final failure?) throw failure;
    state = SyncState.synced;
    notifyListeners();
    return true;
  }

  @override
  Future<void> signOut() async {
    state = SyncState.signedOut;
    notifyListeners();
  }

  @override
  Future<void> retry() async {
    state = SyncState.synced;
    notifyListeners();
  }
}
