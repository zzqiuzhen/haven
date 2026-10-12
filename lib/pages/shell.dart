/// 主壳：四个 Tab + 悬浮导航 + 迷你播放器
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../player_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'me_page.dart';
import 'player_page.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(
            child: IndexedStack(
              index: app.tab,
              children: const [HomePage(), LibraryPage(), MePage()],
            ),
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: BottomDock()),
        ],
      ),
    );
  }
}

/// 单层液态玻璃 Dock：播放中时顶部为迷你播放器行，下面是导航行，共用同一块玻璃
class BottomDock extends StatelessWidget {
  const BottomDock({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final engine = context.watch<PlayerEngine>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showMini = engine.hasBook;
    // 底部导航项：按设置过滤（「我的」始终保留），并映射到真实 tab 下标
    final entries = <(IconData, IconData, String, int)>[
      if (app.navShowDiscover) (Icons.explore_outlined, Icons.explore, '发现', 0),
      if (app.navShowLibrary) (Icons.library_books_outlined, Icons.library_books, '书库', 1),
      (Icons.person_outline, Icons.person, '我的', 2),
    ];
    final iconsOnly = app.navIconsOnly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Glass(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMini) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque, // 整条小条（含文字/封面/进度环/空白处）都可点开全屏播放页；仅播放键保留暂停功能
                onTap: () => Navigator.of(context).push(PlayerPage.route()),
                onLongPress: () => _showActions(context, engine),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Row(
                    children: [
                      HavenCover(engine.item!.id, engine.item!.meta.title, size: 40, radius: 9),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(engine.item!.meta.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(engine.item == null ? '' : trackDisplayTitle(engine.item!.meta.title, engine.track?.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: C.text2)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MiniProgress(engine: engine),
                      IconButton(
                        onPressed: engine.toggle,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          engine.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          size: 32,
                          color: C.navy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
            SizedBox(
              height: iconsOnly ? 46 : 54,
              child: Row(
                children: [
                  for (final e in entries)
                    Expanded(
                      child: _DockItem(
                        icon: e.$1,
                        iconActive: e.$2,
                        label: e.$3,
                        selected: e.$4 == app.tab,
                        dark: dark,
                        iconsOnly: iconsOnly,
                        haptic: app.hapticFeedback,
                        onTap: () => app.setTab(e.$4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, PlayerEngine engine) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined, color: C.red),
              title: const Text('停止播放并关闭会话'),
              onTap: () {
                Navigator.pop(ctx);
                engine.stopAndClose();
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开播放页'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(PlayerPage.route());
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你进度环（显示全书进度）
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.engine});
  final PlayerEngine engine;

  @override
  Widget build(BuildContext context) {
    final frac = engine.duration > 0 ? (engine.absolute / engine.duration).clamp(0.0, 1.0).toDouble() : 0.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(
        value: frac,
        strokeWidth: 2.4,
        backgroundColor: dark ? C.dLine : const Color(0xFFE5E7EB),
        valueColor: const AlwaysStoppedAnimation(C.primary),
      ),
    );
  }
}


/// 状态栏按钮：点击弹跳动画 + 触觉反馈
class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.icon,
    required this.iconActive,
    required this.label,
    required this.selected,
    required this.dark,
    required this.iconsOnly,
    required this.haptic,
    required this.onTap,
  });
  final IconData icon;
  final IconData iconActive;
  final String label;
  final bool selected;
  final bool dark;
  final bool iconsOnly;
  final bool haptic;
  final VoidCallback onTap;
  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  /// 弹跳：1.0 → 1.22 → 1.0（带过冲回落）
  static final Animatable<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.22).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 38),
    TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 62),
  ]);

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.haptic) HapticFeedback.lightImpact();
    _pop.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) => Transform.scale(scale: _popScale.evaluate(_pop), child: child),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.iconsOnly ? 5 : 3),
              decoration: BoxDecoration(
                color: widget.selected
                    ? (widget.dark ? C.primary.withValues(alpha: 0.18) : C.primarySoft.withValues(alpha: 0.8))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                widget.selected ? widget.iconActive : widget.icon,
                size: 22,
                color: widget.selected ? C.primary : C.text2,
              ),
            ),
            if (!widget.iconsOnly) ...[
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.selected ? C.primary : C.text2,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
