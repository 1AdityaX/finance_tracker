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
