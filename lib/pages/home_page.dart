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
          padding: const EdgeInsets.only(bottom: 178),
          children: [
            const _Header(),
            if (app.loadingHome && app.continueList.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            _ContinueSection(app: app),
            _StatsSection(stats: app.stats),
            _NewSection(app: app),
            _LibSection(app: app),
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

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const BlobBackground(height: 140),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('发现', style: TS.h1),
              const SizedBox(height: 4),
              Text(todayLabel(), style: TS.sub),
            ],
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('继续收听'),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: app.continueList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final (it, pg) = app.continueList[i];
              return _ContinueCard(item: it, pg: pg);
            },
          ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final frac = (pg.progress > 0 ? pg.progress : (pg.duration > 0 ? pg.currentTime / pg.duration : 0)).clamp(0.0, 1.0).toDouble();
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 286,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? C.dCard : Colors.white,
          borderRadius: R.card,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.3 : 0.05), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            HavenCover(item.id, item.meta.title, size: 78, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(item.meta.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.text2)),
                  const SizedBox(height: 8),
                  ProgressLine(frac, height: 4),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(fmtDur(pg.currentTime), style: TS.mini),
                      const Spacer(),
                      Text('${(frac * 100).toStringAsFixed(0)}%', style: TS.mini),
                    ],
                  ),
                ],
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
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: dark ? c.$4.withValues(alpha: 0.12) : c.$4.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$1, style: const TextStyle(fontSize: 12.5, color: C.text2)),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(c.$2, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
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
    final items = (app.libItems[firstLib.id] ?? const <LibItem>[]).take(12).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('最新入库', onMore: () => app.setTab(1)),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final it = items[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: it))),
                child: SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HavenCover(it.id, it.meta.title, size: 112, radius: 12),
                      const SizedBox(height: 7),
                      Text(it.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(it.meta.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.text2)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                    onTap: () => app.setTab(1),
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
