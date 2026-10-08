/// 阅读记录
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'book_page.dart';

class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('阅读记录')),
      body: FutureBuilder<List<(LibItem, MediaProgress)>>(
        future: app.recentList(),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final list = snap.data!;
          if (list.isEmpty) return const EmptyView('还没有收听记录', icon: Icons.history);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final (it, pg) = list[i];
              final frac = (pg.progress > 0 ? pg.progress : (pg.duration > 0 ? pg.currentTime / pg.duration : 0)).clamp(0.0, 1.0).toDouble();
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: it))),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: dark ? C.dCard : Colors.white, borderRadius: R.card),
                  child: Row(
                    children: [
                      HavenCover(it.id, it.meta.title, size: 54, radius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            ProgressLine(frac, height: 3.5),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(fmtAgo(pg.updatedAt), style: TS.mini),
                                const Spacer(),
                                Text('${(frac * 100).toStringAsFixed(0)}% · ${fmtDur(pg.currentTime)}', style: TS.mini),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
