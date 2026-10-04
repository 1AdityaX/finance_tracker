import 'ledger.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "October".
String monthName(DateTime date) => _monthNames[date.month - 1];

/// What was spent in one category or bill, by its id.
typedef Total = ({String id, int amount});

/// What you spent in one calendar month: your share of each expense dated in
/// it, whether you split it with friends or it was just yours. Money you
/// paid for friends isn't spending; it's what they owe you.
class Spending {
  Spending(this.ledger, DateTime month, {this.throughDay})
    : month = DateTime(month.year, month.month);

  final Ledger ledger;

  /// The first day of the month.
  final DateTime month;

  /// When set, only days up to and including this one count, to compare the
  /// month so far with the same days of another month.
  final int? throughDay;

  /// Each expense you had a share in, biggest share first.
  late final List<({Expense expense, int share})> items =
      [
        for (final e in ledger.expenses)
          if (_counts(e.date) && (e.shares[me] ?? 0) > 0)
            (expense: e, share: e.shares[me]!),
      ]..sort((a, b) {
        final bySize = b.share.compareTo(a.share);
        return bySize != 0 ? bySize : b.expense.date.compareTo(a.expense.date);
      });

  late final int total = items.fold(0, (sum, i) => sum + i.share);

  /// What you spent in each category, biggest first. Expenses with no
  /// category come last, under the id ''.
  late final List<Total> byCategory = _group(
    (e) => ledger.category(e.categoryId)?.id ?? '',
    (id) => id.isEmpty ? null : ledger.category(id)!.name,
  );

  /// What you spent in each bill, biggest first.
  late final List<Total> byBill = _group(
    (e) => e.billId,
    (id) => ledger.bill(id)?.name,
  );

  bool _counts(DateTime date) =>
      date.year == month.year &&
      date.month == month.month &&
      (throughDay == null || date.day <= throughDay!);

  /// Totals by [key], biggest first, ties by name. A group with no name goes
  /// last whatever its size: it isn't one of the others.
  List<Total> _group(
    String Function(Expense e) key,
    String? Function(String id) name,
  ) {
    final totals = <String, int>{};
    for (final i in items) {
      final id = key(i.expense);
      totals[id] = (totals[id] ?? 0) + i.share;
    }
    return [
      for (final MapEntry(:key, :value) in totals.entries)
        (id: key, amount: value),
    ]..sort((a, b) {
      final (na, nb) = (name(a.id), name(b.id));
      if ((na == null) != (nb == null)) return na == null ? 1 : -1;
      final bySize = b.amount.compareTo(a.amount);
      if (bySize != 0) return bySize;
      return (na ?? '').toLowerCase().compareTo((nb ?? '').toLowerCase());
    });
  }
}
