/// 首页 · 发现
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../player_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'book_page.dart';
import 'player_page.dart';
import 'recent_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: app.refreshHome,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 220),
          children: [
            const _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: GestureDetector(
                onTap: () => app.setTab(2),
                child: Glass(
                  radius: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: const Row(children: [
                    Icon(Icons.search, size: 18, color: C.text2),
                    SizedBox(width: 9),
                    Text('搜索书名 / 作者 / 章节', style: TextStyle(fontSize: 14, color: C.text2)),
                  ]),
                ),
              ),
            ),
            if (app.loadingHome && app.continueList.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            for (final m in app.homeModules)
              if (m.$2) _module(m.$1, app),
            if (app.homeError != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('加载失败：${app.homeError}', style: const TextStyle(color: C.red, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 按设置渲染发现页模块
Widget _module(String id, AppState app) {
  switch (id) {
    case 'continue':
      return _ContinueSection(app: app);
    case 'stats':
      return _StatsSection(stats: app.stats);
    case 'new':
      return _NewSection(app: app);
    case 'libs':
      return _LibSection(app: app);
  }
  return const SizedBox.shrink();
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Text('发现', style: TS.h1),
    );
  }
}

class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.continueList.isEmpty) {
      return const SizedBox.shrink();
    }
    final (it, pg) = app.continueList.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('继续收听', onMore: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecentPage()));
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ContinueCard(item: it, pg: pg),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.pg});
  final LibItem item;
  final MediaProgress pg;

  void _open(BuildContext context) {
    final engine = context.read<PlayerEngine>();
    final app = context.read<AppState>();
    // 先立即跳转播放页（即时反馈），再在后台加载会话与音源，避免等待导致“点不动”
    Navigator.of(context).push(PlayerPage.route());
    if (engine.hasBook && engine.item?.id == item.id && engine.session == null) {
      // 恢复态：直接从恢复位置起播
      unawaited(engine.toggle());
    } else {
      unawaited(engine.open(item, startAt: app.resumeAbsFor(item.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final frac = (pg.progress > 0 ? pg.progress : (pg.duration > 0 ? pg.currentTime / pg.duration : 0)).clamp(0.0, 1.0).toDouble();
    final remain = (pg.duration - pg.currentTime).clamp(0.0, double.infinity).toDouble();
    final sub = '${item.meta.authorText}${item.meta.narrators.isNotEmpty ? ' · ${item.meta.narratorText} 演播' : ''}';
    return GestureDetector(
      onTap: () => _open(context),
      child: Glass(
        radius: 20,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            HavenCover(item.id, item.meta.title, size: 96, radius: 16),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.text2)),
                  const SizedBox(height: 11),
                  ProgressLine(frac, height: 5),
                  const SizedBox(height: 7),
                  Text('已听 ${(frac * 100).toStringAsFixed(0)}% · 还剩 ${fmtDur(remain)}', style: const TextStyle(fontSize: 11, color: C.text2)),
                ],
              ),
            ),
            const SizedBox(width: 13),
            GestureDetector(
              onTap: () => _open(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF33456F), Color(0xFF0F1830)]),
                  boxShadow: [BoxShadow(color: Color(0x590F1830), blurRadius: 12, offset: Offset(0, 5))],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.stats});
  final ListeningStats stats;

  (String, String) _hr(double sec) {
    if (sec >= 3600) return ((sec / 3600).toStringAsFixed(1), '小时');
    if (sec >= 60) return ((sec / 60).toStringAsFixed(0), '分钟');
    return (sec.round().toString(), '秒');
  }

  @override
  Widget build(BuildContext context) {
    if (stats.totalTime <= 0 && stats.today <= 0 && stats.days.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = _hr(stats.today);
    final w = _hr(stats.last7);
    final all = _hr(stats.totalTime);
    final cards = [
      ('今日聆听', t.$1, t.$2, C.primary),
      ('本周探索', w.$1, w.$2, C.orange),
      ('连续收听', '${stats.streak}', '天', C.teal),
      ('累计时长', all.$1, all.$2, C.purple),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('聆听数据'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.05,
            children: [
              for (final c in cards)
                Glass(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$1, style: const TextStyle(fontSize: 12.5, color: C.text2)),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(c.$2, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 3),
                          Text(c.$3, style: const TextStyle(fontSize: 12, color: C.text2)),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NewSection extends StatelessWidget {
  const _NewSection({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final firstLib = app.libraries.isNotEmpty ? app.libraries.first : null;
    if (firstLib == null) return const SizedBox.shrink();
    final items = (app.libItems[firstLib.id] ?? const <LibItem>[]).take(3).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('最新入库', onMore: () => app.setTab(1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _NewTile(item: items[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.item});
  final LibItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: item))),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, cons) {
            return HavenCover(item.id, item.meta.title, width: cons.maxWidth, height: cons.maxWidth, radius: 15);
          }),
          const SizedBox(height: 7),
          Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LibSection extends StatelessWidget {
  const _LibSection({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.libraries.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tints = [C.primary, C.purple, C.teal, C.orange];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('我的书库'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (int i = 0; i < app.libraries.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => app.openLibrary(app.libraries[i].id),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: dark ? tints[i % 4].withValues(alpha: 0.12) : tints[i % 4].withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.library_books_rounded, color: tints[i % 4], size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(app.libraries[i].name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('共 ${app.libTotals[app.libraries[i].id] ?? app.libraries[i].numItems ?? '-'} 本', style: TS.mini),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: C.text2),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
