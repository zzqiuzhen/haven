/// 书籍详情页
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cache_manager.dart';
import '../consts.dart';
import '../models.dart';
import '../player_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/bookmark_sheet.dart';
import '../widgets/common.dart';
import '../widgets/download_sheet.dart';
import 'downloads_page.dart';
import 'player_page.dart';

class BookPage extends StatefulWidget {
  const BookPage({super.key, required this.item});
  final LibItem item;
  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  BookDetail? _d;
  bool _loading = true;
  String? _err;
  bool _descOpen = false;
  int _group = 0;
  bool _didPrewarm = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final d = await app.detail(widget.item.id);
      if (!mounted) return;
      final pg = app.progressOf(widget.item.id);
      final abs = pg?.currentTime ?? 0;
      var ti = 0;
      for (int i = 0; i < d.tracks.length; i++) {
        if (abs < d.tracks[i].end) {
          ti = i;
          break;
        }
      }
      setState(() {
        _d = d;
        _loading = false;
        _group = (ti ~/ 100) * 100;
      });
      if (!_didPrewarm) {
        _didPrewarm = true;
        app.prewarm(widget.item, d, abs);
        // 转码书（WMA 等）：进入详情页即预热转码会话，起播免等冷启动
        if (d.tracks.any((t) => codecNeedsTranscode(t.codec, t.mimeType))) {
          unawaited(context.read<PlayerEngine>().prewarmTranscode(widget.item));
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = '$e';
        setState(() {
          _err = (msg.contains('404') || msg.contains('not found'))
              ? '该书已不在服务器上（可能已被删除），请返回刷新'
              : msg;
          _loading = false;
        });
      }
    }
  }

  void _play({double? startAt}) {
    final app = context.read<AppState>();
    final engine = context.read<PlayerEngine>();
    Navigator.of(context).push(PlayerPage.route());
    if (engine.hasBook && engine.item?.id == widget.item.id && engine.session == null && startAt == null) {
      // 恢复态同一本书：直接续播
      unawaited(engine.toggle());
    } else {
      unawaited(engine.open(widget.item, startAt: startAt ?? app.resumeAbsFor(widget.item.id)));
    }
  }

  void _onChapterTap(int i, Track t) {
    final engine = context.read<PlayerEngine>();
    Navigator.of(context).push(PlayerPage.route());
    if (engine.hasBook && engine.item?.id == widget.item.id) {
      unawaited(engine.playAt(i));
    } else {
      unawaited(engine.open(widget.item, startAt: t.startOffset));
    }
  }

  void _enqueueCache(List<int> idx) {
    final d = _d;
    if (d == null) return;
    enqueueCacheRange(context, widget.item, d, idx);
  }

  void _downloadSheet() {
    final d = _d;
    if (d == null || d.tracks.isEmpty) return;
    final app = context.read<AppState>();
    final pg = app.progressOf(widget.item.id);
    var ti = 0;
    for (int i = 0; i < d.tracks.length; i++) {
      if ((pg?.currentTime ?? 0) < d.tracks[i].end) {
        ti = i;
        break;
      }
    }
    showDownloadSheet(context: context, item: widget.item, detail: d, currentIndex: ti);
  }

  Future<void> _addBookmark() async {
    final engine = context.read<PlayerEngine>();
    final app = context.read<AppState>();
    if (!(engine.hasBook && engine.item?.id == widget.item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('播放本书后才能在当前位置添加书签')));
      return;
    }
    try {
      await app.addBookmarkAt(widget.item, engine.absolute, engine.track?.title ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('书签已添加 · ${fmtDur(engine.absolute)}'),
          action: SnackBarAction(label: '查看', onPressed: _showBookmarks),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败：$e')));
    }
  }

  void _showBookmarks() {
    final app = context.read<AppState>();
    final engine = context.read<PlayerEngine>();
    showBookmarkSheet(context: context, api: app.api, item: widget.item, engine: engine);
  }

  /// 固定的「章节」栏：章节标题 + 分组快速切换（上滑时钉在顶部，仅下方列表滚动）
  static const double _chapterRowH = 50; // 标题行固定高（防与首行重合）
  static const double _chapterChipsH = 38; // 分组标签行固定高

  Widget _chapterHeader(BuildContext context, bool dark, BookDetail? d) {
    final topPad = MediaQuery.of(context).padding.top;
    final hasChips = d != null && d.tracks.length > 100;
    return ColoredBox(
      color: dark ? C.dBg : C.bg,
      child: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _chapterRowH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    const Text('章节', style: TS.h2),
                    const SizedBox(width: 8),
                    Text(d == null ? '加载中…' : '共 ${d.tracks.length} 章', style: TS.mini),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showBookmarks(),
                      child: const Text('书签', style: TextStyle(fontSize: 13, color: C.primary)),
                    ),
                  ],
                ),
              ),
            ),
            if (hasChips)
              SizedBox(
                height: _chapterChipsH,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: (d.tracks.length / 100).ceil(),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, gi) {
                    final start = gi * 100;
                    final end = math.min(start + 100, d.tracks.length);
                    final sel = _group == start;
                    return Center(
                      child: ChoiceChip(
                        label: Text('第${start + 1}-$end章', style: const TextStyle(fontSize: 12.5)),
                        selected: sel,
                        onSelected: (_) => setState(() => _group = start),
                      ),
                    );
                  },
                ),
              ),
            Container(height: 1, color: dark ? C.dLine : C.line),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cache = context.watch<CacheManager>();
    final engine = context.watch<PlayerEngine>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;
    final pg = app.progressOf(item.id);
    final d = _d;
    final w = MediaQuery.of(context).size.width;
    final isPlayingThis = engine.hasBook && engine.item?.id == item.id;

    final resumeLabel = (pg != null && pg.currentTime > 5) ? '继续听 · ${fmtDur(pg.currentTime)}' : '开始播放';

    String metaLine = [item.meta.authorText, if (item.meta.narrators.isNotEmpty) '演播 ${item.meta.narratorText}', fmtTotal(item.duration)].join(' · ');

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 380,
            child: IgnorePointer(
              child: Opacity(
                opacity: dark ? 0.22 : 0.32,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: HavenCover(item.id, item.meta.title, width: w, height: 380, radius: 0),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: 0,
            right: 0,
            height: 200,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [C.bg.withValues(alpha: 0), dark ? C.dBg : C.bg],
                  ),
                ),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: Row(
                          children: [
                            _CircleBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                            const Spacer(),
                            _CircleBtn(icon: Icons.more_horiz, onTap: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (_) => SafeArea(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    ListTile(
                                      leading: const Icon(Icons.refresh, color: C.primary),
                                      title: const Text('刷新书籍信息'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        app.detailCache.remove(item.id);
                                        setState(() => _loading = true);
                                        _load();
                                      },
                                    ),
                                  ]),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
                          ),
                          child: HavenCover(item.id, item.meta.title, size: 186, radius: 18),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            Text(item.meta.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25)),
                            if (item.meta.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(item.meta.subtitle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.text2)),
                            ],
                            const SizedBox(height: 6),
                            Text(metaLine, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: C.text2)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: C.navy,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  onPressed: () => _play(),
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                                  label: Text(resumeLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _SquareBtn(icon: Icons.download_outlined, onTap: _downloadSheet),
                            const SizedBox(width: 10),
                            _SquareBtn(icon: Icons.bookmark_add_outlined, onTap: _addBookmark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (item.meta.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GestureDetector(
                            onTap: () => setState(() => _descOpen = !_descOpen),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: dark ? C.dCard : Colors.white,
                                borderRadius: R.card,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('简介', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(
                                    cleanHtml(item.meta.description),
                                    maxLines: _descOpen ? null : 4,
                                    overflow: _descOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, height: 1.55, color: dark ? C.dText2 : const Color(0xFF5A6068)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_descOpen ? '收起' : '展开', style: const TextStyle(fontSize: 12.5, color: C.primary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_err != null)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('加载失败：$_err', style: const TextStyle(color: C.red, fontSize: 13)),
                        ),
                      if (_loading) const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ChapterHeaderDelegate(
                  height: MediaQuery.of(context).padding.top + 51 + ((d != null && d.tracks.length > 100) ? 38 : 0),
                  child: _chapterHeader(context, dark, d),
                ),
              ),
              if (d != null)
                SliverList.builder(
                  itemCount: () {
                    final start = d.tracks.length > 100 ? _group : 0;
                    final end = d.tracks.length > 100 ? math.min(_group + 100, d.tracks.length) : d.tracks.length;
                    return end - start;
                  }(),
                  itemBuilder: (context, i) {
                    final start = d.tracks.length > 100 ? _group : 0;
                    final ti = start + i;
                    final t = d.tracks[ti];
                    final current = isPlayingThis && engine.index == ti;
                    final done = cache.hasMark(item.id, t.ino);
                    final task = cache.taskFor(item.id, t.ino);
                    return _ChapterTile(
                      track: t,
                      current: current,
                      downloaded: done,
                      downloading: task != null && (task.state == 'downloading' || task.state == 'queued'),
                      onTap: () => _onChapterTap(ti, t),
                      onLongPress: () => showModalBottomSheet(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(
                              leading: const Icon(Icons.download, color: C.primary),
                              title: const Text('缓存本集'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _enqueueCache([ti]);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.playlist_add, color: C.purple),
                              title: const Text('从本集缓存以下 10 集'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _enqueueCache([for (int k = ti; k < ti + 10; k++) k]);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.edit_calendar_outlined, color: C.navy),
                              title: const Text('自定义范围缓存…'),
                              onTap: () {
                                Navigator.pop(ctx);
                                showCustomRangeDialog(context, widget.item, d, defaultStart: t.index);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: C.red),
                              title: const Text('清除本书缓存'),
                              onTap: () {
                                Navigator.pop(ctx);
                                cache.deleteBook(item.id);
                              },
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 44)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ChapterHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(height: height, child: child);
  @override
  bool shouldRebuild(covariant _ChapterHeaderDelegate old) => true;
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (dark ? C.dCard : Colors.white),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  const _SquareBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: dark ? C.dCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: 22, color: C.navy),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.track,
    required this.current,
    required this.downloaded,
    required this.downloading,
    required this.onTap,
    required this.onLongPress,
  });
  final Track track;
  final bool current;
  final bool downloaded;
  final bool downloading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: current
              ? C.primary.withValues(alpha: dark ? 0.16 : 0.07)
              : (dark ? C.dCard : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: current ? Border.all(color: C.primary, width: 1.3) : Border.all(color: Colors.transparent, width: 1.3),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? C.dCardSoft : C.cardSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: current
                  ? Icon(downloading ? Icons.downloading : Icons.graphic_eq, size: 18, color: C.primary)
                  : Text('${track.index}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    [if (track.ext.isNotEmpty) track.ext, if (track.codec.isNotEmpty) track.codec].join(' · '),
                    style: const TextStyle(fontSize: 11, color: C.text2),
                  ),
                ],
              ),
            ),
            if (downloaded) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check_circle, size: 16, color: C.teal)),
            if (downloading) const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
            Text(fmtDur(track.duration), style: const TextStyle(fontSize: 12, color: C.text2)),
          ],
        ),
      ),
    );
  }
}
