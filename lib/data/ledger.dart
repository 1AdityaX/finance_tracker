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
    required this.expenseId,
    required this.date,
  });
  final String id;
  final String friendId;
  final Direction direction;
  final int amount;
  final String billId;

  /// The expense this payment settles, if the user picked one.
  final String? expenseId;
  final DateTime date;

  /// How this payment moves what the friend owes you.
  ///
  /// Money received means they owe less. Money sent means you owe less.
  int get effect => direction == Direction.received ? -amount : amount;

  Map<String, Object?> toJson() => {
    'id': id,
    'friend': friendId,
    'direction': direction.name,
    'amount': amount,
    'bill': billId,
    'expense': expenseId,
    'date': date.toIso8601String(),
  };
  factory Payment.fromJson(Map<String, Object?> json) => Payment(
    id: json['id']! as String,
    friendId: json['friend']! as String,
    direction: Direction.values.byName(json['direction']! as String),
    amount: json['amount']! as int,
    billId: json['bill']! as String,
    expenseId: json['expense'] as String?,
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

  Friend? friend(String id) => friends.where((f) => f.id == id).firstOrNull;
  Bill? bill(String id) => bills.where((b) => b.id == id).firstOrNull;
  Expense? expense(String id) => expenses.where((e) => e.id == id).firstOrNull;
  Payment? payment(String id) => payments.where((p) => p.id == id).firstOrNull;

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
    for (final p in payments) {
      if (p.friendId == friendId &&
          (billId == null || p.billId == billId) &&
          (expenseId == null || p.expenseId == expenseId)) {
        total += p.effect;
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
    for (final p in payments) {
      if (billId == null || p.billId == billId) add(p.friendId, p.effect);
    }
    return totals;
  }

  /// What [friendId] still owes you on each expense, by expense id, after the
  /// payments linked to it; negative when you owe them. One pass over the
  /// records, for lists of expenses.
  Map<String, int> expenseBalances(String friendId) {
    final open = {for (final e in expenses) e.id: e.owedBy(friendId)};
    for (final p in payments) {
      if (p.friendId == friendId && open.containsKey(p.expenseId)) {
        open[p.expenseId!] = open[p.expenseId]! + p.effect;
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
    for (final p in payments) {
      if (p.friendId == friendId) {
        totals[p.billId] = (totals[p.billId] ?? 0) + p.effect;
      }
    }
    return totals;
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
    return friends.toList()..sort((a, b) {
      final (da, db) = (last[a.id], last[b.id]);
      if (da != db) {
        if (da == null || db == null) return da == null ? 1 : -1;
        return db.compareTo(da);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// General first, then the newest bills.
  List<Bill> get billsInOrder => [
    ...bills.where((b) => b.id == generalBill),
    ...bills.where((b) => b.id != generalBill).toList()
      ..sort((a, b) => b.created.compareTo(a.created)),
  ];

  /// Whether some other record in [records] already uses [name], ignoring
  /// case. Names identify friends and bills to the user, so they stay unique.
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

  /// Adds or replaces records by id. Payments for an expense follow it when
  /// it moves to another bill, so per-bill balances stay right.
  Ledger put({Friend? friend, Bill? bill, Expense? expense, Payment? payment}) {
    var next = _put(payments, payment, (p) => p.id);
    if (expense != null) {
      next = [
        for (final p in next)
          p.expenseId == expense.id && p.billId != expense.billId
              ? _relink(p, billId: expense.billId, expenseId: expense.id)
              : p,
      ];
    }
    return Ledger(
      friends: _put(friends, friend, (f) => f.id),
      bills: _put(bills, bill, (b) => b.id),
      expenses: _put(expenses, expense, (e) => e.id),
      payments: next,
    );
  }

  Ledger removeFriend(String id) =>
      _copy(friends: friends.where((f) => f.id != id).toList());

  /// Removes a bill and its expenses. Its payments still count, under General.
  Ledger removeBill(String id) {
    assert(id != generalBill, 'The General bill cannot be removed.');
    return _copy(
      bills: bills.where((b) => b.id != id).toList(),
      expenses: expenses.where((e) => e.billId != id).toList(),
      payments: [
        for (final p in payments)
          p.billId == id ? _relink(p, billId: generalBill) : p,
      ],
    );
  }

  /// Removes an expense. Payments made for it still count toward the balance.
  Ledger removeExpense(String id) => _copy(
    expenses: expenses.where((e) => e.id != id).toList(),
    payments: [
      for (final p in payments)
        p.expenseId == id ? _relink(p, billId: p.billId) : p,
    ],
  );

  Ledger removePayment(String id) =>
      _copy(payments: payments.where((p) => p.id != id).toList());

  Ledger _copy({
    List<Friend>? friends,
    List<Bill>? bills,
    List<Expense>? expenses,
    List<Payment>? payments,
  }) => Ledger(
    friends: friends ?? this.friends,
    bills: bills ?? this.bills,
    expenses: expenses ?? this.expenses,
    payments: payments ?? this.payments,
  );

  static Payment _relink(
    Payment p, {
    required String billId,
    String? expenseId,
  }) => Payment(
    id: p.id,
    friendId: p.friendId,
    direction: p.direction,
    amount: p.amount,
    billId: billId,
    expenseId: expenseId,
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

  static const version = 2;

  Map<String, Object?> toJson() => {
    'version': version,
    'friends': [for (final f in friends) f.toJson()],
    'bills': [for (final b in bills) b.toJson()],
    'expenses': [for (final e in expenses) e.toJson()],
    'payments': [for (final p in payments) p.toJson()],
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
  );

  static Map<String, Object?> _map(Object? json) =>
      (json! as Map).cast<String, Object?>();
}
