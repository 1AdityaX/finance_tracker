import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'ledger.dart';

/// Reads and writes the whole ledger as one JSON document.
abstract interface class Storage {
  Future<String?> read();
  Future<void> write(String json);
}

/// Keeps the ledger in one SQLite row, so every save is a single atomic write.
class SqliteStorage implements Storage {
  SqliteStorage({
    DatabaseFactory? factory,
    this.path,
    this.name = 'shared_expenses.db',
  }) : _factory = factory ?? databaseFactory;
  final DatabaseFactory _factory;

  /// Defaults to [name] in the app's database folder.
  final String? path;
  final String name;

  /// Cached as a future so concurrent first calls open the database once.
  Future<Database>? _db;

  Future<Database> _open() => _db ??= () async {
    return _factory.openDatabase(
      path ?? '${await _factory.getDatabasesPath()}/$name',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE tracker_state '
          '(id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL)',
        ),
      ),
    );
  }();

  @override
  Future<String?> read() async {
    final rows = await (await _open()).query('tracker_state', where: 'id = 1');
    return rows.firstOrNull?['payload'] as String?;
  }

  @override
  Future<void> write(String json) async => (await _open()).insert(
    'tracker_state',
    {'id': 1, 'payload': json},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// The app's single source of truth: the current ledger, saving, and undo.
class Store extends ChangeNotifier {
  Store(this._storage);
  final Storage _storage;
  static const _undoLimit = 50;
  final _undo = <({String label, Ledger before})>[];

  Ledger _ledger = Ledger.empty;
  Ledger get ledger => _ledger;

  bool _loading = true;
  bool get loading => _loading;

  /// Set when saved records could not be read. Nothing is written until a
  /// later [load] succeeds, so the saved data is never replaced.
  Object? get loadError => _loadError;
  Object? _loadError;

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    _undo.clear();
    notifyListeners();
    try {
      final json = await _storage.read();
      _ledger = json == null ? Ledger.empty : decodeLedger(json);
    } catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Reads the ledger again after something other than this store changed
  /// what is saved, such as a sync, without leaving the screen. Undo can't
  /// reach past it.
  Future<void> reload() async {
    final json = await _storage.read();
    _ledger = json == null ? Ledger.empty : decodeLedger(json);
    _undo.clear();
    notifyListeners();
  }

  /// Saves [next] and remembers the current ledger so [undo] can restore it.
  Future<void> save(Ledger next, String label) async {
    await _storage.write(jsonEncode(next.toJson()));
    _undo.add((label: label, before: _ledger));
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _ledger = next;
    notifyListeners();
  }

  /// The label of the change [undo] would revert, if any.
  String? get undoLabel => _undo.lastOrNull?.label;

  /// Reverts the most recent change and returns its label.
  Future<String?> undo() async {
    final last = _undo.lastOrNull;
    if (last == null) return null;
    await _storage.write(jsonEncode(last.before.toJson()));
    _undo.removeLast();
    _ledger = last.before;
    notifyListeners();
    return last.label;
  }
}

/// Parses a saved ledger, upgrading data saved by the first version of the app.
Ledger decodeLedger(String source) {
  final json = (jsonDecode(source) as Map).cast<String, Object?>();
  return switch (json['version']) {
    // Version 2 had no categories; until version 4 a payment named at most
    // one expense. Ledger.fromJson reads both.
    2 || 3 || Ledger.version => Ledger.fromJson(json),
    null when json.containsKey('purchases') => _fromVersion1(json),
    _ => throw const FormatException(
      'These records were saved by a newer version of Between.',
    ),
  };
}

/// Version 1 stored purchases with line items, and payments split into
/// portions per friend. Balances stay exactly as version 1 showed them:
///
/// * A purchase with one item becomes an expense in General; a purchase with
///   several items becomes a bill of expenses.
/// * Items version 1 had not counted yet (proposed or unresolved) go to a
///   "Not split yet" bill, charged wholly to whoever paid, so they keep their
///   record without changing any balance. Edit them to split them.
/// * Each payment portion becomes its own payment, linked to the purchase it
///   settled.
///
/// One rule changes: money received in advance and held for a purchase now
/// counts toward the balance straight away, as all money received does.
Ledger _fromVersion1(Map<String, Object?> json) {
  List<Map<String, Object?>> list(Object? value) => [
    for (final item in value! as List) (item as Map).cast<String, Object?>(),
  ];
  const splits = {
    'equal': SplitMode.equal,
    'quantity': SplitMode.quantity,
    'proportion': SplitMode.percent,
    'exact': SplitMode.exact,
  };
  final friends = [
    for (final p in list(json['people']))
      if (p['id'] != me) Friend.fromJson(p),
  ];
  final bills = Ledger.empty.bills.toList();
  final expenses = <Expense>[];
  const unsplit = 'v1-unsplit';
  for (final purchase in list(json['purchases'])) {
    final items = list(purchase['items']);
    final id = purchase['id']! as String;
    final date = DateTime.parse(purchase['date']! as String);
    final payerId = purchase['payerId']! as String;
    if (items.length > 1) {
      bills.add(
        Bill(id: id, name: purchase['title']! as String, created: date),
      );
    }
    for (final item in items) {
      final assignment = (item['assignment']! as Map).cast<String, Object?>();
      final amount = item['amount']! as int;
      final parts = (assignment['values']! as Map).cast<String, int>();
      final mode = splits[assignment['mode']]!;
      final quantity = item['quantity']! as int;
      final counted = assignment['status'] == 'confirmed';
      if (!counted && !bills.any((b) => b.id == unsplit)) {
        bills.add(Bill(id: unsplit, name: 'Not split yet', created: date));
      }
      final shares = sharesOf(mode, amount, parts);
      // The new model needs the payer among the people in the expense, and
      // splits by quantity only above one unit. Where an item breaks either
      // rule, an exact split of the same shares keeps every amount.
      final keep =
          counted &&
          (payerId == me || parts.containsKey(payerId)) &&
          (mode != SplitMode.quantity || quantity > 1);
      expenses.add(
        Expense(
          id: items.length > 1 ? '$id-${item['id']}' : id,
          billId: !counted
              ? unsplit
              : items.length > 1
              ? id
              : generalBill,
          name:
              (items.length > 1 ? item['name'] : purchase['title'])! as String,
          amount: amount,
          quantity: quantity,
          payerId: payerId,
          split: keep ? mode : SplitMode.exact,
          parts: keep
              ? parts
              : counted
              ? {payerId: 0, ...shares}
              : {payerId: amount},
          date: date,
        ),
      );
    }
  }
  final payments = <Payment>[];
  for (final t in list(json['transfers'])) {
    final portions = (t['portions']! as Map).cast<String, int>();
    for (final MapEntry(key: friendId, value: amount) in portions.entries) {
      final settled = {
        for (final a in list(t['allocations']))
          if (a['personId'] == friendId) a['purchaseId']! as String,
        ?t['reservedPurchaseId'] as String?,
      };
      final purchaseId = settled.length == 1 ? settled.single : null;
      final asBill = bills.any((b) => b.id == purchaseId);
      final asExpense = expenses.any(
        (e) => e.id == purchaseId && e.billId != unsplit,
      );
      payments.add(
        Payment(
          id: portions.length == 1
              ? t['id']! as String
              : '${t['id']}-$friendId',
          friendId: friendId,
          direction: Direction.values.byName(t['direction']! as String),
          amount: amount,
          billId: asBill ? purchaseId! : generalBill,
          settles: asExpense ? {purchaseId!: amount} : const {},
          date: DateTime.parse(t['date']! as String),
        ),
      );
    }
  }
  return Ledger(
    friends: friends,
    bills: bills,
    expenses: expenses,
    payments: payments,
  );
}
