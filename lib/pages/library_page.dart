/// 书库页：分类切换 + 封面网格 + 分页加载
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/global_bookmarks_sheet.dart';
import 'book_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _libId;
  String _sort = 'addedAt';
  bool _desc = true;
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
                IconButton(
                  tooltip: '书签',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.bookmarks_outlined, size: 20, color: C.text2),
                  onPressed: () => showGlobalBookmarksSheet(context: context),
                ),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (v) {
                    setState(() => _sort = v);
                    _load(refresh: true);
                  },
                  itemBuilder: (_) => [
                    for (final e in _sortNames.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
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
                IconButton(
                  icon: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward, size: 18, color: C.text2),
                  onPressed: () {
                    setState(() => _desc = !_desc);
                    _load(refresh: true);
                  },
                ),
              ],
            ),
          ),
          if (app.libraries.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: app.libraries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final l = app.libraries[i];
                  final sel = l.id == id;
                  final darkChip = Theme.of(context).brightness == Brightness.dark;
                  return GestureDetector(
                    onTap: () => setState(() => _libId = l.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: R.pill,
                        gradient: sel ? const LinearGradient(colors: [Color(0xFF2F80ED), Color(0xFF1F66C9)]) : null,
                        color: sel ? null : (darkChip ? C.dCard.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.55)),
                        border: sel ? null : Border.all(color: darkChip ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.7)),
                        boxShadow: sel ? [BoxShadow(color: C.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))] : null,
                      ),
                      child: Text(l.name,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: sel ? Colors.white : (darkChip ? C.dText : const Color(0xFF333D55)))),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: items.isEmpty
                  ? (app.loadingHome || _loading
                      ? const LoadingView()
                      : EmptyView(_loadError != null ? '加载失败：$_loadError' : '书库是空的'))
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 220),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.68,
                      ),
                      itemCount: items.length + (_loading ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= items.length) {
                          return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                        }
                        return _GridCard(item: items[i], app: app);
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
  const _GridCard({required this.item, required this.app});
  final LibItem item;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final pg = app.progressOf(item.id);
    final frac = pg == null ? 0.0 : (pg.progress > 0 ? pg.progress : (pg.duration > 0 ? pg.currentTime / pg.duration : 0)).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: item))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, cons) {
            return Stack(
              children: [
                HavenCover(item.id, item.meta.title, width: cons.maxWidth, height: cons.maxWidth, radius: 12),
                if (frac > 0.005)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                        child: Text('${(frac * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
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
