import 'package:flutter_test/flutter_test.dart';

import 'package:bills/main.dart';

void main() {
  group('bill input and date logic', () {
    test('matches the selected date exactly', () {
      final selectedDate = DateTime(2026, 8, 19);
      final bill = Bill(
        title: 'Rent',
        description: 'Apartment',
        amount: 2500,
        dueDate: DateTime(2026, 8, 19, 9, 0),
        iconCodePoint: 0,
      );

      expect(matchesDateFilter(bill.dueDate, selectedDate), isTrue);
    });

    test('searches bills by title or description', () {
      final bill = Bill(
        title: 'Electricity',
        description: 'Home power bill',
        amount: 1250,
        dueDate: DateTime(2026, 8, 19),
        iconCodePoint: 0,
      );

      expect(matchesBillSearch(bill, 'electric'), isTrue);
      expect(matchesBillSearch(bill, 'POWER'), isTrue);
      expect(matchesBillSearch(bill, 'rent'), isFalse);
    });

    test('parses comma-formatted amounts', () {
      expect(parseAmountInput('1,250'), 1250);
      expect(parseAmountInput('2,345.50'), 2345.5);
      expect(parseAmountInput('1,00,000'), 100000);
      expect(parseAmountInput(''), isNull);
    });
  });
}
