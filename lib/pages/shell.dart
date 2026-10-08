/// 主壳：四个 Tab + 悬浮导航 + 迷你播放器
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../player_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'me_page.dart';
import 'player_page.dart';
import 'search_page.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: app.tab,
              children: const [HomePage(), LibraryPage(), SearchPage(), MePage()],
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

  static const _items = [
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.library_books_outlined, Icons.library_books, '书库'),
    (Icons.search, Icons.search, '搜索'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final engine = context.watch<PlayerEngine>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showMini = engine.hasBook;

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
                            Text(engine.track?.title ?? '',
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
              Divider(
                height: 1,
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                indent: 10,
                endIndent: 10,
              ),
              const SizedBox(height: 2),
            ],
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  for (int i = 0; i < _items.length; i++)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => app.setTab(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                              decoration: BoxDecoration(
                                color: i == app.tab
                                    ? (dark ? C.primary.withValues(alpha: 0.18) : C.primarySoft.withValues(alpha: 0.8))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                i == app.tab ? _items[i].$2 : _items[i].$1,
                                size: 22,
                                color: i == app.tab ? C.primary : C.text2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _items[i].$3,
                              style: TextStyle(
                                fontSize: 10,
                                color: i == app.tab ? C.primary : C.text2,
                                fontWeight: i == app.tab ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
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
