/// Money is stored as integer paise: ₹1 is 100 paise.
library;

/// Formats [paise] as rupees with Indian digit grouping, e.g. `₹12,34,567.50`.
///
/// Whole rupees drop the decimals: `₹1,200`.
String rupees(int paise) {
  final whole = (paise.abs() ~/ 100).toString();
  final grouped = whole.length <= 3
      ? whole
      : '${whole.substring(0, whole.length - 3).replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},')},'
            '${whole.substring(whole.length - 3)}';
  final fraction = paise.abs() % 100;
  return '${paise < 0 ? '−' : ''}₹$grouped'
      '${fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}'}';
}

/// Parses a decimal with up to two fraction digits into hundredths.
///
/// Rupees become paise and percentages become basis points: `"1200.5"`
/// gives `120050`. Returns null for anything else.
int? parseHundredths(String input) {
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(input.trim());
  if (match == null) return null;
  return int.parse(match[1]!) * 100 +
      int.parse((match[2] ?? '').padRight(2, '0'));
}

/// Works out sums typed into a money field, as a spreadsheet does:
/// `"1000-300"` gives `70000`, `"3*45.50"` gives `13650`. Handles `+`, `-`,
/// `*` or `×`, `/` or `÷` and brackets, with `*` and `/` before `+` and `-`.
/// Commas and spaces are ignored. The arithmetic is exact and only the result
/// is rounded, to the nearest hundredth, halves up.
///
/// Returns null for anything that isn't a sum, divides by zero, or comes to
/// less than zero or more than 999,999,999.99. A plain number is a sum too.
int? evaluateHundredths(String input) {
  final text = input.replaceAll(RegExp(r'[,\s]'), '');
  if (text.isEmpty) return null;
  final tokens = RegExp(r'\d*\.?\d+|\d+\.|[-+*/×÷()]').allMatches(text);
  if (tokens.fold<int>(0, (n, m) => n + m.group(0)!.length) != text.length) {
    return null;
  }
  final parser = _Sum([for (final m in tokens) m.group(0)!]);
  final value = parser.sum();
  if (value == null || !parser.done) return null;
  final (n, d) = value;
  if (n < BigInt.zero) return null;
  // Hundredths are already the unit, so only the leftover fraction rounds.
  final rounded = (n * BigInt.two + d) ~/ (d * BigInt.two);
  return rounded > BigInt.from(99999999999) ? null : rounded.toInt();
}

/// A fraction of hundredths, kept exact while a sum is worked out.
typedef _Fraction = (BigInt, BigInt);

class _Sum {
  _Sum(this.tokens);
  final List<String> tokens;
  var _at = 0;

  bool get done => _at == tokens.length;
  String? get _next => done ? null : tokens[_at];

  _Fraction? sum() {
    var total = term();
    while (total != null && (_next == '+' || _next == '-')) {
      final plus = tokens[_at++] == '+';
      final right = term();
      if (right == null) return null;
      final (a, b) = total;
      final (c, d) = right;
      total = (plus ? a * d + c * b : a * d - c * b, b * d);
    }
    return total;
  }

  _Fraction? term() {
    var total = factor();
    while (total != null && const {'*', '×', '/', '÷'}.contains(_next)) {
      final times = const {'*', '×'}.contains(tokens[_at++]);
      final right = factor();
      if (right == null) return null;
      final (a, b) = total;
      final (c, d) = right;
      if (!times && c == BigInt.zero) return null;
      // Both sides are in hundredths, so a product has 100 too many and a
      // quotient 100 too few.
      total = times
          ? (a * c, b * d * BigInt.from(100))
          : (a * d * BigInt.from(100), b * c);
      final (n, m) = total;
      if (m < BigInt.zero) total = (-n, -m);
    }
    return total;
  }

  _Fraction? factor() {
    switch (_next) {
      case '+' || '-':
        final minus = tokens[_at++] == '-';
        final value = factor();
        if (value == null) return null;
        return minus ? (-value.$1, value.$2) : value;
      case '(':
        _at++;
        final value = sum();
        if (value == null || _next != ')') return null;
        _at++;
        return value;
      case final String number when RegExp(r'[\d.]').hasMatch(number):
        _at++;
        final [whole, fraction] = '$number.'.split('.').take(2).toList();
        if (fraction.length > 2) return null;
        return (
          BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(100) +
              BigInt.parse(fraction.padRight(2, '0')),
          BigInt.one,
        );
      default:
        return null;
    }
  }
}

/// Whether [input] is a sum to work out rather than a plain number.
bool isSum(String input) => RegExp(r'\d\s*[-+*/×÷(]|[()]').hasMatch(input);

/// Formats hundredths back into editable text: `120050` gives `"1200.5"`.
String hundredthsText(int value) {
  final fraction = value % 100;
  if (fraction == 0) return '${value ~/ 100}';
  return '${value ~/ 100}.${fraction.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
}

/// Splits [total] in proportion to [weights], so the parts always add up to
/// [total] exactly.
///
/// Each key first gets its rounded-down share. Leftover paise then go one at a
/// time to the largest remainders, with ties broken by key, so the result
/// doesn't depend on the order of [weights].
Map<String, int> apportion(int total, Map<String, int> weights) {
  final sum = weights.values.fold<int>(0, (a, b) => a + b);
  if (sum <= 0) return {for (final key in weights.keys) key: 0};
  final parts = {
    for (final MapEntry(:key, :value) in weights.entries)
      key: total * value ~/ sum,
  };
  int remainder(String key) => total * weights[key]! % sum;
  final order = weights.keys.toList()
    ..sort((a, b) {
      final byRemainder = remainder(b).compareTo(remainder(a));
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  final left = total - parts.values.fold<int>(0, (a, b) => a + b);
  for (final key in order.take(left)) {
    parts[key] = parts[key]! + 1;
  }
  return parts;
}

/// A balance in words: "owes you ₹600", "you owe ₹300" or "settled up".
///
/// With a [name] it reads as a sentence: "Rahul owes you ₹600".
String balancePhrase(int balance, {String? name}) {
  if (balance == 0) return 'settled up';
  final amount = rupees(balance.abs());
  if (name == null) return balance > 0 ? 'owes you $amount' : 'you owe $amount';
  return '${owesPhrase(name, balance)} $amount';
}

/// "Rahul owes you" for a positive amount, "You owe Rahul" for a negative one.
String owesPhrase(String name, int amount) =>
    amount >= 0 ? '$name owes you' : 'You owe $name';
