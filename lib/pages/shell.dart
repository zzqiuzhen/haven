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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayerBar(),
                HavenNavBar(index: app.tab, onChanged: app.setTab),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    if (!engine.hasBook) return const SizedBox.shrink();
    final item = engine.item!;
    final t = engine.track;
    final progress = engine.duration > 0 ? (engine.absolute / engine.duration).clamp(0.0, 1.0).toDouble() : 0.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(PlayerPage.route()),
      onLongPress: () => _showActions(context, engine),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Glass(
          radius: 20,
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      HavenCover(item.id, item.meta.title, size: 44, radius: 10),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.text2)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: engine.toggle,
                        icon: Icon(engine.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34, color: C.navy),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ProgressLine(progress, height: 2.5),
                ),
              ],
            ),
          ),
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
