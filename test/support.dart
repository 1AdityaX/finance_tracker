import 'package:finance_tracker/data/ledger.dart';
import 'package:finance_tracker/data/store.dart';

final day = DateTime(2026, 10, 1);

const rahul = Friend(id: 'rahul', name: 'Rahul');
const priya = Friend(id: 'priya', name: 'Priya');

final goa = Bill(id: 'goa', name: 'Goa trip', created: day);

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
);

Payment payment({
  String id = 'p1',
  String friendId = 'rahul',
  Direction direction = Direction.received,
  int amount = 20000,
  String billId = generalBill,
  String? expenseId,
}) => Payment(
  id: id,
  friendId: friendId,
  direction: direction,
  amount: amount,
  billId: billId,
  expenseId: expenseId,
  date: day.add(const Duration(hours: 1)),
);

/// A ledger with Rahul and Priya, a Goa trip bill, and the given records.
Ledger ledgerWith({
  List<Expense> expenses = const [],
  List<Payment> payments = const [],
}) => Ledger(
  friends: const [rahul, priya],
  bills: [...Ledger.empty.bills, goa],
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
