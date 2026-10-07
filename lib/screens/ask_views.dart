import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ledger.dart';
import '../data/money.dart';
import '../flows/flows.dart';
import '../theme.dart';
import 'widgets.dart';

/// The heading and hint shared by every question page.
class _Question extends StatelessWidget {
  const _Question(this.ask);
  final Ask ask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            headingLevel: 1,
            liveRegion: true,
            child: Text(ask.question, style: theme.textTheme.headlineSmall),
          ),
          if (ask.hint case final hint?) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The input for one [Ask], chosen by its type.
class AskView extends StatelessWidget {
  const AskView({
    super.key,
    required this.ask,
    required this.onChanged,
    required this.onDone,
  });
  final Ask ask;

  /// Call after changing the answer, so the screen can update.
  final VoidCallback onChanged;

  /// Call to accept the answer and move on.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => switch (ask) {
    final TextAsk a => _TextView(a, onChanged, onDone),
    final AmountAsk a => _AmountView(a, onChanged, onDone),
    final CountAsk a => _CountView(a, onChanged, onDone),
    final PickAsk a => _PickView(a, onChanged, onDone),
    final MultiPickAsk a => _MultiPickView(a, onChanged, onDone),
    final SplitAsk a => _SplitView(a, onChanged),
    final SettleAsk a => _SettleView(a, onChanged, onDone),
  };
}

/// Accepts digits with up to two decimals. Commas are digit grouping, as in
/// "1,200", so they are dropped rather than read as a decimal point.
final _decimal = TextInputFormatter.withFunction((old, value) {
  final text = value.text.replaceAll(',', '');
  if (!RegExp(r'^\d{0,9}(\.\d{0,2})?$').hasMatch(text)) return old;
  final caret = value.selection.end.clamp(0, value.text.length);
  final dropped = ','.allMatches(value.text.substring(0, caret)).length;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret - dropped),
  );
});

class _TextView extends StatefulWidget {
  const _TextView(this.ask, this.onChanged, this.onDone);
  final TextAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  late final controller = TextEditingController(text: widget.ask.text);
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Not autofocus, which is dropped while the previous page's field still
    // has focus during the transition, closing the keyboard.
    focus.requestFocus();
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      _Question(widget.ask),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: TextField(
          controller: controller,
          focusNode: focus,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: InputDecoration(
            hintText: widget.ask.placeholder,
            counterText: '',
          ),
          onChanged: (text) {
            widget.ask.text = text;
            widget.onChanged();
          },
          // Keeps the keyboard up while the next page takes focus.
          onEditingComplete: () {},
          onSubmitted: (_) => widget.onDone(),
        ),
      ),
    ],
  );
}

class _AmountView extends StatefulWidget {
  const _AmountView(this.ask, this.onChanged, this.onDone);
  final AmountAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_AmountView> createState() => _AmountViewState();
}

class _AmountViewState extends State<_AmountView> {
  late final controller = TextEditingController(
    text: switch (widget.ask.paise) {
      final paise? => hundredthsText(paise),
      null => '',
    },
  );
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.requestFocus();
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displaySmall?.copyWith(fontFeatures: tabular);
    return ListView(
      children: [
        _Question(widget.ask),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: controller,
            focusNode: focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [_decimal],
            textInputAction: TextInputAction.next,
            style: style,
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: style?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              hintText: '0',
              filled: false,
              border: const UnderlineInputBorder(),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            onChanged: (text) {
              widget.ask.paise = parseHundredths(text);
              widget.onChanged();
            },
            onEditingComplete: () {},
            onSubmitted: (_) => widget.onDone(),
          ),
        ),
      ],
    );
  }
}

class _CountView extends StatefulWidget {
  const _CountView(this.ask, this.onChanged, this.onDone);
  final CountAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_CountView> createState() => _CountViewState();
}

class _CountViewState extends State<_CountView> {
  late final controller = TextEditingController(text: '${widget.ask.count}');

  /// Steps from the current count, so quick repeated taps all count.
  void _step(int by) {
    final count = (widget.ask.count + by).clamp(1, CountAsk.max);
    controller.text = '$count';
    widget.ask.count = count;
    widget.onChanged();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.ask.count;
    return ListView(
      children: [
        _Question(widget.ask),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16,
          children: [
            IconButton.filledTonal(
              tooltip: 'One less',
              iconSize: 28,
              onPressed: count > 1 ? () => _step(-1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter('${CountAsk.max}'.length),
                ],
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontFeatures: tabular),
                decoration: const InputDecoration(filled: false),
                onChanged: (text) {
                  widget.ask.count = int.tryParse(text) ?? 0;
                  widget.onChanged();
                },
                onEditingComplete: () {},
                onSubmitted: (_) => widget.onDone(),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'One more',
              iconSize: 28,
              onPressed: count < CountAsk.max ? () => _step(1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

/// A search field shown above long lists and lists you can add to.
///
/// It takes focus only when the list is empty, so the keyboard doesn't
/// cover the choices when tapping one is all it takes.
class _Search extends StatefulWidget {
  const _Search({
    required this.controller,
    required this.hint,
    required this.focusFirst,
    required this.onChanged,
    required this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final bool focusFirst;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.focusFirst) focus.requestFocus();
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: TextField(
      controller: widget.controller,
      focusNode: focus,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      // Keeps the keyboard up for the next name or the next page.
      onEditingComplete: () {},
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
      ),
      onChanged: (_) => widget.onChanged(),
      onSubmitted: (_) => widget.onSubmitted(),
    ),
  );
}

/// Lists longer than this get a search field, as do lists you can add to.
const _searchAbove = 7;

/// Shared by single and multiple choice: filters choices by the typed text
/// and offers to create one when nothing matches exactly.
mixin _Filtering<T extends StatefulWidget> on State<T> {
  final query = TextEditingController();

  String get typed => query.text.trim();

  List<Choice> filter(List<Choice> choices) => typed.isEmpty
      ? choices
      : [
          for (final c in choices)
            if (c.label.toLowerCase().contains(typed.toLowerCase())) c,
        ];

  bool canCreate(Creator? creator, List<Choice> choices) =>
      creator != null &&
      typed.isNotEmpty &&
      !choices.any((c) => c.label.toLowerCase() == typed.toLowerCase());

  /// [empty] replaces the note shown when there are no choices.
  Widget choiceList(
    Ask ask,
    List<Choice> choices,
    Creator? creator, {
    required VoidCallback onSubmitted,
    VoidCallback? onCreate,
    required Widget Function(Choice choice) tile,
    Widget? status,
    String? empty,
  }) {
    final visible = filter(choices);
    final create = canCreate(creator, choices);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Question(ask)),
        if (creator != null || choices.length > _searchAbove)
          SliverToBoxAdapter(
            child: _Search(
              controller: query,
              hint: creator?.placeholder ?? 'Search',
              // Nothing to tap yet, unless nothing is a fine answer.
              focusFirst: choices.isEmpty && ask.problem != null,
              onChanged: () => setState(() {}),
              onSubmitted: onSubmitted,
            ),
          ),
        if (create)
          SliverToBoxAdapter(
            child: ListTile(
              leading: const Icon(Icons.add),
              title: Text(creator!.label(typed)),
              onTap: onCreate,
            ),
          ),
        if (status != null) SliverToBoxAdapter(child: status),
        SliverList.list(children: [for (final c in visible) tile(c)]),
        if (visible.isEmpty && !create)
          SliverToBoxAdapter(
            child: EmptyNote(switch ((choices.isEmpty, ask.problem)) {
              (false, _) => 'Nothing matches “$typed”.',
              (true, _) when empty != null => empty,
              (true, null) =>
                'Nothing here yet. Type a name above to add one, or '
                    'continue without.',
              (true, _) => 'Nothing here yet. Type a name above to add one.',
            }),
          ),
      ],
    );
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }
}

class _PickView extends StatefulWidget {
  const _PickView(this.ask, this.onChanged, this.onDone);
  final PickAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_PickView> createState() => _PickViewState();
}

class _PickViewState extends State<_PickView> with _Filtering {
  void _pick(String id) {
    // Tapping the current answer to move on doesn't count as a change.
    if (id != widget.ask.selected) {
      widget.ask.selected = id;
      widget.onChanged();
    }
    widget.onDone();
  }

  /// Enter picks the only match, or else creates what was typed.
  void _submit() {
    final ask = widget.ask;
    final choices = ask.choices();
    final visible = filter(choices);
    if (typed.isNotEmpty && visible.length == 1) {
      _pick(visible.single.id);
    } else if (canCreate(ask.creator, choices)) {
      _pick(ask.creator!.create(typed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    final scheme = Theme.of(context).colorScheme;
    return choiceList(
      ask,
      ask.choices(),
      ask.creator,
      onSubmitted: _submit,
      onCreate: () => _pick(ask.creator!.create(typed)),
      tile: (c) => ListTile(
        title: Text(c.label),
        subtitle: c.detail == null
            ? null
            : Text(c.detail!, style: TextStyle(color: scheme.forSign(c.sign))),
        selected: c.id == ask.selected,
        trailing: c.id == ask.selected ? const Icon(Icons.check_circle) : null,
        onTap: () => _pick(c.id),
      ),
    );
  }
}

class _MultiPickView extends StatefulWidget {
  const _MultiPickView(this.ask, this.onChanged, this.onDone);
  final MultiPickAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_MultiPickView> createState() => _MultiPickViewState();
}

class _MultiPickViewState extends State<_MultiPickView> with _Filtering {
  void _toggle(String id) {
    final selected = widget.ask.selected;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    widget.onChanged();
  }

  void _create() {
    widget.ask.selected.add(widget.ask.creator!.create(typed));
    query.clear();
    widget.onChanged();
  }

  /// Enter ticks the only match or creates what was typed; with nothing
  /// typed it moves on.
  void _submit() {
    final ask = widget.ask;
    final choices = ask.choices();
    final visible = filter(choices);
    if (typed.isEmpty) {
      widget.onDone();
    } else if (visible.length == 1) {
      if (!ask.selected.contains(visible.single.id)) {
        ask.selected.add(visible.single.id);
      }
      query.clear();
      widget.onChanged();
    } else if (canCreate(ask.creator, choices)) {
      _create();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    return choiceList(
      ask,
      ask.choices(),
      ask.creator,
      onSubmitted: _submit,
      onCreate: _create,
      tile: (c) => CheckboxListTile(
        value: ask.selected.contains(c.id),
        onChanged: (_) => _toggle(c.id),
        secondary: Avatar(c.label),
        title: Text(c.label),
      ),
    );
  }
}

class _SettleView extends StatefulWidget {
  const _SettleView(this.ask, this.onChanged, this.onDone);
  final SettleAsk ask;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  State<_SettleView> createState() => _SettleViewState();
}

class _SettleViewState extends State<_SettleView> with _Filtering {
  SettleAsk get ask => widget.ask;

  void _toggle(String id) {
    ask.selected.contains(id) ? ask.selected.remove(id) : ask.selected.add(id);
    widget.onChanged();
  }

  /// Enter ticks the only match; with nothing typed it moves on.
  void _submit() {
    final visible = filter([for (final e in ask.expenses()) e.choice]);
    if (typed.isEmpty) {
      if (ask.problem == null) widget.onDone();
    } else if (visible.length == 1) {
      if (!ask.selected.contains(visible.single.id)) {
        ask.selected.add(visible.single.id);
      }
      query.clear();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expenses = ask.expenses();
    final open = {for (final e in expenses) e.choice.id: e.open};
    final settles = ask.settles;
    final order = settles.keys.toList();
    return choiceList(
      ask,
      [for (final e in expenses) e.choice],
      null,
      onSubmitted: _submit,
      status: expenses.isEmpty ? null : _status(theme),
      empty:
          'Nothing is open with them in this bill. Continue to put it '
          'toward the overall balance.',
      tile: (c) {
        final part = settles[c.id];
        final left = open[c.id]!;
        // With two or more ticked, the order decides what is paid in full.
        final turn = order.length > 1 && part != null
            ? '${_ordinal(order.indexOf(c.id) + 1)} · '
            : '';
        return CheckboxListTile(
          value: part != null,
          onChanged: (_) => _toggle(c.id),
          title: Text(c.label),
          subtitle: Text(
            switch (part) {
              null => c.detail ?? '',
              0 when left == 0 => '${turn}Already paid',
              0 => '${turn}Nothing left for this',
              _ when part >= left => '$turn${rupees(part)}, paid in full',
              _ =>
                '$turn${rupees(part)} of ${rupees(left)}, '
                    '${rupees(left - part)} left',
            },
            style: TextStyle(
              color: switch (part) {
                null => scheme.forSign(c.sign),
                0 => scheme.forSign(-1),
                _ => null,
              },
              fontFeatures: tabular,
            ),
          ),
        );
      },
    );
  }

  /// "1st", "2nd", "3rd", "4th", "11th", "21st".
  static String _ordinal(int n) => switch ((n % 10, n % 100)) {
    (_, 11 || 12 || 13) => '${n}th',
    (1, _) => '${n}st',
    (2, _) => '${n}nd',
    (3, _) => '${n}rd',
    _ => '${n}th',
  };

  /// Where the money goes: "₹1.50 left over goes toward the overall
  /// balance". A problem shows above Continue instead, where it can't
  /// scroll away.
  Widget? _status(ThemeData theme) {
    if (ask.problem != null) return null;
    final amount = rupees(ask.amount());
    final (String text, int sign) = switch (ask.leftOver) {
      _ when ask.settles.isEmpty => (
        'All $amount goes toward the overall balance.',
        0,
      ),
      final left when left > 0 => (
        '${rupees(left)} left over goes toward the overall balance.',
        0,
      ),
      _ => ('All $amount goes to these expenses.', 1),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.forSign(sign),
            fontFeatures: tabular,
          ),
        ),
      ),
    );
  }
}

class _SplitView extends StatefulWidget {
  const _SplitView(this.ask, this.onChanged);
  final SplitAsk ask;
  final VoidCallback onChanged;

  @override
  State<_SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<_SplitView> {
  final _controllers = <String, TextEditingController>{};

  SplitAsk get ask => widget.ask;

  TextEditingController _controller(String id) =>
      _controllers.putIfAbsent('${ask.mode.name}/$id', () {
        final value = ask.values[ask.mode]![id];
        return TextEditingController(
          text: value == null ? '' : hundredthsText(value),
        );
      });

  void _setValue(String id, int? value) {
    value == null
        ? ask.values[ask.mode]!.remove(id)
        : ask.values[ask.mode]![id] = value;
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = ask.people();
    final shares = ask.shares;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Question(ask)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // Chips wrap rather than squeeze, so labels stay whole on narrow
            // phones and at large text sizes.
            child: Wrap(
              spacing: 8,
              children: [
                for (final mode in ask.modes)
                  ChoiceChip(
                    label: Text(switch (mode) {
                      SplitMode.equal => 'Equally',
                      SplitMode.quantity => 'By quantity',
                      SplitMode.percent => 'By percentage',
                      SplitMode.exact => 'By amount',
                      SplitMode.items => 'By item',
                    }),
                    selected: ask.mode == mode,
                    onSelected: (_) {
                      ask.mode = mode;
                      if (mode == SplitMode.items && ask.items.isEmpty) {
                        ask.addItem();
                      }
                      widget.onChanged();
                    },
                  ),
              ],
            ),
          ),
        ),
        // Below a list of items, where it stays in view while they change.
        if (ask.mode != SplitMode.items)
          SliverToBoxAdapter(child: _status(theme, shares)),
        if (ask.mode == SplitMode.items) ...[
          SliverList.list(
            children: [
              for (final (i, item) in ask.items.indexed)
                _itemCard(theme, i, item, people),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      ask.addItem();
                      widget.onChanged();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                ),
              ),
              _status(theme, shares),
              if (shares != null) ...[
                for (final id in people)
                  ListTile(
                    leading: Avatar(ask.nameOf(id)),
                    title: Text(ask.nameOf(id)),
                    trailing: Text(
                      rupees(shares[id] ?? 0),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ]
        // No rows for a mode that no longer applies; its problem says why.
        else if (ask.modes.contains(ask.mode))
          SliverList.list(
            children: [for (final id in people) _row(theme, id, shares?[id])],
          ),
      ],
    );
  }

  /// "₹400 each", "₹200 still to assign", "All ₹1,200 assigned".
  Widget _status(ThemeData theme, Map<String, int>? shares) {
    final problem = ask.problem;
    final (String text, int sign) = problem != null
        ? (problem, -1)
        : switch (ask.mode) {
            SplitMode.equal when shares!.values.toSet().length == 1 => (
              '${rupees(shares.values.first)} each',
              0,
            ),
            SplitMode.equal => (
              'About ${rupees(ask.amount() ~/ shares!.length)} each',
              0,
            ),
            _ => ('All ${ask.format(ask.target)} assigned', 1),
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.forSign(sign),
            fontFeatures: tabular,
          ),
        ),
      ),
    );
  }

  TextEditingController _itemController(ItemDraft item, String field) =>
      _controllers.putIfAbsent('item/${item.key}/$field', () {
        return TextEditingController(
          text: field == 'name'
              ? item.name
              : item.paise == null
              ? ''
              : hundredthsText(item.paise!),
        );
      });

  /// One item: what it was, what it cost, and who shared it.
  Widget _itemCard(
    ThemeData theme,
    int index,
    ItemDraft item,
    List<String> people,
  ) => Card.outlined(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemController(item, 'name'),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Item ${index + 1}',
                  ),
                  onChanged: (text) {
                    item.name = text;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _itemController(item, 'amount'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimal],
                  textAlign: TextAlign.end,
                  textInputAction: TextInputAction.done,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: tabular,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const _Unit('₹'),
                    prefixIconConstraints: const BoxConstraints(),
                    hintText: item == ask.items.last && ask.left > 0
                        ? hundredthsText(ask.left)
                        : '0',
                  ),
                  onChanged: (text) {
                    item.paise = parseHundredths(text);
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip:
                    'Remove ${item.name.trim().isEmpty ? 'item ${index + 1}' : item.name.trim()}',
                onPressed: () {
                  ask.items.remove(item);
                  widget.onChanged();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in people)
                FilterChip(
                  label: Text(ask.nameOf(id)),
                  selected: item.people.contains(id),
                  onSelected: (on) {
                    on ? item.people.add(id) : item.people.remove(id);
                    widget.onChanged();
                  },
                ),
            ],
          ),
          if (item.people.length > 1 && (item.paise ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.people.length == 2
                    ? '${rupees(item.paise! ~/ 2)} each'
                    : 'About ${rupees(item.paise! ~/ item.people.length)} each',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: tabular,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  /// Units shown for [id]: typed, or the remainder for the one left blank.
  int _units(String id) =>
      ask.values[SplitMode.quantity]![id] ?? (ask.filler == id ? ask.left : 0);

  Widget _row(ThemeData theme, String id, int? share) {
    final name = ask.nameOf(id);
    final shareText = share == null ? null : Text(rupees(share));
    switch (ask.mode) {
      case SplitMode.equal:
        final included = !ask.excluded.contains(id);
        return CheckboxListTile(
          value: included,
          secondary: Avatar(name),
          title: Text(name),
          subtitle: included ? shareText : const Text('Not included'),
          onChanged: (_) {
            included ? ask.excluded.add(id) : ask.excluded.remove(id);
            widget.onChanged();
          },
        );
      case SplitMode.quantity:
        final typed = ask.values[SplitMode.quantity]![id];
        final shown = _units(id);
        return ListTile(
          leading: Avatar(name),
          title: Text(name),
          subtitle: shareText,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'One less for $name',
                onPressed: shown > 0
                    ? () => _setValue(id, _units(id) - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$shown',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: tabular,
                    color: typed == null
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'One more for $name',
                onPressed: () => _setValue(id, _units(id) + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        );
      case SplitMode.items:
        return const SizedBox.shrink();
      case SplitMode.percent || SplitMode.exact:
        final percent = ask.mode == SplitMode.percent;
        return ListTile(
          leading: Avatar(name),
          title: Text(name),
          subtitle: percent ? shareText : null,
          trailing: SizedBox(
            width: 120,
            child: TextField(
              controller: _controller(id),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimal],
              textAlign: TextAlign.end,
              textInputAction: id == ask.people().last
                  ? TextInputAction.done
                  : TextInputAction.next,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: tabular,
              ),
              decoration: InputDecoration(
                isDense: true,
                // Icons rather than prefix text, which hides while empty.
                prefixIcon: percent ? null : const _Unit('₹'),
                suffixIcon: percent ? const _Unit('%') : null,
                prefixIconConstraints: const BoxConstraints(),
                suffixIconConstraints: const BoxConstraints(),
                hintText: ask.filler == id ? hundredthsText(ask.left) : '0',
              ),
              onChanged: (text) => _setValue(id, parseHundredths(text)),
            ),
          ),
        );
    }
  }
}

/// A ₹ or % marker inside a split field that stays visible while it's empty.
class _Unit extends StatelessWidget {
  const _Unit(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
