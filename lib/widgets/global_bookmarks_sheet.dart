/// 全局书签面板：聚合所有书的书签，点击直达对应章节
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../pages/player_page.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';

Future<void> showGlobalBookmarksSheet({required BuildContext context}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _GlobalBookmarksSheet(),
  );
}

class _GlobalBookmarksSheet extends StatefulWidget {
  const _GlobalBookmarksSheet();
  @override
  State<_GlobalBookmarksSheet> createState() => _GlobalBookmarksSheetState();
}

class _GlobalBookmarksSheetState extends State<_GlobalBookmarksSheet> {
  List<Map<String, dynamic>>? _list; // null=加载中
  bool _syncing = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> l) {
    final out = [...l];
    out.sort((a, b) => ((b['ts'] as num?)?.toInt() ?? 0).compareTo((a['ts'] as num?)?.toInt() ?? 0));
    return out;
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.settings.bookmarksSeeded) {
      await _rescan();
      return;
    }
    setState(() => _list = _sorted(app.settings.bookmarkIndex));
  }

  Future<void> _rescan() async {
    final app = context.read<AppState>();
    setState(() {
      _syncing = true;
      _done = 0;
      _total = 0;
      _list = null;
    });
    try {
      // 汇总候选书目：所有书库 + 继续收听 + 当前播放 + 本地索引里已有的
      final items = <String, LibItem>{};
      for (final l in app.libraries) {
        var list = app.libItems[l.id] ?? const <LibItem>[];
        if (list.isEmpty) {
          try {
            list = await app.loadLibrary(l.id, page: 0);
          } catch (_) {
            list = const <LibItem>[];
          }
        }
        for (final it in list) {
          items[it.id] = it;
        }
      }
      for (final (it, _) in app.continueList) {
        items[it.id] = it;
      }
      final eng = app.engine.item;
      if (eng != null) items[eng.id] = eng;
      for (final e in app.settings.bookmarkIndex) {
        final id = e['itemId']?.toString() ?? '';
        if (id.isEmpty || items.containsKey(id)) continue;
        try {
          items[id] = await app.ensureItem(id);
        } catch (_) {}
      }
      final ids = items.keys.toList();
      setState(() => _total = ids.length);
      final found = <Map<String, dynamic>>[];
      const batch = 6;
      for (var i = 0; i < ids.length; i += batch) {
        final end = (i + batch > ids.length) ? ids.length : i + batch;
        final slice = ids.sublist(i, end);
        await Future.wait(slice.map((id) async {
          final it = items[id];
          if (it != null) {
            try {
              final bs = await app.api.bookmarks(id);
              for (final b in bs) {
                found.add({
                  'itemId': id,
                  'bookTitle': it.meta.title,
                  'author': it.meta.authorText,
                  'time': b.time,
                  'title': b.title,
                  'ts': b.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
                });
              }
            } catch (_) {}
          }
          if (mounted) setState(() => _done += 1);
        }));
      }
      await app.settings.syncBookmarksFromServer(items.keys.toSet(), found);
      await app.settings.setBookmarksSeeded(true);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _syncing = false;
        _list = _sorted(context.read<AppState>().settings.bookmarkIndex);
      });
    }
  }

  Future<void> _jump(Map<String, dynamic> e) async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final itemId = e['itemId']?.toString() ?? '';
    final time = (e['time'] as num?)?.toDouble() ?? 0;
    if (itemId.isEmpty || time <= 0) return;
    Navigator.pop(context);
    nav.push(PlayerPage.route());
    try {
      final it = await app.ensureItem(itemId);
      if (app.engine.hasBook && app.engine.item?.id == itemId) {
        await app.engine.seekAbsolute(time);
      } else {
        await app.engine.open(it, startAt: time);
      }
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('跳转失败：$err')));
    }
  }

  Future<void> _remove(Map<String, dynamic> e) async {
    final app = context.read<AppState>();
    final itemId = e['itemId']?.toString() ?? '';
    final time = (e['time'] as num?)?.toDouble() ?? 0;
    try {
      final it = await app.ensureItem(itemId);
      await app.removeBookmarkAt(it, time);
    } catch (_) {}
    if (mounted) setState(() => _list?.remove(e));
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final hint = Theme.of(context).hintColor;
    return SafeArea(
      child: SizedBox(
        height: 480,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(children: [
              const Icon(Icons.bookmarks, size: 20, color: C.primary),
              const SizedBox(width: 8),
              const Text('书签', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (list != null && !_syncing) Text('共 ${list.length} 个', style: TextStyle(fontSize: 12, color: hint)),
              const Spacer(),
              IconButton(onPressed: _syncing ? null : _rescan, icon: const Icon(Icons.refresh, size: 20)),
            ]),
          ),
          const Divider(height: 1),
          if (_syncing)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(strokeWidth: 2.5),
                  const SizedBox(height: 14),
                  Text(_total > 0 ? '正在同步书签 $_done / $_total …' : '正在同步书签…', style: TextStyle(fontSize: 12.5, color: hint)),
                ]),
              ),
            )
          else
            Expanded(child: _buildBody(list)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Text('点击书签直达对应章节播放；在播放页 / 书籍页可添加书签', style: TextStyle(fontSize: 11.5, color: hint)),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>>? list) {
    if (list == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '暂无书签\n播放时点书签图标添加，之后从这里一键直达',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.6),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final e = list[i];
        final bookTitle = e['bookTitle']?.toString() ?? '';
        final chTitle = e['title']?.toString() ?? '';
        final time = (e['time'] as num?)?.toDouble() ?? 0;
        return ListTile(
          leading: const Icon(Icons.bookmark, color: C.primary),
          title: Text(bookTitle.isEmpty ? '未知书籍' : bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${chTitle.isEmpty ? '章节书签' : chTitle} · ${fmtDur(time)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _remove(e),
          ),
          onTap: () => _jump(e),
        );
      },
    );
  }
}
