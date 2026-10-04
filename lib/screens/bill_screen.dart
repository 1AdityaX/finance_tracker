import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'widgets.dart';

class BillScreen extends StatelessWidget {
  const BillScreen({super.key, required this.store, required this.billId});
  final Store store;
  final String billId;

  Future<void> _delete(BuildContext context, Bill bill, int expenses) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final message = switch (expenses) {
      0 => '“${bill.name}” deleted',
      1 => '“${bill.name}” and its expense deleted',
      _ => '“${bill.name}” and its $expenses expenses deleted',
    };
    await store.save(store.ledger.removeBill(bill.id), message);
    showUndo(messenger, store, message);
  }

  @override
  Widget build(BuildContext context) => RecordScreen(
    store: store,
    find: (ledger) => ledger.bill(billId),
    builder: (context, ledger, bill) {
      final theme = Theme.of(context);
      final expenses = ledger.expenses.where((e) => e.billId == bill.id);
      final payments = ledger.payments.where((p) => p.billId == bill.id);
      final total = expenses.fold(0, (sum, e) => sum + e.amount);
      final inBill = ledger.balances(billId: bill.id);
      final balances = [
        for (final friend in ledger.recentFriends)
          if (inBill[friend.id] case final balance? when balance != 0)
            (friend: friend, balance: balance),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(bill.name),
          actions: [
            if (bill.id != generalBill)
              PopupMenuButton<VoidCallback>(
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: () => startFlow(
                      context,
                      store,
                      BillFlow(ledger, existing: bill),
                    ),
                    child: const Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: () => _delete(context, bill, expenses.length),
                    child: const Text('Delete bill'),
                  ),
                ],
              ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text.rich(
                    TextSpan(
                      children: expenses.isEmpty
                          ? [const TextSpan(text: 'No expenses yet.')]
                          : [
                              TextSpan(
                                text: rupees(total),
                                style: const TextStyle(fontFeatures: tabular),
                              ),
                              TextSpan(
                                text: expenses.length == 1
                                    ? ' spent on 1 expense.'
                                    : ' spent across ${expenses.length} expenses.',
                              ),
                            ],
                    ),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FilledButton.icon(
                    onPressed: () => startFlow(
                      context,
                      store,
                      ExpenseFlow(ledger, billId: bill.id),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add expense'),
                  ),
                ),
                if (balances.isNotEmpty) ...[
                  const SectionHeader('Balances'),
                  for (final b in balances)
                    ListTile(
                      leading: Avatar(b.friend.name),
                      title: Text(b.friend.name),
                      subtitle: BalanceText(b.balance),
                    ),
                ],
                const SectionHeader('Activity'),
                if (expenses.isEmpty && payments.isEmpty)
                  const EmptyNote(
                    'Expenses you add to this bill show up here.',
                  ),
              ],
            ),
            ActivityList(
              store: store,
              expenses: expenses,
              payments: payments,
              showBill: false,
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      );
    },
  );
}
