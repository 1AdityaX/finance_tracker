import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../data/spending.dart';
import '../data/store.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'bill_screen.dart';
import 'friend_screen.dart';
import 'spending_screen.dart';
import 'widgets.dart';

/// A slash command. Choosing one starts its flow, or opens its [screen].
class Command {
  const Command(this.name, this.description, this.icon, this.start)
    : screen = null;
  const Command.screen(this.name, this.description, this.icon, this.screen)
    : start = null;
  final String name;
  final String description;
  final IconData icon;
  final CommandFlow Function(Ledger ledger)? start;
  final Widget Function(Store store)? screen;
}

final commands = [
  Command(
    'expense',
    'Add something you paid for or shared',
    Icons.receipt_long_outlined,
    ExpenseFlow.new,
  ),
  Command(
    'sent',
    'Record money you sent a friend',
    Icons.north_east,
    (ledger) => PaymentFlow(ledger, Direction.sent),
  ),
  Command(
    'receive',
    'Record money a friend sent you',
    Icons.south_west,
    (ledger) => PaymentFlow(ledger, Direction.received),
  ),
  Command(
    'bill',
    'Group expenses into a bill, like a trip',
    Icons.folder_open_outlined,
    BillFlow.new,
  ),
  Command(
    'friend',
    'Add someone you split costs with',
    Icons.person_add_alt_1_outlined,
    FriendFlow.new,
  ),
  Command.screen(
    'spending',
    'See where your money went each month',
    Icons.insights_outlined,
    (store) => SpendingScreen(store: store),
  ),
  Command(
    'category',
    'Add a category to sort your spending by',
    Icons.sell_outlined,
    CategoryFlow.new,
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final Store store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  Store get store => widget.store;

  /// True while the command list replaces the overview.
  bool get _choosing => _focus.hasFocus || _input.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _dismiss() {
    _input.clear();
    _focus.unfocus();
  }

  /// Commands whose name starts with the typed text come first, then those
  /// whose description mentions it.
  List<Command> get _matches {
    final typed = _input.text.trim().toLowerCase();
    return [
      ...commands.where((c) => c.name.startsWith(typed)),
      ...commands.where(
        (c) =>
            !c.name.startsWith(typed) &&
            c.description.toLowerCase().contains(typed),
      ),
    ];
  }

  Future<void> _run(Command command) async {
    _dismiss();
    if (command.screen case final screen?) return _open(screen(store));
    final flow = command.start!(store.ledger);
    final saved = await startFlow(context, store, flow);
    // A new bill is usually followed by its first expense.
    if (saved && flow is BillFlow && mounted) {
      _open(BillScreen(store: store, billId: flow.id));
    }
  }

  Future<void> _undo() async {
    _dismiss();
    final messenger = ScaffoldMessenger.of(context);
    final label = await store.undo();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(label == null ? 'Nothing to undo' : 'Undid: $label'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_choosing,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _dismiss();
    },
    // Ctrl+K or Cmd+K opens the commands from a hardware keyboard.
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _focus.requestFocus,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'between',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        body: _choosing ? _commandList() : _overview(),
        // In the bottom bar slot, snackbars float above the command bar. The
        // padding lifts it above the keyboard, which only resizes the body.
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          // Its own surface and edge, so the list scrolls visibly beneath it.
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(),
                SafeArea(top: false, child: _commandBar()),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _commandBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_choosing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // Wraps at large text sizes, so every shortcut stays reachable.
              child: Wrap(
                spacing: 8,
                children: [
                  for (final command in commands.take(4))
                    ActionChip(
                      label: Text('/${command.name}'),
                      onPressed: () => _run(command),
                    ),
                ],
              ),
            ),
          TextField(
            controller: _input,
            focusNode: _focus,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            // The slash is drawn as the field's prefix.
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'^/'))],
            decoration: InputDecoration(
              hintText: 'Type a command',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 18, right: 6),
                child: Text(
                  '/',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: _choosing
                  ? IconButton(
                      tooltip: 'Close commands',
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final matches = _matches;
              if (_input.text.trim().toLowerCase() == 'undo') {
                _undo();
              } else if (matches.isNotEmpty) {
                _run(matches.first);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _commandList() {
    final matches = _matches;
    final undo = store.undoLabel;
    final typed = _input.text.trim();
    final showUndo = undo != null && 'undo'.startsWith(typed.toLowerCase());
    return ListView(
      reverse: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        // Reversed so the best match sits right above the input.
        for (final command in matches)
          ListTile(
            leading: Icon(command.icon),
            title: Text('/${command.name}'),
            subtitle: Text(command.description),
            onTap: () => _run(command),
          ),
        if (showUndo)
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('/undo'),
            subtitle: Text('Undo: $undo'),
            onTap: _undo,
          ),
        if (matches.isEmpty && !showUndo)
          EmptyNote('No command matches “/$typed”.'),
      ],
    );
  }

  Widget _overview() {
    final ledger = store.ledger;
    // Only a brand-new ledger, with nothing but the General bill, welcomes.
    if (ledger.friends.isEmpty &&
        ledger.bills.length == 1 &&
        ledger.expenses.isEmpty &&
        ledger.categories.isEmpty) {
      return _welcome();
    }
    final recent = ledger.recentFriends;
    final all = ledger.balances();
    final balances = {for (final f in recent) f.id: all[f.id] ?? 0};
    // Biggest open balances first; ties keep the most recent first.
    final friends = recent.toList()
      ..sort((a, b) {
        final bySize = balances[b.id]!.abs().compareTo(balances[a.id]!.abs());
        return bySize != 0 ? bySize : recent.indexOf(a) - recent.indexOf(b);
      });
    return CustomScrollView(
      slivers: [
        SliverList.list(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _Headline(friends: friends, balances: balances),
            ),
            const SectionHeader('Spending'),
            _spendingTile(ledger),
            const SectionHeader('Friends'),
            if (friends.isEmpty) const EmptyNote('Add friends with /friend.'),
            for (final friend in friends)
              ListTile(
                leading: Avatar(friend.name),
                title: Text(friend.name),
                subtitle: BalanceText(balances[friend.id]!),
                onTap: () =>
                    _open(FriendScreen(store: store, friendId: friend.id)),
              ),
            const SectionHeader('Bills'),
            for (final bill in ledger.billsInOrder) _billTile(ledger, bill),
            const SectionHeader('Recent'),
            if (ledger.expenses.isEmpty && ledger.payments.isEmpty)
              const EmptyNote('Expenses and payments you add show up here.'),
          ],
        ),
        ActivityList(
          store: store,
          expenses: ledger.expenses,
          payments: ledger.payments,
          limit: 5,
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  /// This month's spending so far, and what most of it went on.
  Widget _spendingTile(Ledger ledger) {
    final now = DateTime.now();
    final spending = Spending(ledger, now);
    final rows = spending.byCategory;
    final top = rows.isEmpty
        ? null
        : rows.reduce((top, row) => row.amount > top.amount ? row : top);
    return ListTile(
      leading: const IconBadge(Icons.insights_outlined),
      title: Text('Spent in ${monthName(now)}'),
      subtitle: Text(switch (top) {
        null => 'Nothing yet',
        (id: '', amount: _) => 'See where it went',
        (:final id, amount: _) => 'Most on ${ledger.category(id)!.name}',
      }),
      trailing: TrailingAmount(rupees(spending.total)),
      onTap: () => _open(SpendingScreen(store: store)),
    );
  }

  Widget _billTile(Ledger ledger, Bill bill) {
    final expenses = ledger.expenses.where((e) => e.billId == bill.id);
    final total = expenses.fold(0, (sum, e) => sum + e.amount);
    return ListTile(
      leading: const Icon(Icons.folder_open_outlined),
      title: Text(bill.name),
      subtitle: Text(switch (expenses.length) {
        0 => 'No expenses yet',
        1 => '1 expense',
        final n => '$n expenses',
      }),
      trailing: TrailingAmount(rupees(total)),
      onTap: () => _open(BillScreen(store: store, billId: bill.id)),
    );
  }

  void _open(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  Widget _welcome() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Text(
          'Track your spending and split costs, one question at a time.',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Pick a command below or type /. Between asks for each detail in '
          'turn: what it was, how much it cost, and who shared it, if anyone.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _run(commands.first),
          icon: const Icon(Icons.add),
          label: const Text('Add your first expense'),
        ),
      ],
    );
  }
}

/// The overall position in one sentence, e.g. "Rahul owes you ₹600.
/// You owe 2 friends ₹500."
class _Headline extends StatelessWidget {
  const _Headline({required this.friends, required this.balances});
  final List<Friend> friends;
  final Map<String, int> balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final owing = friends.where((f) => balances[f.id]! > 0).toList();
    final owed = friends.where((f) => balances[f.id]! < 0).toList();
    int total(List<Friend> list) =>
        list.fold(0, (sum, f) => sum + balances[f.id]!.abs());
    String who(List<Friend> list) =>
        list.length == 1 ? list.single.name : '${list.length} friends';
    TextSpan amount(int value, int sign) => TextSpan(
      text: rupees(value),
      style: TextStyle(color: scheme.forSign(sign), fontFeatures: tabular),
    );
    return Text.rich(
      TextSpan(
        children: [
          if (owing.isEmpty && owed.isEmpty)
            const TextSpan(text: 'You’re all settled up.'),
          if (owing.isNotEmpty) ...[
            TextSpan(
              text: '${who(owing)} ${owing.length == 1 ? 'owes' : 'owe'} you ',
            ),
            amount(total(owing), 1),
            const TextSpan(text: '. '),
          ],
          if (owed.isNotEmpty) ...[
            TextSpan(text: 'You owe ${who(owed)} '),
            amount(total(owed), -1),
            const TextSpan(text: '.'),
          ],
        ],
      ),
      style: theme.textTheme.headlineSmall,
    );
  }
}
