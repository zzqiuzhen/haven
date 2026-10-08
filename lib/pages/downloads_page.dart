/// 下载与缓存管理
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cache_manager.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheManager>();
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    final active = cache.tasks.where((t) => t.state != 'done').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载与缓存'),
        actions: [
          IconButton(
            tooltip: '清空全部缓存',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('清空全部缓存？'),
                content: const Text('将删除所有已下载的章节音频。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: C.red),
                    onPressed: () {
                      Navigator.pop(ctx);
                      cache.clearAll();
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, ({int count, int bytes})>>(
        future: cache.allBooks(),
        builder: (context, snap) {
          final books = snap.data ?? const {};
          if (active.isEmpty && books.isEmpty) {
            return const EmptyView('还没有缓存内容\n播放时会自动缓存后续章节', icon: Icons.download_done_outlined);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (active.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('进行中', style: TS.h2)),
                for (final t in active)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: dark ? C.dCard : Colors.white, borderRadius: R.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${app.itemCache[t.bookId]?.meta.title ?? t.bookId.substring(0, 8)} · ${t.ino}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ProgressLine(t.progress, height: 4),
                        const SizedBox(height: 5),
                        Text(
                          t.state == 'failed'
                              ? '失败：${t.error ?? ''}'
                              : t.state == 'queued'
                                  ? '排队中…'
                                  : '${fmtBytes(t.received)}${t.total > 0 ? ' / ${fmtBytes(t.total)}' : ''}',
                          style: TextStyle(fontSize: 11, color: t.state == 'failed' ? C.red : C.text2),
                        ),
                      ],
                    ),
                  ),
              ],
              if (books.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('已缓存', style: TS.h2)),
                for (final e in books.entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: dark ? C.dCard : Colors.white, borderRadius: R.card),
                    child: Row(
                      children: [
                        HavenCover(e.key, app.itemCache[e.key]?.meta.title ?? '', size: 46, radius: 10),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.itemCache[e.key]?.meta.title ?? e.key.substring(0, 8), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text('${e.value.count} 章 · ${fmtBytes(e.value.bytes.toDouble())}', style: TS.mini),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: C.text2),
                          onPressed: () => cache.deleteBook(e.key),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
