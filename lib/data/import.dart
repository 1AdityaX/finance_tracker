import 'ledger.dart';
import 'store.dart';

/// A file that can't be imported, with why.
class ImportError implements Exception {
  const ImportError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What importing a file would change, and the ledger after it.
class ImportPreview {
  const ImportPreview({
    required this.ledger,
    required this.expenses,
    required this.payments,
    required this.incomes,
    required this.newFriends,
    required this.newCategories,
    required this.newBills,
    required this.skipped,
    this.from,
    this.to,
  });

  /// The current ledger with the file's records added.
  final Ledger ledger;

  /// How many of each record are new.
  final int expenses;
  final int payments;
  final int incomes;

  /// Names the file brings that weren't in the ledger yet.
  final List<String> newFriends;
  final List<String> newCategories;
  final List<String> newBills;

  /// Records already in the ledger, as from importing the same file twice.
  final int skipped;

  /// The earliest and latest dates among the new records.
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty => expenses + payments + incomes == 0;
}

/// Adds the records in [source], a ledger saved as JSON, to [current].
///
/// Nothing in [current] is changed or removed. Friends, categories and bills
/// are matched to the ones you have by name, ignoring case, so an import
/// never makes a second "Aayush". Expenses, payments and money in already in
/// [current], by id, are skipped, so the same file can be imported twice.
///
/// Throws an [ImportError] if [source] isn't a ledger or doesn't add up.
ImportPreview previewImport(Ledger current, String source) {
  final Ledger incoming;
  try {
    incoming = decodeLedger(source);
  } on Object {
    throw const ImportError('This file isn’t a Between import file.');
  }
  _check(incoming);

  String key(String name) => name.trim().toLowerCase();
  final takenIds = {
    for (final f in current.friends) f.id,
    for (final c in current.categories) c.id,
    for (final b in current.bills) b.id,
    me,
  };
  String freshId(String id) => takenIds.add(id) ? id : newId();

  final friendIds = <String, String>{me: me};
  final friends = [...current.friends];
  final newFriends = <String>[];
  final friendsByName = {for (final f in current.friends) key(f.name): f.id};
  for (final f in incoming.friends) {
    final id = friendsByName[key(f.name)] ??= () {
      final id = freshId(f.id);
      friends.add(Friend(id: id, name: f.name.trim()));
      newFriends.add(f.name.trim());
      return id;
    }();
    friendIds[f.id] = id;
  }

  final categoryIds = <String, String>{};
  final categories = [...current.categories];
  final newCategories = <String>[];
  final categoriesByName = {
    for (final c in current.categories) key(c.name): c.id,
  };
  for (final c in incoming.categories) {
    final id = categoriesByName[key(c.name)] ??= () {
      final id = freshId(c.id);
      categories.add(Category(id: id, name: c.name.trim(), counted: c.counted));
      newCategories.add(c.name.trim());
      return id;
    }();
    categoryIds[c.id] = id;
  }

  final billIds = <String, String>{generalBill: generalBill};
  final bills = [...current.bills];
  final newBills = <String>[];
  final billsByName = {for (final b in current.bills) key(b.name): b.id};
  for (final b in incoming.bills.where((b) => b.id != generalBill)) {
    final id = billsByName[key(b.name)] ??= () {
      final id = freshId(b.id);
      bills.add(Bill(id: id, name: b.name.trim(), created: b.created));
      newBills.add(b.name.trim());
      return id;
    }();
    billIds[b.id] = id;
  }

  var skipped = 0;
  final dates = <DateTime>[];

  final expenses = [...current.expenses];
  final known = {for (final e in current.expenses) e.id};
  for (final e in incoming.expenses) {
    if (!known.add(e.id)) {
      skipped++;
      continue;
    }
    dates.add(e.date);
    expenses.add(
      Expense(
        id: e.id,
        billId: billIds[e.billId]!,
        name: e.name,
        amount: e.amount,
        quantity: e.quantity,
        payerId: friendIds[e.payerId]!,
        split: e.split,
        parts: {
          for (final MapEntry(:key, :value) in e.parts.entries)
            friendIds[key]!: value,
        },
        date: e.date,
        categoryId: e.categoryId == null ? null : categoryIds[e.categoryId],
        items: [
          for (final item in e.items)
            Item(
              name: item.name,
              amount: item.amount,
              people: [for (final id in item.people) friendIds[id]!],
            ),
        ],
      ),
    );
  }

  final payments = [...current.payments];
  final knownPayments = {for (final p in current.payments) p.id};
  for (final p in incoming.payments) {
    if (!knownPayments.add(p.id)) {
      skipped++;
      continue;
    }
    dates.add(p.date);
    payments.add(
      Payment(
        id: p.id,
        friendId: friendIds[p.friendId]!,
        direction: p.direction,
        amount: p.amount,
        billId: billIds[p.billId]!,
        settles: p.settles,
        date: p.date,
      ),
    );
  }

  final incomes = [...current.incomes];
  final knownIncomes = {for (final i in current.incomes) i.id};
  for (final i in incoming.incomes) {
    if (!knownIncomes.add(i.id)) {
      skipped++;
      continue;
    }
    dates.add(i.date);
    incomes.add(i);
  }

  final ledger = Ledger(
    friends: friends,
    bills: bills,
    expenses: expenses,
    payments: payments,
    categories: categories,
    incomes: incomes,
  );
  dates.sort();
  return ImportPreview(
    ledger: ledger,
    expenses: expenses.length - current.expenses.length,
    payments: payments.length - current.payments.length,
    incomes: incomes.length - current.incomes.length,
    newFriends: newFriends,
    newCategories: newCategories,
    newBills: newBills,
    skipped: skipped,
    from: dates.firstOrNull,
    to: dates.lastOrNull,
  );
}

/// Throws an [ImportError] naming the first record in [ledger] that points
/// at something missing or doesn't add up.
void _check(Ledger ledger) {
  final friends = {me, for (final f in ledger.friends) f.id};
  final bills = {generalBill, for (final b in ledger.bills) b.id};
  final categories = {for (final c in ledger.categories) c.id};
  final expenses = {for (final e in ledger.expenses) e.id};

  for (final e in ledger.expenses) {
    final problem = switch (e) {
      _ when e.amount <= 0 => 'has no amount',
      _ when e.parts.isEmpty => 'has nobody in it',
      _ when !friends.contains(e.payerId) => 'was paid by someone unknown',
      _ when !e.parts.keys.every(friends.contains) =>
        'is split with someone unknown',
      _ when e.parts.values.any((part) => part < 0) => 'has a negative part',
      _
          when (e.split == SplitMode.exact || e.split == SplitMode.items) &&
              e.parts.values.fold(0, (sum, part) => sum + part) != e.amount =>
        'has parts that don’t add up to its amount',
      _
          when !e.items.every(
            (i) => i.people.isNotEmpty && i.people.every(e.parts.containsKey),
          ) =>
        'has an item shared with someone not in it',
      _ when !bills.contains(e.billId) => 'is in an unknown group',
      _ when e.categoryId != null && !categories.contains(e.categoryId) =>
        'is in an unknown category',
      _ => null,
    };
    if (problem != null) throw ImportError('The expense “${e.name}” $problem.');
  }

  for (final p in ledger.payments) {
    final problem = switch (p) {
      _ when p.amount <= 0 => 'has no amount',
      _ when !friends.contains(p.friendId) || p.friendId == me =>
        'is with someone unknown',
      _ when !bills.contains(p.billId) => 'is in an unknown group',
      _ when !p.settles.keys.every(expenses.contains) =>
        'pays toward an expense that isn’t in the file',
      _ when p.settles.values.any((part) => part <= 0) || p.unassigned < 0 =>
        'puts more toward expenses than it is for',
      _ => null,
    };
    if (problem != null) {
      throw ImportError('A payment dated ${_day(p.date)} $problem.');
    }
  }

  for (final i in ledger.incomes) {
    if (i.amount <= 0) {
      throw ImportError('Money in from ${i.from} has no amount.');
    }
  }
}

String _day(DateTime date) => '${date.day}/${date.month}/${date.year}';
