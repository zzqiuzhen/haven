/// 通用 UI 组件
library;

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// 封面（带鉴权头 + 占位色块）
class HavenCover extends StatelessWidget {
  const HavenCover(this.itemId, this.title, {super.key, this.size, this.width, this.height, this.radius = 12, this.api});
  final String? itemId;
  final String title;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final Api? api;

  static const _palette = [
    Color(0xFF5B7CFA), Color(0xFF8B5CF6), Color(0xFF10B981), Color(0xFFF2994A),
    Color(0xFFE5484D), Color(0xFF0EA5E9), Color(0xFFD946EF), Color(0xFF14B8A6),
  ];

  Color get _phColor {
    var h = 0;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final br = BorderRadius.circular(radius);
    final ph = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_phColor, Color.lerp(_phColor, Colors.black, 0.35)!],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title.characters.first : '书',
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
    if (itemId == null || itemId!.isEmpty) return ph;
    return ClipRRect(
      borderRadius: br,
      child: CachedNetworkImage(
        imageUrl: api?.coverUrl(itemId!) ?? '',
        httpHeaders: api?.authHeaders ?? const {},
        width: w,
        height: h,
        fit: BoxFit.cover,
        placeholder: (_, __) => ph,
        errorWidget: (_, __, ___) => ph,
        fadeInDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}

/// 细进度条
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.height = 4, this.color, this.bg});
  final double value;
  final double height;
  final Color? color;
  final Color? bg;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: bg ?? (dark ? C.dLine : const Color(0xFFE8EAEE)),
        valueColor: AlwaysStoppedAnimation(color ?? C.primary),
      ),
    );
  }
}

/// 区块标题（"最近阅读  ·  更多"）
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onMore, this.moreText = '全部'});
  final String title;
  final VoidCallback? onMore;
  final String moreText;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Text(title, style: TS.h2.copyWith(color: dark ? C.dText : C.text)),
          const Spacer(),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: Row(children: [
                Text(moreText, style: const TextStyle(fontSize: 13, color: C.text2)),
                const Icon(Icons.chevron_right, size: 16, color: C.text2),
              ]),
            ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.menu_book_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: C.text3),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(color: C.text2, fontSize: 14.5)),
      ]),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
}

/// 背景柔光斑（Leelaa 风格头部氛围）
class BlobBackground extends StatelessWidget {
  const BlobBackground({super.key, this.height = 210, this.color});
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? C.primary;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(children: [
          Positioned(
            right: -60, top: -80,
            child: _blob(dark ? base.withValues(alpha: 0.10) : base.withValues(alpha: 0.16), 300),
          ),
          Positioned(
            left: -80, top: 40,
            child: _blob(dark ? C.purple.withValues(alpha: 0.06) : C.purple.withValues(alpha: 0.10), 260),
          ),
        ]),
      ),
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}

/// 底部悬浮导航条（圆角浮岛 + 毛玻璃）
class HavenNavBar extends StatelessWidget {
  const HavenNavBar({super.key, required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.library_books_outlined, Icons.library_books, '书库'),
    (Icons.search, Icons.search, '搜索'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bar = Container(
      height: 62,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: (dark ? C.dCard : Colors.white).withValues(alpha: 0.92),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.07), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          for (int i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                      decoration: BoxDecoration(
                        color: i == index ? (dark ? C.primary.withValues(alpha: 0.18) : C.primarySoft) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        i == index ? _items[i].$2 : _items[i].$1,
                        size: 24,
                        color: i == index ? C.primary : C.text2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_items[i].$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: i == index ? C.primary : C.text2,
                          fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: bar),
    );
  }
}

/// 空状态图标小药丸标签
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? C.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: R.pill),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
    );
  }
}
