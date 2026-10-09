/// 离线下载面板（书籍页 / 播放页共用）：预设范围 / 整本 / 自定义 / 查看
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cache_manager.dart';
import '../consts.dart';
import '../models.dart';
import '../pages/downloads_page.dart';
import '../state.dart';
import '../theme.dart';

/// 打开离线下载菜单（转码书：章节自动走服务器缓存模式）
Future<void> showDownloadSheet({
  required BuildContext context,
  required LibItem item,
  BookDetail? detail,
  int? currentIndex,
}) async {
  final d = detail;
  if (d == null || d.tracks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('章节信息加载中，请稍后再试')));
    return;
  }
  final total = d.tracks.length;
  final ti = (currentIndex ?? 0).clamp(0, total - 1);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('离线下载', style: TS.title)),
        ListTile(
          leading: const Icon(Icons.playlist_add, color: C.primary),
          title: Text('从第 ${d.tracks[ti].index} 章缓存 10 章'),
          onTap: () {
            Navigator.pop(ctx);
            enqueueCacheRange(context, item, d, [for (int i = ti; i < ti + 10; i++) i]);
          },
        ),
        ListTile(
          leading: const Icon(Icons.download, color: C.purple),
          title: Text('缓存整本（共 $total 章）'),
          onTap: () {
            Navigator.pop(ctx);
            showDialog(
              context: context,
              builder: (dctx) => AlertDialog(
                title: const Text('缓存整本？'),
                content: Text('将对 $total 章排队下载，占用设备存储，建议在 Wi-Fi 下进行。'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(dctx);
                      enqueueCacheRange(context, item, d, [for (int i = 0; i < total; i++) i]);
                    },
                    child: const Text('开始'),
                  ),
                ],
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit_calendar_outlined, color: C.navy),
          title: const Text('自定义范围（手动输入起止集数）'),
          onTap: () {
            Navigator.pop(ctx);
            showCustomRangeDialog(context, item, d, defaultStart: d.tracks[ti].index);
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_open, color: C.teal),
          title: const Text('查看下载与缓存'),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsPage()));
          },
        ),
      ]),
    ),
  );
}

/// 手动输入起止集数 → 加入缓存队列
void showCustomRangeDialog(BuildContext context, LibItem item, BookDetail d, {required int defaultStart}) {
  final total = d.tracks.length;
  final startCtl = TextEditingController(text: '$defaultStart');
  final endCtl = TextEditingController(text: '${math.min(defaultStart + 9, total)}');
  showDialog(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('自定义缓存范围'),
      content: StatefulBuilder(
        builder: (sctx, setD) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('第'),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: startCtl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setD(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('集 到 第'),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: endCtl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => setD(() {}),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('集'),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('共 $total 集，支持手动输入起止集数', style: const TextStyle(fontSize: 12, color: C.text2)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final a = int.tryParse(startCtl.text.trim());
            final b = int.tryParse(endCtl.text.trim());
            if (a == null || b == null || a < 1 || b > total || a > b) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('请输入有效范围（1 ~ $total，且起始不大于结束）')));
              return;
            }
            Navigator.pop(dctx);
            enqueueCacheRange(context, item, d, [for (int i = a - 1; i <= b - 1; i++) i]);
          },
          child: const Text('开始缓存'),
        ),
      ],
    ),
  );
}

/// 把章节范围加入缓存队列（转码书章节自动跳过并提示）
void enqueueCacheRange(BuildContext context, LibItem item, BookDetail d, List<int> idx) {
  final cache = context.read<CacheManager>();
  final app = context.read<AppState>();
  var n = 0;
  for (final i in idx) {
    if (i < 0 || i >= d.tracks.length) continue;
    final t = d.tracks[i];
    if (t.ino.isEmpty) continue;
    final isTrans = codecNeedsTranscode(t.codec, t.mimeType);
    final url = isTrans
        ? app.api.transcodedFileUrlFor(item.id, t.ino)
        : app.api.fileUrlFor(item.id, t.ino);
    cache.enqueue(
      bookId: item.id,
      ino: t.ino,
      ext: isTrans ? '.m4a' : CacheManager.mediaExt(ext: t.ext, mimeType: t.mimeType, codec: t.codec),
      url: url,
    );
    n++;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入缓存队列（$n 章）')));
}
