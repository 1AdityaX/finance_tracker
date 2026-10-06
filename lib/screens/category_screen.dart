import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/spending.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'widgets.dart';

/// One category: what it cost you, its expenses, and editing or deleting it.
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({
    super.key,
    required this.store,
    required this.categoryId,
  });
  final Store store;
  final String categoryId;

  Future<void> _delete(BuildContext context, Category category) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final count = store.ledger.expenses
        .where((e) => e.categoryId == category.id)
        .length;
    final message = switch (count) {
      0 => '“${category.name}” deleted',
      1 => '“${category.name}” deleted. Its expense now has no category.',
      _ =>
        '“${category.name}” deleted. Its $count expenses now have no '
            'category.',
    };
    await store.save(store.ledger.removeCategory(category.id), message);
    showUndo(messenger, store, message);
  }

  @override
  Widget build(BuildContext context) => RecordScreen(
    store: store,
    find: (ledger) => ledger.category(categoryId),
    builder: (context, ledger, category) {
      final theme = Theme.of(context);
      final expenses = ledger.expenses
          .where((e) => e.categoryId == category.id)
          .toList();
      final now = DateTime.now();
      int share(Iterable<Expense> list) =>
          list.fold(0, (sum, e) => sum + (e.shares[me] ?? 0));
      final thisMonth = share(
        expenses.where(
          (e) => e.date.year == now.year && e.date.month == now.month,
        ),
      );
      final muted = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(category.name),
          actions: [
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: () => startFlow(
                    context,
                    store,
                    CategoryFlow(ledger, existing: category),
                  ),
                  child: const Text('Edit'),
                ),
                PopupMenuItem(
                  value: () => _delete(context, category),
                  child: const Text('Delete category'),
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    thisMonth == 0
                        ? 'Nothing on ${category.name} in ${monthName(now)}.'
                        : '${rupees(thisMonth)} on ${category.name} in '
                              '${monthName(now)}.',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Text(
                    [
                      switch (expenses.length) {
                        0 => 'No expenses yet',
                        1 => '${rupees(share(expenses))} in all, 1 expense',
                        final n =>
                          '${rupees(share(expenses))} in all, $n expenses',
                      },
                      if (!category.counted) 'not counted in your spending',
                    ].join(' · '),
                    style: muted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FilledButton.icon(
                    onPressed: () => startFlow(
                      context,
                      store,
                      ExpenseFlow(ledger, categoryId: category.id),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add expense'),
                  ),
                ),
                const SectionHeader('Expenses'),
                if (expenses.isEmpty)
                  EmptyNote(
                    'Expenses you give the ${category.name} category show '
                    'up here.',
                  ),
              ],
            ),
            ActivityList(store: store, expenses: expenses, payments: const []),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      );
    },
  );
}
