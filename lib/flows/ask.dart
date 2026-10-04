import '../data/ledger.dart';
import '../data/money.dart';

/// One question in a command flow. It holds its answer while the flow runs.
sealed class Ask {
  Ask(this.question, {this.hint});

  /// Shown as the page heading, e.g. "How much did it cost?".
  final String question;
  final String? hint;

  /// Why the current answer can't be accepted, or null when it can.
  String? get problem;

  /// The answer as a short phrase for the answers strip, e.g. "₹1,200".
  String get phrase;

  /// True when an earlier answer changed in a way that this one should be
  /// looked at again, even though it is still valid.
  bool get stale => false;

  /// Called when the user accepts this answer and moves on.
  void accept() {}
}

final class TextAsk extends Ask {
  TextAsk(
    super.question, {
    super.hint,
    this.text = '',
    this.placeholder,
    this.taken,
  });
  String text;
  final String? placeholder;

  /// Returns a message when the name is already used.
  final String? Function(String name)? taken;

  @override
  String? get problem => text.trim().isEmpty
      ? 'Type a name to continue.'
      : taken?.call(text.trim());

  @override
  String get phrase => text.trim();
}

final class AmountAsk extends Ask {
  AmountAsk(super.question, {super.hint, this.paise});

  /// The amount in paise, or null while the field is empty or invalid.
  int? paise;

  @override
  String? get problem =>
      (paise ?? 0) <= 0 ? 'Enter an amount above zero.' : null;

  @override
  String get phrase => rupees(paise ?? 0);
}

final class CountAsk extends Ask {
  CountAsk(super.question, {super.hint, this.count = 1});
  static const max = 999;
  int count;

  @override
  String? get problem =>
      count < 1 || count > max ? 'Enter a number from 1 to $max.' : null;

  @override
  String get phrase => count == 1 ? '1 unit' : '$count units';
}

/// An option in a [PickAsk] or [MultiPickAsk].
class Choice {
  const Choice(this.id, this.label, {this.detail, this.sign = 0});
  final String id;
  final String label;
  final String? detail;

  /// Colours [detail] as a balance: positive when it's owed to you.
  final int sign;
}

/// Something new the user can create from a picker by typing its name.
class Creator {
  const Creator({
    required this.placeholder,
    required this.label,
    required this.create,
  });

  /// The search field's placeholder, e.g. "Search or add a friend".
  final String placeholder;

  /// Builds the row label from the typed name, e.g. `New bill "Goa trip"`.
  final String Function(String name) label;

  /// Creates the record and returns its id.
  final String Function(String name) create;
}

final class PickAsk extends Ask {
  PickAsk(
    super.question, {
    super.hint,
    required this.choices,
    required this.describe,
    this.selected,
    this.creator,
  });

  /// Recomputed on every read, so options follow earlier answers.
  final List<Choice> Function() choices;

  /// Turns the chosen option into the strip phrase, e.g. "in Goa trip".
  final String Function(Choice choice) describe;
  String? selected;
  final Creator? creator;

  Choice? get choice => choices().where((c) => c.id == selected).firstOrNull;

  @override
  String? get problem =>
      choice == null ? 'Choose an option to continue.' : null;

  @override
  String get phrase => describe(choice!);
}

final class MultiPickAsk extends Ask {
  MultiPickAsk(
    super.question, {
    super.hint,
    required this.choices,
    required this.describe,
    List<String> selected = const [],
    this.creator,
    this.emptyProblem,
  }) : selected = [...selected];

  final List<Choice> Function() choices;
  final String Function(List<Choice> chosen) describe;

  /// In the order they were picked.
  final List<String> selected;
  final Creator? creator;

  /// Why picking nobody won't do, or null when it's a fine answer.
  final String? emptyProblem;

  List<Choice> get chosen => [
    for (final id in selected) ...choices().where((c) => c.id == id),
  ];

  @override
  String? get problem => chosen.isEmpty ? emptyProblem : null;

  @override
  String get phrase => describe(chosen);
}

/// How an amount is divided between people, with a value per person.
final class SplitAsk extends Ask {
  SplitAsk(
    super.question, {
    super.hint,
    required this.people,
    required this.nameOf,
    required this.amount,
    required this.quantity,
    Expense? from,
  }) {
    if (from == null) return;
    mode = from.split;
    if (from.split == SplitMode.equal) {
      excluded.addAll(people().where((id) => !from.parts.containsKey(id)));
    } else {
      values[from.split]!.addAll(from.parts);
    }
    accept();
  }

  /// Everyone in the expense, you first.
  final List<String> Function() people;
  final String Function(String id) nameOf;
  final int Function() amount;
  final int Function() quantity;

  SplitMode? _chosen;

  /// How the amount is split: the user's choice, or by quantity when there is
  /// more than one unit (or units were already entered), else equally.
  ///
  /// A split by quantity stays even if the quantity drops to 1; then it is no
  /// longer in [modes] and [problem] asks for another way, rather than the
  /// split quietly changing.
  SplitMode get mode =>
      _chosen ??
      (quantity() > 1 || values[SplitMode.quantity]!.isNotEmpty
          ? SplitMode.quantity
          : SplitMode.equal);
  set mode(SplitMode value) => _chosen = value;

  /// The modes that make sense for the current quantity.
  List<SplitMode> get modes => [
    SplitMode.equal,
    if (quantity() > 1) SplitMode.quantity,
    SplitMode.percent,
    SplitMode.exact,
  ];

  /// People left out of an equal split.
  final excluded = <String>{};

  /// Values typed per mode, kept so switching modes loses nothing.
  /// Units for quantity, basis points for percent, paise for exact.
  final values = <SplitMode, Map<String, int>>{
    SplitMode.quantity: {},
    SplitMode.percent: {},
    SplitMode.exact: {},
  };

  /// What the values must add up to in the current mode.
  int get target => switch (mode) {
    SplitMode.equal => 0,
    SplitMode.quantity => quantity(),
    SplitMode.percent => 10000,
    SplitMode.exact => amount(),
  };

  /// What is still unassigned; negative when too much is assigned.
  int get left {
    final typed = values[mode] ?? const {};
    return target - people().fold<int>(0, (sum, id) => sum + (typed[id] ?? 0));
  }

  /// The one person with no value yet, who gets whatever is left.
  String? get filler {
    if (mode == SplitMode.equal) return null;
    final empty = people().where((id) => !values[mode]!.containsKey(id));
    return empty.length == 1 && left >= 0 ? empty.single : null;
  }

  /// The parts to save, or null while they don't add up.
  Map<String, int>? get parts {
    if (!modes.contains(mode)) return null;
    if (mode == SplitMode.equal) {
      final included = people().where((id) => !excluded.contains(id));
      return included.isEmpty ? null : {for (final id in included) id: 1};
    }
    final typed = values[mode]!;
    final result = {for (final id in people()) id: typed[id] ?? 0};
    if (filler case final id?) result[id] = left;
    final sum = result.values.fold<int>(0, (a, b) => a + b);
    return sum == target && target > 0 ? result : null;
  }

  /// What each person pays, or null while the parts don't add up.
  Map<String, int>? get shares => switch (parts) {
    final parts? => sharesOf(mode, amount(), parts),
    null => null,
  };

  /// Formats a value in the current mode's unit.
  String format(int value) => switch (mode) {
    SplitMode.equal => '',
    SplitMode.quantity => value == 1 ? '1 unit' : '$value units',
    SplitMode.percent => '${hundredthsText(value)}%',
    SplitMode.exact => rupees(value),
  };

  @override
  String? get problem {
    if (parts != null) return null;
    if (!modes.contains(mode)) {
      return 'Splitting by quantity needs more than one unit. '
          'Choose another way to split it.';
    }
    if (mode == SplitMode.equal) return 'Include at least one person.';
    return left >= 0
        ? '${format(left)} still to assign.'
        : '${format(-left)} more than the total.';
  }

  /// The answers this split was accepted for. Someone joining or leaving, or
  /// a new quantity, means the shares need another look: a new person would
  /// otherwise get nothing without being asked.
  String? _acceptedFor;
  String get _inputs => [
    mode.name,
    ...people(),
    if (mode == SplitMode.quantity) '${quantity()}',
  ].join('|');

  @override
  bool get stale =>
      mode != SplitMode.equal &&
      _acceptedFor != null &&
      _acceptedFor != _inputs;

  @override
  void accept() => _acceptedFor = _inputs;

  @override
  String get phrase => switch (mode) {
    SplitMode.equal => switch (people()
        .where((id) => !excluded.contains(id))
        .length) {
      final n when n == people().length => 'split equally',
      final n => 'split equally by $n',
    },
    SplitMode.quantity => 'split by quantity',
    SplitMode.percent => 'split by percentage',
    SplitMode.exact => 'split by amount',
  };
}
