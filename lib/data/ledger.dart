import 'money.dart';

/// The person id of the device owner.
const me = 'me';

/// The id of the built-in bill that every expense and payment defaults to.
const generalBill = 'general';

var _sequence = 0;

/// A unique, roughly time-ordered id for a new record.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_sequence++).toRadixString(36)}';

class Friend {
  const Friend({required this.id, required this.name});
  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
  factory Friend.fromJson(Map<String, Object?> json) =>
      Friend(id: json['id']! as String, name: json['name']! as String);
}

/// A named group of expenses, such as a trip or a dinner.
class Bill {
  const Bill({required this.id, required this.name, required this.created});
  final String id;
  final String name;
  final DateTime created;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created': created.toIso8601String(),
  };
  factory Bill.fromJson(Map<String, Object?> json) => Bill(
    id: json['id']! as String,
    name: json['name']! as String,
    created: DateTime.parse(json['created']! as String),
  );
}

/// A kind of spending, like Food or Rent. Users make their own.
class Category {
  const Category({required this.id, required this.name, this.counted = true});
  final String id;
  final String name;

  /// Whether its expenses count in your spending. Off for big costs someone
  /// else gave you the money for, like college fees, so they don't swamp
  /// what you spend day to day.
  final bool counted;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (!counted) 'counted': false,
  };
  factory Category.fromJson(Map<String, Object?> json) => Category(
    id: json['id']! as String,
    name: json['name']! as String,
    counted: json['counted'] as bool? ?? true,
  );
}

/// Money you got that nobody owes back, like pocket money or a gift.
/// Unlike a payment, it never changes anyone's balance.
class Income {
  const Income({
    required this.id,
    required this.from,
    required this.amount,
    required this.date,
    this.note,
  });
  final String id;

  /// Who gave it, as typed: "Mom", or a friend's name.
  final String from;

  /// In paise.
  final int amount;
  final DateTime date;

  /// What it's for, like "College fees".
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'from': from,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': ?note,
  };
  factory Income.fromJson(Map<String, Object?> json) => Income(
    id: json['id']! as String,
    from: json['from']! as String,
    amount: json['amount']! as int,
    date: DateTime.parse(json['date']! as String),
    note: json['note'] as String?,
  );
}

/// How an expense is divided between the people in it.
enum SplitMode {
  /// Everyone pays the same.
  equal,

  /// Parts are units out of [Expense.quantity].
  quantity,

  /// Parts are basis points: 100% is 10000.
  percent,

  /// Parts are paise and add up to [Expense.amount].
  exact,
}

/// What each person's part costs, in paise, for an expense of [amount].
Map<String, int> sharesOf(
  SplitMode split,
  int amount,
  Map<String, int> parts,
) => switch (split) {
  SplitMode.exact => parts,
  SplitMode.equal => apportion(amount, {for (final id in parts.keys) id: 1}),
  SplitMode.quantity || SplitMode.percent => apportion(amount, parts),
};

class Expense {
  Expense({
    required this.id,
    required this.billId,
    required this.name,
    required this.amount,
    required this.quantity,
    required this.payerId,
    required this.split,
    required this.parts,
    required this.date,
    this.categoryId,
  });
  final String id;
  final String billId;
  final String name;

  /// The total paid, in paise.
  final int amount;
  final int quantity;

  /// [me] or a friend id.
  final String payerId;
  final SplitMode split;

  /// Everyone in the expense, mapped to their part as described by [split].
  final Map<String, int> parts;
  final DateTime date;
  final String? categoryId;

  /// Just yours: you paid and nobody shared it.
  bool get personal => payerId == me && parts.keys.every((id) => id == me);

  /// What each person's part costs, in paise. Always adds up to [amount].
  late final Map<String, int> shares = sharesOf(split, amount, parts);

  /// What [friendId] owes you for this expense, in paise.
  ///
  /// Negative when you owe them. Zero when neither of you paid.
  int owedBy(String friendId) {
    if (payerId == me) return shares[friendId] ?? 0;
    if (payerId == friendId) return -(shares[me] ?? 0);
    return 0;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'bill': billId,
    'name': name,
    'amount': amount,
    'quantity': quantity,
    'payer': payerId,
    'split': split.name,
    'parts': parts,
    'date': date.toIso8601String(),
    'category': ?categoryId,
  };
  factory Expense.fromJson(Map<String, Object?> json) => Expense(
    id: json['id']! as String,
    billId: json['bill']! as String,
    name: json['name']! as String,
    amount: json['amount']! as int,
    quantity: json['quantity']! as int,
    payerId: json['payer']! as String,
    split: SplitMode.values.byName(json['split']! as String),
    parts: (json['parts']! as Map).cast<String, int>(),
    date: DateTime.parse(json['date']! as String),
    categoryId: json['category'] as String?,
  );
}

enum Direction { sent, received }

/// Money you sent a friend or received from one.
class Payment {
  const Payment({
    required this.id,
    required this.friendId,
    required this.direction,
    required this.amount,
    required this.billId,
    this.settles = const {},
    required this.date,
  });
  final String id;
  final String friendId;
  final Direction direction;
  final int amount;
  final String billId;

  /// The expenses this payment pays toward, in the order they were picked,
  /// with how much of [amount] goes to each, in paise. The rest counts
  /// toward the balance overall.
  final Map<String, int> settles;
  final DateTime date;

  /// How this payment moves what the friend owes you.
  ///
  /// Money received means they owe less. Money sent means you owe less.
  int get effect => direction == Direction.received ? -amount : amount;

  /// The part of [amount] not put toward any expense.
  int get unassigned =>
      settles.values.fold(amount, (left, part) => left - part);

  Map<String, Object?> toJson() => {
    'id': id,
    'friend': friendId,
    'direction': direction.name,
    'amount': amount,
    'bill': billId,
    'settles': settles,
    'date': date.toIso8601String(),
  };
  factory Payment.fromJson(Map<String, Object?> json) => Payment(
    id: json['id']! as String,
    friendId: json['friend']! as String,
    direction: Direction.values.byName(json['direction']! as String),
    amount: json['amount']! as int,
    billId: json['bill']! as String,
    settles: switch (json) {
      {'settles': final Map<Object?, Object?> settles} =>
        settles.cast<String, int>(),
      // Until version 4, a payment went wholly to the one expense it named.
      {'expense': final String expense} => {expense: json['amount']! as int},
      _ => const {},
    },
    date: DateTime.parse(json['date']! as String),
  );
}

/// Every record on the device. Immutable: changes return a new ledger.
class Ledger {
  const Ledger({
    required this.friends,
    required this.bills,
    required this.expenses,
    required this.payments,
    this.categories = const [],
    this.incomes = const [],
  });

  static final empty = Ledger(
    friends: const [],
    bills: [Bill(id: generalBill, name: 'General', created: DateTime(2000))],
    expenses: const [],
    payments: const [],
  );

  final List<Friend> friends;

  /// Always contains the General bill first.
  final List<Bill> bills;
  final List<Expense> expenses;
  final List<Payment> payments;
  final List<Category> categories;
  final List<Income> incomes;

  Friend? friend(String id) => friends.where((f) => f.id == id).firstOrNull;
  Bill? bill(String id) => bills.where((b) => b.id == id).firstOrNull;
  Expense? expense(String id) => expenses.where((e) => e.id == id).firstOrNull;
  Payment? payment(String id) => payments.where((p) => p.id == id).firstOrNull;
  Category? category(String? id) =>
      categories.where((c) => c.id == id).firstOrNull;
  Income? income(String id) => incomes.where((i) => i.id == id).firstOrNull;

  /// Who you've had money from, most recent first.
  List<String> get incomeSources => {
    for (final i in incomes.toList()..sort((a, b) => b.date.compareTo(a.date)))
      i.from,
  }.toList();

  /// "You" for the device owner, otherwise the friend's name.
  String nameOf(String personId) =>
      personId == me ? 'You' : friend(personId)?.name ?? 'Removed friend';

  /// What [friendId] owes you in paise; negative when you owe them.
  ///
  /// Narrow it to one bill or one expense with [billId] or [expenseId].
  int balance(String friendId, {String? billId, String? expenseId}) {
    var total = 0;
    for (final e in expenses) {
      if ((billId == null || e.billId == billId) &&
          (expenseId == null || e.id == expenseId)) {
        total += e.owedBy(friendId);
      }
    }
    final billOf = _billOf;
    for (final p in payments.where((p) => p.friendId == friendId)) {
      for (final part in _parts(p, billOf)) {
        if ((billId == null || part.billId == billId) &&
            (expenseId == null || part.expenseId == expenseId)) {
          total += part.effect;
        }
      }
    }
    return total;
  }

  /// Every friend's balance at once, in one pass over the records. Friends
  /// with nothing recorded are missing; read them as zero.
  ///
  /// Narrow it to one bill with [billId].
  Map<String, int> balances({String? billId}) {
    final totals = <String, int>{};
    void add(String id, int amount) => totals[id] = (totals[id] ?? 0) + amount;
    for (final e in expenses) {
      if (billId != null && e.billId != billId) continue;
      for (final id in {...e.parts.keys, e.payerId}) {
        if (id != me) add(id, e.owedBy(id));
      }
    }
    final billOf = _billOf;
    for (final p in payments) {
      for (final part in _parts(p, billOf)) {
        if (billId == null || part.billId == billId) {
          add(p.friendId, part.effect);
        }
      }
    }
    return totals;
  }

  /// What [friendId] still owes you on each expense, by expense id, after the
  /// payments linked to it; negative when you owe them. One pass over the
  /// records, for lists of expenses.
  Map<String, int> expenseBalances(String friendId) {
    final open = {for (final e in expenses) e.id: e.owedBy(friendId)};
    for (final p in payments.where((p) => p.friendId == friendId)) {
      for (final MapEntry(key: id, value: part) in p.settles.entries) {
        if (open[id] case final left?) open[id] = left + part * p.effect.sign;
      }
    }
    return open;
  }

  /// What [friendId] owes you in each bill, by bill id, in one pass.
  Map<String, int> billBalances(String friendId) {
    final totals = <String, int>{};
    for (final e in expenses) {
      totals[e.billId] = (totals[e.billId] ?? 0) + e.owedBy(friendId);
    }
    final billOf = _billOf;
    for (final p in payments.where((p) => p.friendId == friendId)) {
      for (final part in _parts(p, billOf)) {
        totals[part.billId] = (totals[part.billId] ?? 0) + part.effect;
      }
    }
    return totals;
  }

  /// Each expense's bill, by expense id.
  Map<String, String> get _billOf => {for (final e in expenses) e.id: e.billId};

  /// How [p] moves balances, piece by piece: what it put toward each
  /// expense counts in that expense's bill, and the rest in the payment's
  /// own bill. Signed like [Payment.effect].
  static Iterable<({String billId, String? expenseId, int effect})> _parts(
    Payment p,
    Map<String, String> billOf,
  ) sync* {
    final sign = p.effect.sign;
    for (final MapEntry(key: id, value: part) in p.settles.entries) {
      yield (
        billId: billOf[id] ?? p.billId,
        expenseId: id,
        effect: part * sign,
      );
    }
    if (p.unassigned != 0) {
      yield (billId: p.billId, expenseId: null, effect: p.unassigned * sign);
    }
  }

  /// Friends you dealt with most recently first, then the rest by name.
  List<Friend> get recentFriends {
    final last = <String, DateTime>{};
    void touch(String id, DateTime date) {
      if (last[id] == null || date.isAfter(last[id]!)) last[id] = date;
    }

    for (final e in expenses) {
      for (final id in {...e.parts.keys, e.payerId}) {
        touch(id, e.date);
      }
    }
    for (final p in payments) {
      touch(p.friendId, p.date);
    }
    return _recentFirst(friends, last, (f) => (id: f.id, name: f.name));
  }

  /// Categories used most recently first, then the rest by name.
  List<Category> get recentCategories {
    final last = <String, DateTime>{};
    for (final e in expenses) {
      final id = e.categoryId;
      if (id != null && (last[id] == null || e.date.isAfter(last[id]!))) {
        last[id] = e.date;
      }
    }
    return _recentFirst(categories, last, (c) => (id: c.id, name: c.name));
  }

  /// [items] by their date in [last], newest first, then the rest by name.
  static List<T> _recentFirst<T>(
    List<T> items,
    Map<String, DateTime> last,
    ({String id, String name}) Function(T) key,
  ) => items.toList()
    ..sort((a, b) {
      final (ka, kb) = (key(a), key(b));
      final (da, db) = (last[ka.id], last[kb.id]);
      if (da != db) {
        if (da == null || db == null) return da == null ? 1 : -1;
        return db.compareTo(da);
      }
      return ka.name.toLowerCase().compareTo(kb.name.toLowerCase());
    });

  /// General first, then the newest bills.
  List<Bill> get billsInOrder => [
    ...bills.where((b) => b.id == generalBill),
    ...bills.where((b) => b.id != generalBill).toList()
      ..sort((a, b) => b.created.compareTo(a.created)),
  ];

  /// Whether some other record in [records] already uses [name], ignoring
  /// case. Names identify friends, bills and categories to the user, so they
  /// stay unique.
  static bool nameTaken(
    Iterable<({String id, String name})> records,
    String name, {
    String? except,
  }) => records.any(
    (r) => r.id != except && r.name.toLowerCase() == name.toLowerCase(),
  );

  /// Whether any expense or payment mentions [friendId].
  bool involves(String friendId) =>
      expenses.any(
        (e) => e.payerId == friendId || e.parts.containsKey(friendId),
      ) ||
      payments.any((p) => p.friendId == friendId);

  /// Adds or replaces records by id. A payment that went wholly to expenses
  /// that are now all in another bill follows them there, so it is listed
  /// where its money counts. (Money put toward an expense always counts in
  /// that expense's bill; any rest stays in the payment's.)
  Ledger put({
    Friend? friend,
    Bill? bill,
    Category? category,
    Expense? expense,
    Payment? payment,
    Income? income,
  }) {
    var next = _put(payments, payment, (p) => p.id);
    final old = expenses.where((e) => e.id == expense?.id).firstOrNull;
    if (expense != null && old != null && old.billId != expense.billId) {
      final billOf = {..._billOf, expense.id: expense.billId};
      next = [
        for (final p in next)
          p.billId == old.billId &&
                  p.unassigned == 0 &&
                  p.settles.containsKey(expense.id) &&
                  p.settles.keys.every((id) => billOf[id] == expense.billId)
              ? _relink(p, billId: expense.billId)
              : p,
      ];
    }
    return Ledger(
      friends: _put(friends, friend, (f) => f.id),
      bills: _put(bills, bill, (b) => b.id),
      expenses: _put(expenses, expense, (e) => e.id),
      payments: next,
      categories: _put(categories, category, (c) => c.id),
      incomes: _put(incomes, income, (i) => i.id),
    );
  }

  Ledger removeFriend(String id) =>
      _copy(friends: friends.where((f) => f.id != id).toList());

  /// Removes a bill and its expenses. Its payments still count, under General.
  Ledger removeBill(String id) {
    assert(id != generalBill, 'The General bill cannot be removed.');
    final gone = {
      for (final e in expenses)
        if (e.billId == id) e.id,
    };
    return _copy(
      bills: bills.where((b) => b.id != id).toList(),
      expenses: expenses.where((e) => e.billId != id).toList(),
      payments: [
        for (final p in payments)
          p.billId == id || p.settles.keys.any(gone.contains)
              ? _relink(
                  p,
                  billId: p.billId == id ? generalBill : p.billId,
                  drop: gone,
                )
              : p,
      ],
    );
  }

  /// Removes an expense. Payments made for it still count toward the balance.
  Ledger removeExpense(String id) => _copy(
    expenses: expenses.where((e) => e.id != id).toList(),
    payments: [
      for (final p in payments)
        p.settles.containsKey(id)
            ? _relink(p, billId: p.billId, drop: {id})
            : p,
    ],
  );

  Ledger removePayment(String id) =>
      _copy(payments: payments.where((p) => p.id != id).toList());

  /// Removes a category. Its expenses stay, with no category.
  Ledger removeCategory(String id) => _copy(
    categories: categories.where((c) => c.id != id).toList(),
    expenses: [
      for (final e in expenses)
        e.categoryId == id
            ? Expense(
                id: e.id,
                billId: e.billId,
                name: e.name,
                amount: e.amount,
                quantity: e.quantity,
                payerId: e.payerId,
                split: e.split,
                parts: e.parts,
                date: e.date,
              )
            : e,
    ],
  );

  Ledger removeIncome(String id) =>
      _copy(incomes: incomes.where((i) => i.id != id).toList());

  Ledger _copy({
    List<Friend>? friends,
    List<Bill>? bills,
    List<Expense>? expenses,
    List<Payment>? payments,
    List<Category>? categories,
    List<Income>? incomes,
  }) => Ledger(
    friends: friends ?? this.friends,
    bills: bills ?? this.bills,
    expenses: expenses ?? this.expenses,
    payments: payments ?? this.payments,
    categories: categories ?? this.categories,
    incomes: incomes ?? this.incomes,
  );

  /// [p] in [billId], no longer paying toward the expenses in [drop].
  static Payment _relink(
    Payment p, {
    required String billId,
    Set<String> drop = const {},
  }) => Payment(
    id: p.id,
    friendId: p.friendId,
    direction: p.direction,
    amount: p.amount,
    billId: billId,
    settles: {
      for (final MapEntry(:key, :value) in p.settles.entries)
        if (!drop.contains(key)) key: value,
    },
    date: p.date,
  );

  /// Replaces the item with the same id, or appends it.
  static List<T> _put<T>(List<T> items, T? item, String Function(T) id) {
    if (item == null) return items;
    final index = items.indexWhere((i) => id(i) == id(item));
    return index < 0
        ? [...items, item]
        : [...items.take(index), item, ...items.skip(index + 1)];
  }

  /// Version 3 added categories, version 4 lets a payment pay toward
  /// several expenses, and version 5 adds money in and categories left out
  /// of spending.
  static const version = 5;

  Map<String, Object?> toJson() => {
    'version': version,
    'friends': [for (final f in friends) f.toJson()],
    'bills': [for (final b in bills) b.toJson()],
    'categories': [for (final c in categories) c.toJson()],
    'expenses': [for (final e in expenses) e.toJson()],
    'payments': [for (final p in payments) p.toJson()],
    'incomes': [for (final i in incomes) i.toJson()],
  };

  factory Ledger.fromJson(Map<String, Object?> json) => Ledger(
    friends: [
      for (final f in json['friends']! as List) Friend.fromJson(_map(f)),
    ],
    bills: [for (final b in json['bills']! as List) Bill.fromJson(_map(b))],
    expenses: [
      for (final e in json['expenses']! as List) Expense.fromJson(_map(e)),
    ],
    payments: [
      for (final p in json['payments']! as List) Payment.fromJson(_map(p)),
    ],
    categories: [
      for (final c in json['categories'] as List? ?? const [])
        Category.fromJson(_map(c)),
    ],
    incomes: [
      for (final i in json['incomes'] as List? ?? const [])
        Income.fromJson(_map(i)),
    ],
  );

  static Map<String, Object?> _map(Object? json) =>
      (json! as Map).cast<String, Object?>();
}
