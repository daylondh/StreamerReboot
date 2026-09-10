import 'package:flutter/material.dart';

const kAccentLime = Color(0xff00ff0f);
const kAccentBlue = Color(0xff00aeff);
const kAccentTeal = Color(0xff00de94);
const kAccentGreen = Color(0xff00ff52);

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    colorScheme: const ColorScheme.light(
      primary: kAccentBlue,
      onPrimary: Colors.black,
      secondary: kAccentTeal,
      onSecondary: Colors.black,
      tertiary: kAccentGreen,
      onTertiary: Colors.black,
      surface: Colors.white,
      onSurface: Colors.black,
      error: Colors.black,
      onError: Colors.black,
    ),
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0x26000000)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0x26000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kAccentBlue, width: 1.5),
      ),
      filled: true,
      fillColor: Color(0xfffafafa),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
      showDuration: Duration(seconds: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      textStyle: TextStyle(color: Colors.white, fontSize: 13),
      decoration: BoxDecoration(
        color: Color(0xff252525),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 1,
      shadowColor: Color(0x18000000),
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Color(0x22000000)),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}
