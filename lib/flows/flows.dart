import '../data/ledger.dart';
import '../data/money.dart';
import '../data/spending.dart';
import 'ask.dart';

export 'ask.dart';

/// A line on a flow's review card.
class Line {
  const Line(this.label, this.value, {this.detail, this.sign = 0});
  final String label;
  final String value;
  final String? detail;

  /// Colours [value]: positive when someone owes you, negative when you owe.
  final int sign;
}

/// A guided command: questions asked one at a time, then a review and save.
///
/// A flow is plain Dart: it builds its [asks] from earlier answers and turns
/// the answers into a new [Ledger] in [save]. `FlowScreen` renders it.
abstract class CommandFlow {
  CommandFlow(this.ledger);

  /// The ledger when the flow started.
  final Ledger ledger;

  /// The app bar title, e.g. "New expense".
  String get title;

  /// The questions still relevant to the answers so far, in order.
  List<Ask> get asks;

  /// Questions already answered from where the flow was started, which the
  /// flow skips.
  Set<Ask> get preset => const {};

  /// True when changing an existing record; the flow opens on its review.
  bool get editing => false;

  /// When the record happened, for flows that keep a date. The review card
  /// shows it, and tapping it picks another day.
  DateTime? date;

  /// Whether the flow ends on a review card. Flows without one save straight
  /// from their last question.
  bool get hasReview => true;

  /// The review card's heading and amount. Read only once every ask is valid.
  ({String title, int amount}) get heading =>
      throw UnsupportedError('$runtimeType has no review');

  /// The review card's lines, in sections. Read only once every ask is valid.
  List<List<Line>> get review => const [];

  String get saveLabel;

  /// Applies the answers to [onto], normally the store's current ledger, or
  /// to the [ledger] the flow started from. Building on the current ledger
  /// keeps anything saved while the flow was open.
  Ledger save([Ledger? onto]);

  /// Shown after saving, and used as the undo label.
  String get savedMessage;

  /// Removes the record being edited from [onto], if the flow edits one.
  ({Ledger ledger, String message})? delete([Ledger? onto]) => null;
}

/// A single-question flow that names something: a bill or a friend.
abstract class _NameFlow extends CommandFlow {
  _NameFlow(super.ledger);
  late final TextAsk name;

  @override
  List<Ask> get asks => [name];

  @override
  bool get hasReview => false;
}

class BillFlow extends _NameFlow {
  BillFlow(super.ledger, {this.existing}) {
    name = TextAsk(
      'What should the bill be called?',
      hint: 'A bill groups expenses, like a trip or a night out.',
      placeholder: 'Goa trip',
      text: existing?.name ?? '',
      taken: (text) =>
          Ledger.nameTaken(
            ledger.bills.map((b) => (id: b.id, name: b.name)),
            text,
            except: existing?.id,
          )
          ? 'You already have a bill called “$text”.'
          : null,
    );
  }
  final Bill? existing;

  /// The id the bill is saved under, so the app can open it afterwards.
  late final String id = existing?.id ?? newId();

  @override
  String get title => existing == null ? 'New bill' : 'Rename bill';

  @override
  String get saveLabel => existing == null ? 'Create bill' : 'Save name';

  @override
  String get savedMessage => existing == null
      ? '“${name.phrase}” created'
      : 'Renamed to “${name.phrase}”';

  @override
  Ledger save([Ledger? onto]) => (onto ?? ledger).put(
    bill: Bill(
      id: id,
      name: name.phrase,
      created: existing?.created ?? DateTime.now(),
    ),
  );
}

class FriendFlow extends _NameFlow {
  FriendFlow(super.ledger, {this.existing}) {
    name = TextAsk(
      'What’s your friend’s name?',
      hint: 'Only you see this. Friends don’t need the app.',
      placeholder: 'Rahul',
      text: existing?.name ?? '',
      taken: (text) =>
          Ledger.nameTaken(
            ledger.friends.map((f) => (id: f.id, name: f.name)),
            text,
            except: existing?.id,
          )
          ? 'You already have a friend called “$text”.'
          : null,
    );
  }
  final Friend? existing;

  @override
  String get title => existing == null ? 'New friend' : 'Rename friend';

  @override
  String get saveLabel => existing == null ? 'Add friend' : 'Save name';

  @override
  String get savedMessage =>
      existing == null ? '${name.phrase} added' : 'Renamed to ${name.phrase}';

  @override
  Ledger save([Ledger? onto]) => (onto ?? ledger).put(
    friend: Friend(id: existing?.id ?? newId(), name: name.phrase),
  );
}

class CategoryFlow extends _NameFlow {
  CategoryFlow(super.ledger, {this.existing}) {
    name = TextAsk(
      'What should the category be called?',
      hint:
          'Like Food, Rent or Travel. Give expenses a category to see where '
          'your money goes.',
      placeholder: 'Food',
      text: existing?.name ?? '',
      taken: (text) => text.toLowerCase() == noCategory.toLowerCase()
          ? '“$noCategory” is for expenses without one.'
          : Ledger.nameTaken(
              ledger.categories.map((c) => (id: c.id, name: c.name)),
              text,
              except: existing?.id,
            )
          ? 'You already have a category called “$text”.'
          : null,
    );
  }
  final Category? existing;

  /// What expenses without a category are listed under.
  static const noCategory = 'No category';

  @override
  String get title => existing == null ? 'New category' : 'Rename category';

  @override
  String get saveLabel => existing == null ? 'Add category' : 'Save name';

  @override
  String get savedMessage => existing == null
      ? '“${name.phrase}” added'
      : 'Renamed to “${name.phrase}”';

  @override
  Ledger save([Ledger? onto]) => (onto ?? ledger).put(
    category: Category(id: existing?.id ?? newId(), name: name.phrase),
  );
}

/// Friends, bills and categories typed into a picker are created when the
/// flow saves, so cancelling leaves nothing behind and one undo removes
/// everything.
mixin _Creates on CommandFlow {
  final _newFriends = <Friend>[];
  final _newBills = <Bill>[];
  final _newCategories = <Category>[];

  List<Friend> get friends => [...ledger.recentFriends, ..._newFriends];
  List<Bill> get bills => [...ledger.billsInOrder, ..._newBills];
  List<Category> get categories => [
    ...ledger.recentCategories,
    ..._newCategories,
  ];

  late final friendCreator = Creator(
    placeholder: 'Search or add a friend',
    label: (name) => 'Add “$name” as a friend',
    create: (name) {
      final friend = Friend(id: newId(), name: name);
      _newFriends.add(friend);
      return friend.id;
    },
  );

  late final billCreator = Creator(
    placeholder: 'Search or start a new bill',
    label: (name) => 'New bill “$name”',
    create: (name) {
      final bill = Bill(id: newId(), name: name, created: DateTime.now());
      _newBills.add(bill);
      return bill.id;
    },
  );

  late final categoryCreator = Creator(
    placeholder: 'Search or add a category',
    label: (name) => 'New category “$name”',
    create: (name) {
      final category = Category(id: newId(), name: name);
      _newCategories.add(category);
      return category.id;
    },
  );

  /// [onto] plus the new friends, bills and categories that [used] refers to.
  Ledger withCreated(Ledger onto, bool Function(String id) used) {
    var next = onto;
    for (final friend in _newFriends.where((f) => used(f.id))) {
      next = next.put(friend: friend);
    }
    for (final bill in _newBills.where((b) => used(b.id))) {
      next = next.put(bill: bill);
    }
    for (final category in _newCategories.where((c) => used(c.id))) {
      next = next.put(category: category);
    }
    return next;
  }

  String nameOf(String id) =>
      _newFriends.where((f) => f.id == id).firstOrNull?.name ??
      ledger.nameOf(id);
}

class ExpenseFlow extends CommandFlow with _Creates {
  ExpenseFlow(super.ledger, {this.existing, String? billId}) {
    final e = existing;
    name = TextAsk(
      'What was it for?',
      placeholder: 'Dinner',
      text: e?.name ?? '',
    );
    category = PickAsk(
      'Which category is it?',
      hint: 'Categories show where your money goes. Type a name to add one.',
      choices: () => [
        for (final c in categories) Choice(c.id, c.name),
        const Choice('', CategoryFlow.noCategory),
      ],
      describe: (c) => c.id.isEmpty ? 'no category' : c.label,
      selected: e?.categoryId ?? '',
      creator: categoryCreator,
    );
    bill = PickAsk(
      'Which bill is it part of?',
      hint: 'Most expenses go in General.',
      choices: () => [for (final b in bills) Choice(b.id, b.name)],
      describe: (c) => 'in ${c.label}',
      selected: e?.billId ?? billId ?? generalBill,
      creator: billCreator,
    );
    amount = AmountAsk(
      'How much did it cost?',
      hint: 'The total that was paid.',
      paise: e?.amount,
    );
    quantity = CountAsk(
      'How many units?',
      hint:
          'Leave it at 1 unless you want to split by quantity, '
          'like 4 pizzas between 3 people.',
      count: e?.quantity ?? 1,
    );
    people = MultiPickAsk(
      'Who shared it with you?',
      hint:
          'Pick everyone involved besides you. Leave it empty if it was '
          'just yours.',
      choices: () => [for (final f in friends) Choice(f.id, f.name)],
      describe: (chosen) => chosen.isEmpty
          ? 'just you'
          : 'with ${names(chosen.map((c) => c.label))}',
      selected: e == null
          ? const []
          : {...e.parts.keys, e.payerId}.where((id) => id != me).toList(),
      creator: friendCreator,
    );
    payer = PickAsk(
      'Who paid?',
      choices: () => [
        const Choice(me, 'You'),
        for (final c in people.chosen) Choice(c.id, c.label),
      ],
      describe: (c) => c.id == me ? 'paid by you' : 'paid by ${c.label}',
      selected: e?.payerId ?? me,
    );
    split = SplitAsk(
      'How do you want to split it?',
      people: () => [me, ...people.chosen.map((c) => c.id)],
      nameOf: nameOf,
      amount: () => amount.paise ?? 0,
      quantity: () => quantity.count,
      from: e,
    );
    date = e?.date ?? DateTime.now();
    // Started from a bill's page, the bill is already known.
    if (billId != null) preset = {bill};
  }

  final Expense? existing;
  late final TextAsk name;
  late final PickAsk category;
  late final PickAsk bill;
  late final AmountAsk amount;
  late final CountAsk quantity;
  late final MultiPickAsk people;
  late final PickAsk payer;
  late final SplitAsk split;

  @override
  Set<Ask> preset = const {};

  @override
  bool get editing => existing != null;

  @override
  String get title => editing ? 'Edit expense' : 'New expense';

  /// Whether anyone shared it. An expense that was just yours has nobody
  /// else who could have paid, and nothing to split.
  bool get _shared => people.chosen.isNotEmpty;

  @override
  List<Ask> get asks => [
    name,
    category,
    bill,
    amount,
    quantity,
    people,
    if (_shared) ...[payer, split],
  ];

  @override
  String get saveLabel => editing ? 'Save changes' : 'Add expense';

  @override
  String get savedMessage =>
      editing ? '“${name.phrase}” updated' : '“${name.phrase}” added';

  Expense get _expense {
    final shared = _shared;
    return Expense(
      id: existing?.id ?? newId(),
      billId: bill.selected!,
      name: name.phrase,
      amount: amount.paise!,
      quantity: quantity.count,
      payerId: shared ? payer.selected! : me,
      split: shared ? split.mode : SplitMode.equal,
      parts: shared ? split.parts! : const {me: 1},
      date: date!,
      categoryId: category.selected!.isEmpty ? null : category.selected,
    );
  }

  @override
  Ledger save([Ledger? onto]) {
    final expense = _expense;
    return withCreated(
      onto ?? ledger,
      (id) =>
          id == expense.billId ||
          id == expense.categoryId ||
          id == expense.payerId ||
          expense.parts.containsKey(id),
    ).put(expense: expense);
  }

  @override
  ({String title, int amount}) get heading =>
      (title: name.phrase, amount: amount.paise!);

  @override
  List<List<Line>> get review {
    final expense = _expense;
    final after = save();
    final shares = expense.shares;
    return [
      // An expense that was just yours costs you all of it, as shown above.
      if (!expense.personal)
        [
          for (final id in expense.parts.keys)
            Line(
              nameOf(id),
              rupees(shares[id]!),
              detail: switch (expense.split) {
                SplitMode.quantity =>
                  '${expense.parts[id]} of ${expense.quantity}',
                SplitMode.percent => '${hundredthsText(expense.parts[id]!)}%',
                SplitMode.equal || SplitMode.exact => null,
              },
            ),
        ],
      [
        // The payer can sit out an equal split and still be owed.
        for (final id in {
          ...expense.parts.keys,
          expense.payerId,
        }.where((id) => id != me))
          if (expense.owedBy(id) case final owed when owed != 0)
            Line(
              owesPhrase(nameOf(id), owed),
              rupees(owed.abs()),
              sign: owed.sign,
              detail: [
                if (editing) ?_settledPhrase(after, id, owed),
                '${editing ? 'Overall' : 'After this'}: '
                    '${balancePhrase(after.balance(id), name: nameOf(id))}',
              ].join(' · '),
            ),
      ],
      if ((shares[me] ?? 0) > 0)
        [
          Line(
            'Spent in ${monthName(expense.date)}',
            rupees(Spending(after, expense.date).total),
            detail: 'Including this',
          ),
        ],
    ];
  }

  /// How much of [owed] has been paid toward this expense, if any.
  String? _settledPhrase(Ledger ledger, String id, int owed) {
    final paid = owed - ledger.balance(id, expenseId: existing!.id);
    if (paid * owed.sign <= 0) return null;
    return paid.abs() >= owed.abs()
        ? 'Paid in full'
        : '${rupees(paid.abs())} paid so far';
  }

  @override
  ({Ledger ledger, String message})? delete([Ledger? onto]) => existing == null
      ? null
      : (
          ledger: (onto ?? ledger).removeExpense(existing!.id),
          message: '“${existing!.name}” deleted',
        );
}

class PaymentFlow extends CommandFlow with _Creates {
  PaymentFlow(super.ledger, this.direction, {this.existing, String? friendId}) {
    final p = existing;
    final sent = direction == Direction.sent;
    amount = AmountAsk(
      sent ? 'How much did you send?' : 'How much did you receive?',
      paise: p?.amount,
    );
    friend = PickAsk(
      sent ? 'Who did you send it to?' : 'Who sent it?',
      choices: () {
        final balances = _base.balances();
        return [
          for (final f in friends)
            Choice(
              f.id,
              f.name,
              detail: balancePhrase(balances[f.id] ?? 0),
              sign: (balances[f.id] ?? 0).sign,
            ),
        ];
      },
      describe: (c) => sent ? 'to ${c.label}' : 'from ${c.label}',
      selected: p?.friendId ?? friendId,
      creator: friendCreator,
    );
    bill = PickAsk(
      'Which bill is it for?',
      hint: 'Use General if it isn’t for a particular bill.',
      choices: () {
        final id = friend.selected;
        return [
          for (final b in bills)
            if (id == null ? 0 : _billBalances(id)[b.id] ?? 0 case final open)
              Choice(
                b.id,
                b.name,
                detail: open == 0 ? null : balancePhrase(open),
                sign: open.sign,
              ),
        ];
      },
      describe: (c) => 'in ${c.label}',
      selected: p?.billId ?? generalBill,
    );
    expense = PickAsk(
      'Which expense is it for?',
      hint: 'Pick one to mark it paid, or leave it for the balance overall.',
      choices: () => [
        for (final (:expense, :open) in _openExpenses)
          Choice(
            expense.id,
            expense.name,
            detail: balancePhrase(open),
            sign: open.sign,
          ),
        const Choice('', 'Not for a particular expense'),
      ],
      describe: (c) => c.id.isEmpty ? 'any expense' : 'for ${c.label}',
      selected: p?.expenseId ?? '',
    );
    date = p?.date ?? DateTime.now();
    if (friendId != null) preset = {friend};
  }

  final Direction direction;
  final Payment? existing;
  late final AmountAsk amount;
  late final PickAsk friend;
  late final PickAsk bill;
  late final PickAsk expense;

  @override
  Set<Ask> preset = const {};

  /// The ledger without the payment being edited, for "before" balances.
  late final Ledger _base = existing == null
      ? ledger
      : ledger.removePayment(existing!.id);

  // Choices are read many times per frame, so balances are worked out once
  // per friend; the base ledger never changes during the flow.
  final _expenseBalances = <String, Map<String, int>>{};
  final _billCache = <String, Map<String, int>>{};

  Map<String, int> _billBalances(String friendId) =>
      _billCache[friendId] ??= _base.billBalances(friendId);

  /// Expenses in the chosen bill that this payment can settle, newest first,
  /// with what is still open on each. The expense a payment being edited is
  /// linked to stays listed even when it is fully paid.
  List<({Expense expense, int open})> get _openExpenses {
    final id = friend.selected;
    if (id == null) return const [];
    final open = _expenseBalances[id] ??= _base.expenseBalances(id);
    final sign = direction == Direction.received ? 1 : -1;
    return [
      for (final e in _base.expenses.reversed)
        if (e.billId == bill.selected &&
            (open[e.id]! * sign > 0 || e.id == existing?.expenseId))
          (expense: e, open: open[e.id]!),
    ];
  }

  @override
  bool get editing => existing != null;

  @override
  String get title => switch ((editing, direction)) {
    (false, Direction.sent) => 'Money sent',
    (false, Direction.received) => 'Money received',
    (true, _) => 'Edit payment',
  };

  @override
  List<Ask> get asks => [amount, friend, bill, expense];

  @override
  String get saveLabel => editing
      ? 'Save changes'
      : direction == Direction.sent
      ? 'Record ${amount.phrase} sent'
      : 'Record ${amount.phrase} received';

  @override
  String get savedMessage {
    if (editing) return 'Payment updated';
    final name = nameOf(friend.selected!);
    return direction == Direction.sent
        ? '${amount.phrase} to $name recorded'
        : '${amount.phrase} from $name recorded';
  }

  Payment get _payment => Payment(
    id: existing?.id ?? newId(),
    friendId: friend.selected!,
    direction: direction,
    amount: amount.paise!,
    billId: bill.selected!,
    expenseId: expense.selected!.isEmpty ? null : expense.selected,
    date: date!,
  );

  @override
  Ledger save([Ledger? onto]) {
    final payment = _payment;
    return withCreated(
      onto ?? ledger,
      (id) => id == payment.friendId,
    ).put(payment: payment);
  }

  @override
  ({String title, int amount}) get heading {
    final name = nameOf(friend.selected!);
    return (
      title: direction == Direction.sent ? 'You sent $name' : '$name sent you',
      amount: amount.paise!,
    );
  }

  @override
  List<List<Line>> get review {
    final id = friend.selected!;
    final name = nameOf(id);
    final before = _base.balance(id);
    final after = save().balance(id);
    return [
      [
        Line('Before', balancePhrase(before, name: name), sign: before.sign),
        Line('After', balancePhrase(after, name: name), sign: after.sign),
      ],
    ];
  }

  @override
  ({Ledger ledger, String message})? delete([Ledger? onto]) => existing == null
      ? null
      : (
          ledger: (onto ?? ledger).removePayment(existing!.id),
          message: 'Payment deleted',
        );
}

/// "Rahul", "Rahul and Priya", "Rahul, Priya and 2 others".
String names(Iterable<String> all) {
  final list = all.toList();
  return switch (list.length) {
    0 => 'nobody',
    1 => list.single,
    2 => '${list[0]} and ${list[1]}',
    3 => '${list[0]}, ${list[1]} and ${list[2]}',
    _ => '${list[0]}, ${list[1]} and ${list.length - 2} others',
  };
}
