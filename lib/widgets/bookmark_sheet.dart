/// 书签管理面板：列出全部书签、点击跳转定位播放、删除
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../player_engine.dart';
import '../state.dart';
import '../util.dart';
import '../pages/player_page.dart';

/// 打开书签面板（书籍页 / 播放页共用）
Future<void> showBookmarkSheet({
  required BuildContext context,
  required Api api,
  required LibItem item,
  required PlayerEngine engine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BookmarkSheet(api: api, item: item, engine: engine),
  );
}

class _BookmarkSheet extends StatefulWidget {
  const _BookmarkSheet({required this.api, required this.item, required this.engine});
  final Api api;
  final LibItem item;
  final PlayerEngine engine;
  @override
  State<_BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<_BookmarkSheet> {
  List<Bookmark>? _list; // null = 加载中
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _list = null;
      _failed = false;
    });
    try {
      final l = await widget.api.bookmarks(widget.item.id);
      l.sort((a, b) => a.time.compareTo(b.time));
      if (mounted) setState(() => _list = l);
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _list = [];
        });
      }
    }
  }

  void _jump(double abs) {
    final engine = widget.engine;
    final nav = Navigator.of(context);
    Navigator.pop(context);
    nav.push(PlayerPage.route());
    if (engine.hasBook && engine.item?.id == widget.item.id) {
      engine.seekAbsolute(abs);
    } else {
      engine.open(widget.item, startAt: abs);
    }
  }

  Future<void> _remove(Bookmark b) async {
    try {
      await context.read<AppState>().removeBookmarkAt(widget.item, b.time);
    } catch (_) {}
    if (mounted) setState(() => _list?.remove(b));
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final hint = Theme.of(context).hintColor;
    return SafeArea(
      child: SizedBox(
        height: 460,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(children: [
              const Icon(Icons.bookmark, size: 20, color: Colors.deepOrange),
              const SizedBox(width: 8),
              const Text('书签', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (list != null) Text('共 ${list.length} 个', style: TextStyle(fontSize: 12, color: hint)),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh, size: 20)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(list)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Text('点击书签可直接跳转到对应位置播放', style: TextStyle(fontSize: 11.5, color: hint)),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(List<Bookmark>? list) {
    if (list == null) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          _failed ? '加载失败，请点右上角刷新重试' : '暂无书签\n播放时点右上角书签图标添加',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, height: 1.6),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final b = list[i];
        return ListTile(
          leading: const Icon(Icons.bookmark, color: Colors.deepOrange),
          title: Text(b.title.isEmpty ? '书签 ${i + 1}' : b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('位置 ${fmtDur(b.time)}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _remove(b),
          ),
          onTap: () => _jump(b.time),
        );
      },
    );
  }
}
