import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'widgets.dart';

class FriendScreen extends StatelessWidget {
  const FriendScreen({super.key, required this.store, required this.friendId});
  final Store store;
  final String friendId;

  Future<void> _remove(BuildContext context, Friend friend) async {
    final messenger = ScaffoldMessenger.of(context);
    if (store.ledger.involves(friend.id)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${friend.name} is in expenses or payments, so they can’t be '
              'removed. Delete those first.',
            ),
          ),
        );
      return;
    }
    Navigator.of(context).pop();
    final message = '${friend.name} removed';
    await store.save(store.ledger.removeFriend(friend.id), message);
    showUndo(messenger, store, message);
  }

  @override
  Widget build(BuildContext context) => RecordScreen(
    store: store,
    find: (ledger) => ledger.friend(friendId),
    builder: (context, ledger, friend) {
      final theme = Theme.of(context);
      final balance = ledger.balance(friend.id);
      final byBill = ledger.billBalances(friend.id);
      final bills = [
        for (final bill in ledger.billsInOrder)
          if (byBill[bill.id] case final balance? when balance != 0)
            (bill: bill, balance: balance),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(friend.name),
          actions: [
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: () => startFlow(
                    context,
                    store,
                    FriendFlow(ledger, existing: friend),
                  ),
                  child: const Text('Rename'),
                ),
                PopupMenuItem(
                  value: () => _remove(context, friend),
                  child: const Text('Remove friend'),
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
                      children: [
                        if (balance == 0)
                          TextSpan(
                            text: 'You and ${friend.name} are settled up.',
                          )
                        else ...[
                          TextSpan(
                            text: '${owesPhrase(friend.name, balance)} ',
                          ),
                          TextSpan(
                            text: rupees(balance.abs()),
                            style: TextStyle(
                              color: theme.colorScheme.forSign(balance.sign),
                              fontFeatures: tabular,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ],
                    ),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => startFlow(
                            context,
                            store,
                            PaymentFlow(
                              ledger,
                              Direction.received,
                              friendId: friend.id,
                            ),
                          ),
                          icon: const Icon(Icons.south_west),
                          label: const Text('Received'),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => startFlow(
                            context,
                            store,
                            PaymentFlow(
                              ledger,
                              Direction.sent,
                              friendId: friend.id,
                            ),
                          ),
                          icon: const Icon(Icons.north_east),
                          label: const Text('Sent'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (bills.length > 1 ||
                    bills.any((b) => b.bill.id != generalBill)) ...[
                  const SectionHeader('By bill'),
                  for (final b in bills)
                    ListTile(
                      title: Text(b.bill.name),
                      subtitle: BalanceText(b.balance),
                    ),
                ],
                const SectionHeader('Activity'),
                if (!ledger.involves(friend.id))
                  EmptyNote('Nothing with ${friend.name} yet.'),
              ],
            ),
            ActivityList(
              store: store,
              expenses: ledger.expenses.where(
                (e) => e.payerId == friend.id || e.parts.containsKey(friend.id),
              ),
              payments: ledger.payments.where((p) => p.friendId == friend.id),
              friendId: friend.id,
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      );
    },
  );
}
