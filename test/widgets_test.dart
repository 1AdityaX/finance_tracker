import 'package:finance_tracker/screens/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortDate names recent days and keeps day and month together', () {
    final now = DateTime.now();
    expect(shortDate(now), 'Today');
    expect(shortDate(DateUtils.addDaysToDate(now, -1)), 'Yesterday');
    final earlier = DateTime(now.year - 1, 10, 3);
    expect(shortDate(earlier), '3\u00A0Oct\u00A0${now.year - 1}');
  });
}
