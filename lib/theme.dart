import 'package:flutter/material.dart';

/// Haven 设计令牌 —— 视觉语言参考 Leelaa Reader：暖白底、圆角卡片、蓝调主色、深蓝播放键
class C {
  // 亮色
  static const bg = Color(0xFFF5F6F8);
  static const card = Color(0xFFFFFFFF);
  static const cardSoft = Color(0xFFF8F9FB);
  static const primary = Color(0xFF2F80ED);
  static const primarySoft = Color(0xFFD6E9FF);
  static const navy = Color(0xFF1B2A43);
  static const text = Color(0xFF1C1C1E);
  static const text2 = Color(0xFF6B6B70);
  static const text3 = Color(0xFFB3B7BD);
  static const line = Color(0xFFECEDF0);
  static const green = Color(0xFF34C759);
  static const teal = Color(0xFF10B981);
  static const orange = Color(0xFFF2994A);
  static const red = Color(0xFFE5484D);
  static const purple = Color(0xFF8B5CF6);
  static const yellow = Color(0xFFF5C518);

  // 深色
  static const dBg = Color(0xFF0F1318);
  static const dCard = Color(0xFF1A2027);
  static const dCardSoft = Color(0xFF20262E);
  static const dText = Color(0xFFF2F3F5);
  static const dText2 = Color(0xFF9BA1A8);
  static const dLine = Color(0xFF262D36);
}

/// 常用圆角
class R {
  static const card = BorderRadius.all(Radius.circular(16));
  static const chip = BorderRadius.all(Radius.circular(18));
  static const cover = BorderRadius.all(Radius.circular(12));
  static const pill = BorderRadius.all(Radius.circular(999));
}

class HavenTheme {
  static ThemeData of(Brightness b) {
    final dark = b == Brightness.dark;
    final bg = dark ? C.dBg : C.bg;
    final surface = dark ? C.dCard : C.card;
    final text = dark ? C.dText : C.text;
    final text2 = dark ? C.dText2 : C.text2;
    final line = dark ? C.dLine : C.line;

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: C.primary,
        brightness: b,
      ).copyWith(
        primary: C.primary,
        surface: surface,
        onSurface: text,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    TextStyle t(double size, FontWeight w, {Color? color, double? h, double ls = 0}) =>
        TextStyle(fontSize: size, fontWeight: w, color: color ?? text, height: h, letterSpacing: ls);

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: text,
        titleTextStyle: t(20, FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: R.card),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 0.7, space: 0.7),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? C.dCardSoft : Colors.white,
        hintStyle: t(15, FontWeight.w400, color: text2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: R.card, borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: R.card, borderSide: BorderSide(color: line)),
        focusedBorder: const OutlineInputBorder(
          borderRadius: R.card,
          borderSide: BorderSide(color: C.primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF2A313A) : const Color(0xFF2B2F36),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: R.card),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: R.card),
        titleTextStyle: t(17, FontWeight.w700),
        contentTextStyle: t(14.5, FontWeight.w400, color: text2),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 4,
        activeTrackColor: C.primary,
        inactiveTrackColor: dark ? C.dLine : const Color(0xFFE5E7EB),
        thumbColor: C.primary,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: t(22, FontWeight.w700),
        titleMedium: t(17, FontWeight.w600),
        titleSmall: t(15, FontWeight.w600),
        bodyLarge: t(16, FontWeight.w400),
        bodyMedium: t(14.5, FontWeight.w400),
        bodySmall: t(12.5, FontWeight.w400, color: text2),
        labelLarge: t(15, FontWeight.w600),
        labelSmall: t(11, FontWeight.w400, color: text2),
      ),
    );
  }
}

/// 便捷文字样式
class TS {
  static const h1 = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15);
  static const h2 = TextStyle(fontSize: 19, fontWeight: FontWeight.w700);
  static const title = TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600);
  static const sub = TextStyle(fontSize: 13, color: C.text2);
  static const mini = TextStyle(fontSize: 11.5, color: C.text2);
}
