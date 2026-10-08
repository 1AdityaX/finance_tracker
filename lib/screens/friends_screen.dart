import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import 'friend_screen.dart';
import 'widgets.dart';

/// Every friend, settled or not, each opening their own page.
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final ledger = store.ledger;
      final balances = ledger.balances();
      final friends = ledger.friends.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final open = [
        for (final f in friends)
          if ((balances[f.id] ?? 0) != 0) f,
      ];
      final settled = [
        for (final f in friends)
          if ((balances[f.id] ?? 0) == 0) f,
      ];
      Widget tile(Friend friend) => ListTile(
        leading: Avatar(friend.name),
        title: Text(friend.name),
        subtitle: BalanceText(balances[friend.id] ?? 0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FriendScreen(store: store, friendId: friend.id),
          ),
        ),
      );
      return Scaffold(
        appBar: AppBar(title: const Text('Friends')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                onPressed: () =>
                    startFlow(context, store, FriendFlow(store.ledger)),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('New friend'),
              ),
            ),
            if (friends.isEmpty) const EmptyNote('No friends yet.'),
            if (open.isNotEmpty) ...[
              const SectionHeader('Not settled'),
              for (final f in open) tile(f),
            ],
            if (settled.isNotEmpty) ...[
              const SectionHeader('Settled up'),
              for (final f in settled) tile(f),
            ],
          ],
        ),
      );
    },
  );
}
