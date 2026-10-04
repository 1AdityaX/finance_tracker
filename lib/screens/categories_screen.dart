import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import 'widgets.dart';

/// Your categories, to add, rename and delete.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.store});
  final Store store;

  Future<void> _delete(BuildContext context, Category category) async {
    final messenger = ScaffoldMessenger.of(context);
    final used = store.ledger.expenses.where(
      (e) => e.categoryId == category.id,
    );
    final message = switch (used.length) {
      0 => '“${category.name}” deleted',
      1 => '“${category.name}” deleted. Its expense now has no category.',
      final n =>
        '“${category.name}” deleted. Its $n expenses now have no '
            'category.',
    };
    await store.save(store.ledger.removeCategory(category.id), message);
    showUndo(messenger, store, message);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final ledger = store.ledger;
      final theme = Theme.of(context);
      final counts = <String, int>{};
      for (final e in ledger.expenses) {
        if (e.categoryId case final id?) counts[id] = (counts[id] ?? 0) + 1;
      }
      final categories = ledger.categories.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Give an expense a category when you add it, to see where '
                'your money goes. Tap a category to rename it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                onPressed: () =>
                    startFlow(context, store, CategoryFlow(store.ledger)),
                icon: const Icon(Icons.add),
                label: const Text('New category'),
              ),
            ),
            const SectionHeader('Your categories'),
            if (categories.isEmpty)
              const EmptyNote('None yet. Food, Rent and Travel are a start.'),
            for (final category in categories)
              ListTile(
                leading: const IconBadge(Icons.sell_outlined),
                title: Text(category.name),
                subtitle: Text(switch (counts[category.id] ?? 0) {
                  0 => 'No expenses yet',
                  1 => '1 expense',
                  final n => '$n expenses',
                }),
                trailing: IconButton(
                  tooltip: 'Delete ${category.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, category),
                ),
                onTap: () => startFlow(
                  context,
                  store,
                  CategoryFlow(store.ledger, existing: category),
                ),
              ),
          ],
        ),
      );
    },
  );
}
