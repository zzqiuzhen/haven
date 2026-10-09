/// 书库页：分类切换 + 封面网格 + 分页加载
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../cache_manager.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/global_bookmarks_sheet.dart';
import 'book_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

Widget _libChip({required bool darkChip, required String label, required bool sel, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: R.pill,
        gradient: sel ? const LinearGradient(colors: [Color(0xFF2F80ED), Color(0xFF1F66C9)]) : null,
        color: sel ? null : (darkChip ? C.dCard : Colors.white),
        border: sel ? null : Border.all(color: darkChip ? Colors.white.withValues(alpha: 0.08) : C.line),
        boxShadow: sel ? [BoxShadow(color: C.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))] : null,
      ),
      child: Text(label,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: sel ? Colors.white : (darkChip ? C.dText : const Color(0xFF333D55)))),
    ),
  );
}

class _LibraryPageState extends State<LibraryPage> {
  String? _libId;
  String _sort = 'addedAt';
  bool _desc = true;
  bool _downloadedOnly = false;
  bool _loading = false;
  final _scroll = ScrollController();
  final _attempted = <String>{};
  String? _loadError;

  static const _sortNames = {
    'addedAt': '最近添加',
    'media.metadata.title': '标题',
    'media.metadata.authorName': '作者',
    'media.duration': '时长',
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final app = context.read<AppState>();
    final id = _libId;
    if (id == null || _loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loaded = (app.libItems[id] ?? const <LibItem>[]).length;
      final page = refresh ? 0 : loaded ~/ 50;
      await app.loadLibrary(id, page: page, refresh: refresh, sort: _sort, desc: _desc);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = '$e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _maybeMore() {
    if (!_scroll.hasClients) return;
    final app = context.read<AppState>();
    final id = _libId;
    if (id == null) return;
    final loaded = (app.libItems[id] ?? const []).length;
    final total = app.libTotals[id] ?? 0;
    if (loaded >= total) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // 首页“我的书库”直达：消费待选书库并加载
    final pend = app.pendingLibId;
    if (pend != null) {
      app.pendingLibId = null;
      if (pend != _libId) {
        _libId = pend;
        _attempted.add(pend);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(refresh: true);
        });
      }
    }
    final id = _libId ?? (app.libraries.isNotEmpty ? app.libraries.first.id : null);
    final items = id == null ? const <LibItem>[] : (app.libItems[id] ?? const <LibItem>[]);

    if (id != null && _libId != id) {
      _libId = id;
    }
    if (id != null && !_loading && !_attempted.contains(id) && (app.libItems[id] ?? const []).isEmpty) {
      _attempted.add(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final cacheMgr = context.watch<CacheManager>();
    final shownItems = _downloadedOnly
        ? items.where((it) => cacheMgr.cachedInosFor(it.id).isNotEmpty).toList()
        : items;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 12, 6),
            child: Row(
              children: [
                const Text('书库', style: TS.h1),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (v) {
                    if (v == '__desc' || v == '__asc') {
                      setState(() => _desc = v == '__desc');
                    } else {
                      setState(() => _sort = v);
                    }
                    _load(refresh: true);
                  },
                  itemBuilder: (_) => [
                    for (final e in _sortNames.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(value: '__desc', checked: _desc, child: const Text('降序')),
                    CheckedPopupMenuItem(value: '__asc', checked: !_desc, child: const Text('升序')),
                  ],
                  child: Glass(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: const Row(children: [
                      Icon(Icons.swap_vert, size: 18, color: C.text2),
                      SizedBox(width: 2),
                      Text('排序', style: TextStyle(fontSize: 13, color: C.text2)),
                    ]),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => showGlobalBookmarksSheet(context: context),
                  child: Glass(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: const Icon(Icons.bookmark_outline, size: 18, color: C.text2),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: app.libraries.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final darkChip = Theme.of(context).brightness == Brightness.dark;
                if (i >= app.libraries.length) {
                  return _libChip(
                    darkChip: darkChip,
                    label: _downloadedOnly ? '✓ 已下载' : '已下载',
                    sel: _downloadedOnly,
                    onTap: () => setState(() => _downloadedOnly = !_downloadedOnly),
                  );
                }
                final l = app.libraries[i];
                final sel = l.id == id;
                return _libChip(
                  darkChip: darkChip,
                  label: sel ? '✓ ${l.name}' : l.name,
                  sel: sel,
                  onTap: () => setState(() => _libId = l.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: shownItems.isEmpty
                  ? (app.loadingHome || _loading
                      ? const LoadingView()
                      : EmptyView(_loadError != null ? '加载失败：$_loadError' : (_downloadedOnly ? '还没有已下载的书籍' : '书库是空的')))
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 220),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: shownItems.length + (_loading ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= shownItems.length) {
                          return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                        }
                        return _GridCard(item: shownItems[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.item});
  final LibItem item;

  @override
  Widget build(BuildContext context) {
    final cachedN = context.watch<CacheManager>().cachedInosFor(item.id).length;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: item))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, cons) {
            return Stack(
              children: [
                HavenCover(item.id, item.meta.title, width: cons.maxWidth, height: cons.maxWidth, radius: 12),
                if (cachedN > 0)
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('已缓存 $cachedN 集',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 6),
          Text(item.meta.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
          const SizedBox(height: 2),
          Text(item.meta.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.text2)),
        ],
      ),
    );
  }
}
