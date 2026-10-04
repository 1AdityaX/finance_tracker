import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/spending.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'categories_screen.dart';
import 'widgets.dart';

/// Where your money went, a month at a time: what you spent, how that
/// compares with the month before, and what it went on, by category and by
/// bill. Tapping a category or bill narrows the expenses listed below.
class SpendingScreen extends StatefulWidget {
  const SpendingScreen({super.key, required this.store});
  final Store store;

  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

/// What the expenses list is narrowed to: a bill, or a category, where ''
/// stands for expenses with no category.
typedef _Filter = ({bool bill, String id});

class _SpendingScreenState extends State<SpendingScreen> {
  Store get store => widget.store;
  late DateTime month = _thisMonth;
  _Filter? filter;

  static DateTime get _thisMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void _go(int months) =>
      setState(() => month = DateTime(month.year, month.month + months));

  void _toggle(_Filter tapped) =>
      setState(() => filter = filter == tapped ? null : tapped);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final ledger = store.ledger;
      final spending = Spending(ledger, month);
      // Pages run from the month of your first expense to this one.
      final months = ledger.expenses.map(
        (e) => DateTime(e.date.year, e.date.month),
      );
      final first = months.fold(_thisMonth, (a, b) => b.isBefore(a) ? b : a);
      final last = months.fold(_thisMonth, (a, b) => b.isAfter(a) ? b : a);
      // A category or bill deleted since it was tapped no longer narrows.
      final filter = switch (this.filter) {
        (bill: true, :final id) when ledger.bill(id) == null => null,
        (bill: false, :final id)
            when id.isNotEmpty && ledger.category(id) == null =>
          null,
        final filter => filter,
      };
      final items = [
        for (final item in spending.items)
          if (_matches(ledger, filter, item.expense)) item,
      ];
      return Scaffold(
        appBar: AppBar(
          title: const Text('Spending'),
          actions: [
            IconButton(
              tooltip: 'Categories',
              icon: const Icon(Icons.sell_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoriesScreen(store: store),
                ),
              ),
            ),
          ],
          bottom: _MonthBar(
            month: month,
            onPrevious: month.isAfter(first) ? () => _go(-1) : null,
            onNext: month.isBefore(last) ? () => _go(1) : null,
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _headline(spending),
                ),
                if (_comparison(ledger, spending.total) case final text?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (spending.total == 0 && month == _thisMonth)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: FilledButton.icon(
                      onPressed: () =>
                          startFlow(context, store, ExpenseFlow(store.ledger)),
                      icon: const Icon(Icons.add),
                      label: const Text('Add an expense'),
                    ),
                  ),
                if (spending.total > 0) ...[
                  ..._byCategory(ledger, spending, filter),
                  if (spending.byBill.length > 1) ...[
                    const SectionHeader('By bill'),
                    for (final row in spending.byBill)
                      _BarRow(
                        key: ValueKey('bill/${row.id}'),
                        label: ledger.bill(row.id)!.name,
                        amount: row.amount,
                        total: spending.total,
                        selected: filter == (bill: true, id: row.id),
                        dimmed: filter?.bill == true && filter?.id != row.id,
                        onTap: () => _toggle((bill: true, id: row.id)),
                      ),
                  ],
                  SectionHeader(
                    filter == null ? 'Expenses' : _label(ledger, filter),
                    action: filter == null
                        ? null
                        : TextButton(
                            onPressed: () => setState(() => this.filter = null),
                            child: const Text('Show all'),
                          ),
                  ),
                  if (items.isEmpty)
                    EmptyNote(
                      'Nothing in ${_label(ledger, filter!)} '
                      'in ${monthName(month)}.',
                    ),
                ],
              ],
            ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) =>
                  _expenseTile(ledger, items[i], filter),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      );
    },
  );

  /// "You’ve spent ₹12,400 so far in October."
  Widget _headline(Spending spending) {
    final style = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontFeatures: tabular);
    final name = monthName(month);
    final current = month == _thisMonth;
    if (spending.total == 0) {
      return Text(
        current ? 'Nothing spent in $name yet.' : 'Nothing spent in $name.',
        style: style,
      );
    }
    return Text(
      current
          ? 'You’ve spent ${rupees(spending.total)} so far in $name.'
          : 'You spent ${rupees(spending.total)} in $name.',
      style: style,
    );
  }

  /// How the month compares with the one before. The current month is
  /// compared with the same days of last month, so a month that has only
  /// just begun isn't measured against a whole one.
  String? _comparison(Ledger ledger, int total) {
    final current = month == _thisMonth;
    final previous = DateTime(month.year, month.month - 1);
    final before = Spending(
      ledger,
      previous,
      throughDay: current ? DateTime.now().day : null,
    ).total;
    if (before == 0) return null;
    final than = current ? 'this time last month' : monthName(previous);
    final difference = total - before;
    return switch (difference.sign) {
      1 => '${rupees(difference)} more than $than',
      -1 => '${rupees(-difference)} less than $than',
      _ => 'The same as $than',
    };
  }

  List<Widget> _byCategory(Ledger ledger, Spending spending, _Filter? filter) {
    final rows = spending.byCategory;
    const header = SectionHeader('By category');
    // One "No category" bar would say nothing, so say how to get a picture.
    if (rows.every((row) => row.id.isEmpty)) {
      return [
        header,
        EmptyNote(
          ledger.categories.isEmpty
              ? 'Add categories with /category, or while adding an '
                    'expense, to see what your money goes on.'
              : 'None of these expenses has a category yet. Tap one below '
                    'to give it one.',
        ),
      ];
    }
    return [
      header,
      for (final row in rows)
        _BarRow(
          key: ValueKey('category/${row.id}'),
          label: row.id.isEmpty
              ? CategoryFlow.noCategory
              : ledger.category(row.id)!.name,
          amount: row.amount,
          total: spending.total,
          other: row.id.isEmpty,
          // A single bar is all of it; the amount says as much.
          showBar: rows.length > 1,
          selected: filter == (bill: false, id: row.id),
          dimmed: filter?.bill == false && filter?.id != row.id,
          onTap: () => _toggle((bill: false, id: row.id)),
        ),
    ];
  }

  static bool _matches(Ledger ledger, _Filter? filter, Expense e) =>
      switch (filter) {
        null => true,
        (bill: true, :final id) => e.billId == id,
        (bill: false, :final id) =>
          (ledger.category(e.categoryId)?.id ?? '') == id,
      };

  static String _label(Ledger ledger, _Filter filter) => switch (filter) {
    (bill: true, :final id) => ledger.bill(id)!.name,
    (bill: false, id: '') => CategoryFlow.noCategory,
    (bill: false, :final id) => ledger.category(id)!.name,
  };

  /// An expense with your share of it. What the list is narrowed to goes
  /// unsaid, as does the General bill.
  Widget _expenseTile(
    Ledger ledger,
    ({Expense expense, int share}) item,
    _Filter? filter,
  ) {
    final e = item.expense;
    return ListTile(
      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (filter?.bill != false) ?ledger.category(e.categoryId)?.name,
          if (filter?.bill != true && e.billId != generalBill)
            ledger.bill(e.billId)!.name,
          if (!e.personal) 'your share of ${rupees(e.amount)}',
          shortDate(e.date),
        ].join(' · '),
        maxLines: 2,
      ),
      trailing: TrailingAmount(rupees(item.share)),
      onTap: () =>
          startFlow(context, store, ExpenseFlow(store.ledger, existing: e)),
    );
  }
}

/// "‹ October 2026 ›", pinned under the title.
class _MonthBar extends StatelessWidget implements PreferredSizeWidget {
  const _MonthBar({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });
  final DateTime month;

  /// Null where there is nothing further to see.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: Text(
                '${monthName(month)} ${month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

/// One line of a breakdown: a name and amount over a thin bar showing its
/// share of the month, with the share as a percentage at the bar's end.
class _BarRow extends StatelessWidget {
  const _BarRow({
    super.key,
    required this.label,
    required this.amount,
    required this.total,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    this.other = false,
    this.showBar = true,
  });
  final String label;
  final int amount;
  final int total;
  final bool selected;

  /// True while another row in the same breakdown is selected.
  final bool dimmed;
  final VoidCallback onTap;

  /// The catch-all "No category", drawn in a neutral rather than the hue.
  final bool other;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = amount / total;
    final percent = switch ((fraction * 100).round()) {
      0 => '<1%',
      final n => '$n%',
    };
    final color = other ? scheme.outline : scheme.bar;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${rupees(amount)}, $percent of your spending',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          color: selected ? scheme.surfaceContainerHigh : null,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: other ? scheme.onSurfaceVariant : null,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    rupees(amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
              if (showBar) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Bar(
                        fraction: fraction,
                        color: dimmed ? color.withValues(alpha: 0.35) : color,
                        track: color.withValues(alpha: 0.14),
                      ),
                    ),
                    // Wide enough for "100%", so every bar ends in line.
                    SizedBox(
                      width: MediaQuery.textScalerOf(context).scale(48),
                      child: Text(
                        percent,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin horizontal bar on a track of its own hue: square where it starts,
/// rounded where the value ends. It grows to a new value rather than jump.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.color,
    required this.track,
  });
  final double fraction;
  final Color color;
  final Color track;

  static const _end = BorderRadius.horizontal(right: Radius.circular(4));

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(color: track, borderRadius: _end),
      child: AnimatedFractionallySizedBox(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        // The smallest shares still show as a sliver.
        widthFactor: fraction.clamp(0.01, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, borderRadius: _end),
        ),
      ),
    ),
  );
}
