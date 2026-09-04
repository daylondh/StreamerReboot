class LiturgicalCalendar {
  LiturgicalCalendar(this.year) {
    _entries = List<String?>.filled(_isLeapYear ? 366 : 365, null);
    _buildYear();
  }

  final int year;
  late final List<String?> _entries;
  late int _pentecost;
  late int _firstAdvent;

  bool get _isLeapYear => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  String nameFor(DateTime date) {
    if (date.year != year) return LiturgicalCalendar(date.year).nameFor(date);
    return _entries[_dayOfYear(date)] ?? 'Service';
  }

  void _buildYear() {
    _addFixedDates();
    _buildToPentecost();
    _buildAdvent();
    _buildPentecost();
    _buildThanksgiving();
  }

  void _addFixedDates() {
    const dates = <(int, int), String>{
      (1, 1): "New Year's Day",
      (1, 6): 'Epiphany',
      (7, 4): 'Independence Day',
      (10, 31): 'Reformation Day',
      (11, 1): 'All Saints Day',
      (11, 11): 'Veterans Day',
      (12, 24): 'Christmas Eve',
      (12, 25): 'Christmas Day',
      (12, 31): "New Year's Eve",
    };
    for (final entry in dates.entries) {
      _entries[_dayOfYear(DateTime(year, entry.key.$1, entry.key.$2))] =
          entry.value;
    }
  }

  void _buildToPentecost() {
    final easter = _easterDate(year);
    final easterDay = _dayOfYear(easter);
    _entries[easterDay] = 'Easter';
    final ashWednesday = easterDay - 46;
    _entries[ashWednesday] = 'Ash Wednesday';
    _entries[ashWednesday - 3] = 'Transfiguration';

    for (var i = 0; i < ashWednesday - 3; i++) {
      if (_entries[i] != null) continue;
      if (i < 6) {
        _entries[i] = 'Second ${_weekday(i)} after Christmas';
      } else if (i < 13 && _weekday(i) == 'Sunday') {
        _entries[i] = 'Baptism of Our Lord';
      } else {
        final week = (i - 5) ~/ 7 + 1;
        _entries[i] = '${_ordinal(week)}${_weekday(i)} after Epiphany';
      }
    }

    _entries[ashWednesday - 2] = 'Monday after Transfiguration';
    _entries[ashWednesday - 1] = 'Tuesday after Transfiguration';
    for (var i = ashWednesday - 3; i < easterDay - 7; i++) {
      if (_entries[i] == null) {
        final week = (i - ashWednesday + 6) ~/ 7;
        _entries[i] = '${_ordinal(week)}${_weekday(i)} of Lent';
      }
    }

    const holyWeek = [
      'Passion Sunday',
      'Monday in Holy Week',
      'Tuesday in Holy Week',
      'Wednesday in Holy Week',
      'Maundy Thursday',
      'Good Friday',
      'Holy Saturday',
    ];
    for (var i = 0; i < holyWeek.length; i++) {
      _entries[easterDay - 7 + i] = holyWeek[i];
    }
    const easterWeek = [
      'Easter Monday',
      'Easter Tuesday',
      'Easter Wednesday',
      'Easter Thursday',
      'Easter Friday',
      'Easter Saturday',
    ];
    for (var i = 0; i < easterWeek.length; i++) {
      _entries[easterDay + i + 1] = easterWeek[i];
    }
    for (var i = easterDay + 7; i < easterDay + 48; i++) {
      if (_entries[i] == null) {
        final week = (i - easterDay) ~/ 7 + 1;
        _entries[i] = '${_ordinal(week)}${_weekday(i)} of Easter';
      }
    }
    _pentecost = easterDay + 49;
    _entries[_pentecost - 1] = 'Pentecost Eve';
    _entries[_pentecost] = 'Pentecost';
  }

  void _buildAdvent() {
    final november30 = DateTime(year, 11, 30);
    final daysFromSunday = november30.weekday % 7;
    final advent = daysFromSunday < 5
        ? november30.subtract(Duration(days: daysFromSunday))
        : november30.add(Duration(days: 7 - daysFromSunday));
    _firstAdvent = _dayOfYear(advent);

    const lastWeek = [
      'Last Sunday Of The Church Year',
      'Last Monday Of The Church Year',
      'Last Tuesday Of The Church Year',
      'Last Wednesday Of The Church Year',
      'Last Thursday Of The Church Year',
      'Last Friday Of The Church Year',
      'Last Saturday Of The Church Year',
    ];
    for (var i = 0; i < lastWeek.length; i++) {
      _entries[_firstAdvent - 7 + i] = lastWeek[i];
    }
    _entries[_firstAdvent] = 'First Sunday in Advent';
    final christmas = _dayOfYear(DateTime(year, 12, 25));
    for (var i = _firstAdvent; i < christmas; i++) {
      _entries[i] ??=
          '${_ordinal((i - _firstAdvent) ~/ 7 + 1)}${_weekday(i)} in Advent';
    }
    for (var i = christmas + 1; i < _entries.length; i++) {
      _entries[i] ??=
          '${_ordinal((i - christmas) ~/ 7 + 1)}${_weekday(i)} of Christmas';
    }
  }

  void _buildPentecost() {
    const pentecostWeek = [
      'Pentecost Monday',
      'Pentecost Tuesday',
      'Pentecost Wednesday',
      'Pentecost Thursday',
      'Pentecost Friday',
      'Pentecost Saturday',
      'Holy Trinity Sunday',
    ];
    for (var i = 0; i < pentecostWeek.length; i++) {
      _entries[_pentecost + i + 1] = pentecostWeek[i];
    }
    for (var i = _pentecost + 8; i <= _firstAdvent - 8; i++) {
      _entries[i] ??=
          '${_ordinal((i - _pentecost) ~/ 7)}${_weekday(i)} after Pentecost';
    }
  }

  void _buildThanksgiving() {
    var date = DateTime(year, 11, 1);
    while (date.weekday != DateTime.thursday) {
      date = date.add(const Duration(days: 1));
    }
    final thanksgiving = date.add(const Duration(days: 21));
    final day = _dayOfYear(thanksgiving);
    _entries[day - 1] = 'Thanksgiving Eve';
    _entries[day] = 'Thanksgiving Day';
  }

  int _dayOfYear(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(date.year, 1, 1)).inDays;

  String _weekday(int day) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][DateTime(year, 1, 1).add(Duration(days: day)).weekday - 1];

  String _ordinal(int value) {
    const names = [
      '',
      'First ',
      'Second ',
      'Third ',
      'Fourth ',
      'Fifth ',
      'Sixth ',
      'Seventh ',
      'Eighth ',
      'Ninth ',
      'Tenth ',
      'Eleventh ',
      'Twelfth ',
      'Thirteenth ',
      'Fourteenth ',
      'Fifteenth ',
      'Sixteenth ',
      'Seventeenth ',
      'Eighteenth ',
      'Nineteenth ',
      'Twentieth ',
      'Twenty-First ',
      'Twenty-Second ',
      'Twenty-Third ',
      'Twenty-Fourth ',
      'Twenty-Fifth ',
      'Twenty-Sixth ',
      'Twenty-Seventh ',
      'Twenty-Eighth ',
      'Twenty-Ninth ',
    ];
    return value >= 0 && value < names.length ? names[value] : '$value-th ';
  }

  static DateTime _easterDate(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final g = (8 * b + 13) ~/ 25;
    final h = (19 * a + b - d - g + 15) % 30;
    final j = c ~/ 4;
    final k = c % 4;
    final m = (a + 11 * h) ~/ 319;
    final r = (2 * e + 2 * j - k - h + m + 32) % 7;
    final month = (h - m + r + 90) ~/ 25;
    final day = (h - m + r + month + 19) % 32;
    return DateTime(year, month, day);
  }
}

class StreamTitleSuggester {
  static String suggest(DateTime now) =>
      '${LiturgicalCalendar(now.year).nameFor(now)} - ${serviceName(now)}';

  static String serviceName(DateTime now) {
    if (now.hour < 9) return 'Early Service';
    if (now.hour < 10 || (now.hour == 10 && now.minute < 5)) {
      return 'Single Service';
    }
    if (now.hour == 10) return 'Late Service';
    return 'Evening Service';
  }
}
