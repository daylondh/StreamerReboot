import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/domain/liturgical_calendar.dart';

void main() {
  final calendar = LiturgicalCalendar(2026);

  test('calculates movable Easter-cycle dates', () {
    expect(calendar.nameFor(DateTime(2026, 2, 18)), 'Ash Wednesday');
    expect(calendar.nameFor(DateTime(2026, 4, 5)), 'Easter');
    expect(calendar.nameFor(DateTime(2026, 5, 24)), 'Pentecost');
    expect(
      calendar.nameFor(DateTime(2026, 6, 28)),
      'Fifth Sunday after Pentecost',
    );
  });

  test('calculates Advent and Thanksgiving', () {
    expect(calendar.nameFor(DateTime(2026, 11, 26)), 'Thanksgiving Day');
    expect(calendar.nameFor(DateTime(2026, 11, 29)), 'First Sunday in Advent');
  });

  test('provides a name for every day, including leap years', () {
    for (final year in [2026, 2028]) {
      final yearCalendar = LiturgicalCalendar(year);
      var date = DateTime(year, 1, 1);
      while (date.year == year) {
        expect(yearCalendar.nameFor(date), isNotEmpty, reason: '$date');
        date = date.add(const Duration(days: 1));
      }
    }
  });

  test('uses the original service time boundaries', () {
    expect(
      StreamTitleSuggester.serviceName(DateTime(2026, 6, 28, 8, 59)),
      'Early Service',
    );
    expect(
      StreamTitleSuggester.serviceName(DateTime(2026, 6, 28, 9)),
      'Single Service',
    );
    expect(
      StreamTitleSuggester.serviceName(DateTime(2026, 6, 28, 10, 5)),
      'Late Service',
    );
    expect(
      StreamTitleSuggester.serviceName(DateTime(2026, 6, 28, 11)),
      'Evening Service',
    );
  });
}
