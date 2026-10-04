import 'package:finance_tracker/data/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rupees uses Indian digit grouping and drops whole-rupee decimals', () {
    expect(rupees(0), '₹0');
    expect(rupees(120000), '₹1,200');
    expect(rupees(12345678950), '₹12,34,56,789.50');
    expect(rupees(-30005), '−₹300.05');
    expect(rupees(99999), '₹999.99');
  });

  test('parseHundredths reads rupees and percentages', () {
    expect(parseHundredths('1200'), 120000);
    expect(parseHundredths('1200.5'), 120050);
    expect(parseHundredths(' 99.99 '), 9999);
    expect(parseHundredths('33.33'), 3333);
    expect(parseHundredths('12.'), 1200);
    for (final bad in ['', '.5', '1.234', 'abc', '-5', '1234567890', '1,200']) {
      expect(parseHundredths(bad), isNull, reason: bad);
    }
  });

  test('balancePhrase reads as words', () {
    expect(balancePhrase(60000), 'owes you ₹600');
    expect(balancePhrase(-30000), 'you owe ₹300');
    expect(balancePhrase(0), 'settled up');
    expect(balancePhrase(60000, name: 'Rahul'), 'Rahul owes you ₹600');
    expect(balancePhrase(-30000, name: 'Rahul'), 'You owe Rahul ₹300');
  });

  test('hundredthsText round-trips with parseHundredths', () {
    for (final value in [0, 5, 50, 120050, 3333, 10000]) {
      expect(parseHundredths(hundredthsText(value)), value);
    }
    expect(hundredthsText(120050), '1200.5');
    expect(hundredthsText(10000), '100');
  });

  group('apportion', () {
    test('always adds up to the total', () {
      for (final total in [0, 1, 100, 99999, 1000001]) {
        final parts = apportion(total, {'a': 1, 'b': 1, 'c': 1});
        expect(parts.values.reduce((a, b) => a + b), total);
      }
    });

    test(
      'gives leftover paise to the largest remainders, ties to the first',
      () {
        expect(apportion(100, {'a': 1, 'b': 1, 'c': 1}), {
          'a': 34,
          'b': 33,
          'c': 33,
        });
        expect(apportion(1000, {'a': 1, 'b': 2}), {'a': 333, 'b': 667});
      },
    );

    test('rounds the same way whatever the order of people', () {
      expect(
        apportion(100, {'c': 1, 'b': 1, 'a': 1}),
        apportion(100, {'a': 1, 'b': 1, 'c': 1}),
      );
    });

    test('splits by weight', () {
      expect(apportion(120000, {'me': 3, 'r': 1}), {'me': 90000, 'r': 30000});
    });
  });
}
