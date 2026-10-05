import 'package:flutter/material.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/spending.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'flow_screen.dart';

/// Opens [flow] as a full-screen task. Completes with true once it saved.
///
/// Any snackbar is dismissed first, so its Undo can't change the ledger
/// while the flow is open.
Future<bool> startFlow(
  BuildContext context,
  Store store,
  CommandFlow flow,
) async {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FlowScreen(store: store, flow: flow),
        ),
      ) ??
      false;
}

/// Confirms a saved change with a way to take it back.
void showUndo(ScaffoldMessengerState messenger, Store store, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Screen reader users need time to reach Undo.
        persist: MediaQuery.accessibleNavigationOf(messenger.context),
        action: SnackBarAction(label: 'Undo', onPressed: store.undo),
      ),
    );
}

/// Shows the record [find] returns, rebuilding as the ledger changes.
///
/// If the record goes away (after an undo, say) the screen closes itself,
/// and while a screen slides away it keeps showing the last version.
class RecordScreen<T extends Object> extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.store,
    required this.find,
    required this.builder,
  });
  final Store store;
  final T? Function(Ledger ledger) find;
  final Widget Function(BuildContext context, Ledger ledger, T record) builder;

  @override
  State<RecordScreen<T>> createState() => _RecordScreenState<T>();
}

class _RecordScreenState<T extends Object> extends State<RecordScreen<T>> {
  T? _last;

  void _closeIfShown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final route = mounted ? ModalRoute.of(context) : null;
    if (route != null && route.isCurrent) {
      Navigator.of(context).removeRoute(route);
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final ledger = widget.store.ledger;
      final current = widget.find(ledger);
      if (current == null) _closeIfShown();
      final record = _last = current ?? _last;
      return record == null
          ? const Scaffold()
          : widget.builder(context, ledger, record);
    },
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Text(name.characters.firstOrNull?.toUpperCase() ?? '?'),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;

  /// A small button at the end of the header, such as "Show all".
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    // A button is taller than the title, so it takes some of the spacing.
    padding: action == null
        ? const EdgeInsets.fromLTRB(20, 28, 20, 4)
        : const EdgeInsets.fromLTRB(20, 20, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            headingLevel: 2,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// A balance phrase coloured by who owes whom.
class BalanceText extends StatelessWidget {
  const BalanceText(this.balance, {super.key});
  final int balance;

  @override
  Widget build(BuildContext context) => Text(
    balancePhrase(balance),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.forSign(balance.sign),
      fontFeatures: tabular,
    ),
  );
}

/// A money figure for the end of a row. It shrinks rather than crowding out
/// the row's title at large text sizes.
class TrailingAmount extends StatelessWidget {
  const TrailingAmount(this.text, {super.key, this.sign});
  final String text;

  /// Colours the figure by who owes whom; null keeps the normal colour.
  final int? sign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.35,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: tabular,
            color: sign == null ? null : theme.colorScheme.forSign(sign!),
          ),
        ),
      ),
    );
  }
}

/// Expenses and payments, newest first, as tappable rows that open the
/// record for editing. A sliver, so long histories only build what shows.
class ActivityList extends StatelessWidget {
  const ActivityList({
    super.key,
    required this.store,
    required this.expenses,
    required this.payments,
    this.friendId,
    this.showBill = true,
    this.limit,
  });
  final Store store;
  final Iterable<Expense> expenses;
  final Iterable<Payment> payments;

  /// When set, expense rows show what this friend owes you (+) or you owe
  /// them (−) for each expense.
  final String? friendId;
  final bool showBill;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    // What is still open with this friend on each expense.
    final open = friendId == null
        ? const <String, int>{}
        : store.ledger.expenseBalances(friendId!);
    final rows = [
      for (final e in expenses) (date: e.date, expense: e, payment: null),
      for (final p in payments) (date: p.date, expense: null, payment: p),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final ledger = store.ledger;
    final bills = {for (final b in ledger.bills) b.id: b.name};
    final categories = {for (final c in ledger.categories) c.id: c.name};
    final expenseNames = {for (final e in ledger.expenses) e.id: e.name};
    return SliverList.builder(
      itemCount: limit == null ? rows.length : rows.length.clamp(0, limit!),
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row.expense case final e?) {
          return _expenseTile(
            context,
            e,
            bills[e.billId],
            categories[e.categoryId],
            open[e.id] ?? 0,
          );
        }
        final p = row.payment!;
        return _paymentTile(context, p, bills[p.billId], [
          for (final id in p.settles.keys) ?expenseNames[id],
        ]);
      },
    );
  }

  Widget _expenseTile(
    BuildContext context,
    Expense e,
    String? bill,
    String? category,
    int open,
  ) {
    final ledger = store.ledger;
    final effect = friendId == null ? null : e.owedBy(friendId!);
    // What friends owe you for this expense, or minus what you owe.
    final net = e.payerId == me
        ? e.amount - (e.shares[me] ?? 0)
        : -(e.shares[me] ?? 0);
    return ListTile(
      leading: IconBadge(Icons.receipt_long_outlined),
      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (showBill) bill ?? 'General',
          ?category,
          if (!e.personal)
            e.payerId == me
                ? 'paid by you'
                : 'paid by ${ledger.nameOf(e.payerId)}',
          if (friendId == null && net > 0) 'you lent ${rupees(net)}',
          if (friendId == null && net < 0) 'you borrowed ${rupees(-net)}',
          if (effect != null && effect != 0 && open != effect)
            switch (open) {
              0 => 'settled',
              _ when open.sign == effect.sign => '${rupees(open.abs())} left',
              _ => 'overpaid',
            },
          shortDate(e.date),
        ].join(' · '),
        maxLines: 2,
      ),
      trailing: TrailingAmount(
        effect == null || effect == 0
            ? rupees(e.amount)
            : '${effect > 0 ? '+' : '−'}${rupees(effect.abs())}',
        sign: effect?.sign,
      ),
      onTap: () =>
          startFlow(context, store, ExpenseFlow(store.ledger, existing: e)),
    );
  }

  Widget _paymentTile(
    BuildContext context,
    Payment p,
    String? bill,
    List<String> expenses,
  ) {
    final name = store.ledger.nameOf(p.friendId);
    final sent = p.direction == Direction.sent;
    return ListTile(
      leading: IconBadge(sent ? Icons.north_east : Icons.south_west),
      title: Text(
        sent ? 'You sent $name' : '$name sent you',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (expenses.isNotEmpty) 'for ${names(expenses)}',
          if (showBill && expenses.isEmpty) 'in ${bill ?? 'General'}',
          shortDate(p.date),
        ].join(' · '),
      ),
      trailing: TrailingAmount(rupees(p.amount)),
      onTap: () => startFlow(
        context,
        store,
        PaymentFlow(store.ledger, p.direction, existing: p),
      ),
    );
  }
}

/// An icon on a soft tile, leading a row.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }
}

/// A short message shown where a list has nothing to show yet.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// "Today", "Yesterday", "3 Oct", or "3 Oct 2024" for other years.
String shortDate(DateTime date) {
  final today = DateTime.now();
  if (DateUtils.isSameDay(date, today)) return 'Today';
  if (DateUtils.isSameDay(date, DateUtils.addDaysToDate(today, -1))) {
    return 'Yesterday';
  }
  // A non-breaking space keeps "3 Oct" together when a row wraps.
  final label = '${date.day}\u00A0${monthName(date).substring(0, 3)}';
  return date.year == today.year ? label : '$label\u00A0${date.year}';
}
