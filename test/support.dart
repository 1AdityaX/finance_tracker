import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/store.dart';

final day = DateTime(2026, 10, 1);

const rahul = Friend(id: 'rahul', name: 'Rahul');
const priya = Friend(id: 'priya', name: 'Priya');

final goa = Bill(id: 'goa', name: 'Goa trip', created: day);

const travel = Category(id: 'travel', name: 'Travel');
const rent = Category(id: 'rent', name: 'Rent');

Expense expense({
  String id = 'e1',
  String billId = generalBill,
  String name = 'Dinner',
  int amount = 120000,
  int quantity = 1,
  String payerId = me,
  SplitMode split = SplitMode.equal,
  Map<String, int>? parts,
  DateTime? date,
  String? categoryId,
}) => Expense(
  id: id,
  billId: billId,
  name: name,
  amount: amount,
  quantity: quantity,
  payerId: payerId,
  split: split,
  parts: parts ?? {me: 1, 'rahul': 1},
  date: date ?? day,
  categoryId: categoryId,
);

/// A payment, wholly toward [expenseId] when given, or as [settles] says.
Payment payment({
  String id = 'p1',
  String friendId = 'rahul',
  Direction direction = Direction.received,
  int amount = 20000,
  String billId = generalBill,
  String? expenseId,
  Map<String, int>? settles,
}) => Payment(
  id: id,
  friendId: friendId,
  direction: direction,
  amount: amount,
  billId: billId,
  settles: settles ?? {?expenseId: amount},
  date: day.add(const Duration(hours: 1)),
);

/// A ledger with Rahul and Priya, a Goa trip bill, Travel and Rent
/// categories, and the given records.
Ledger ledgerWith({
  List<Expense> expenses = const [],
  List<Payment> payments = const [],
}) => Ledger(
  friends: const [rahul, priya],
  bills: [...Ledger.empty.bills, goa],
  categories: const [travel, rent],
  expenses: expenses,
  payments: payments,
);

/// Keeps the saved ledger in memory.
class MemoryStorage implements Storage {
  MemoryStorage([this.json]);
  String? json;

  @override
  Future<String?> read() async => json;

  @override
  Future<void> write(String json) async => this.json = json;
}
