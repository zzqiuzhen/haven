/// 全屏播放器
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../cache_manager.dart';
import '../player_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/bookmark_sheet.dart';
import '../widgets/common.dart';
import '../widgets/download_sheet.dart';
import 'book_page.dart' show BookPage;

/// 播放器页是否处于打开状态（供锁屏返回时判断是否直达播放器）
bool playerPageOpen = false;

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  static Route<void> route() => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const PlayerPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        ),
      );

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {
  bool _dragging = false;
  double _dragValue = 0;
  /// 下滑最小化位移（ValueNotifier：拖拽帧只重建位移层，不重建整页 → 丝滑不卡顿）
  final ValueNotifier<double> _minimizeDragN = ValueNotifier<double>(0);
  late final AnimationController _snapBack;
  double _snapFrom = 0;

  @override
  void initState() {
    super.initState();
    playerPageOpen = true;
    _snapBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _snapBack.addListener(() {
      _minimizeDragN.value = _snapFrom * (1 - Curves.easeOut.transform(_snapBack.value));
    });
  }

  @override
  void dispose() {
    playerPageOpen = false;
    _snapBack.dispose();
    _minimizeDragN.dispose();
    super.dispose();
  }

  /// 动画平滑回弹到 0（未过阈值 / 弹出被拒 时使用）
  void _startSnapBack() {
    _snapFrom = _minimizeDragN.value;
    _snapBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<PlayerEngine>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final item = engine.item;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: engine.loading ? const LoadingView() : const EmptyView('当前没有播放中的书籍'),
      );
    }

    final track = engine.track;
    final settings = engine.settings;
    final w = MediaQuery.of(context).size.width;
    // 进度条按“当前章节”范围显示（不再显示全书 20+ 小时总时长）
    final chapStart = track?.startOffset ?? 0;
    final chapDur = (track?.duration ?? 0) > 0 ? track!.duration : engine.duration;
    final chapPos = _dragging
        ? _dragValue
        : (engine.absolute - chapStart).clamp(0.0, chapDur <= 0 ? 1.0 : chapDur).toDouble();
    final cacheMgr = context.watch<CacheManager>();
    final cacheActive = cacheMgr.tasks
        .where((t) => t.bookId == item.id && (t.state == 'queued' || t.state == 'downloading'))
        .length;
    final buffering = engine.player.processingState == ProcessingState.buffering || engine.loading;

    final cachedSet = cacheMgr.cachedInosFor(item.id);
    var maxCachedIdx = -1;
    for (int i = 0; i < engine.tracks.length; i++) {
      if (cachedSet.contains(engine.tracks[i].ino)) maxCachedIdx = i;
    }
    final cachedCount = maxCachedIdx >= 0 ? engine.tracks[maxCachedIdx].index : 0;
    final curCached = track != null && track.ino.isNotEmpty && cachedSet.contains(track.ino);
    String? cacheLabel;
    if (cacheActive > 0) {
      cacheLabel = cachedCount > 0 ? '自动缓存中 · 已缓存到第 $cachedCount 集' : '自动缓存中 · $cacheActive 章';
    } else if (cachedCount > 0) {
      cacheLabel = '已缓存到第 $cachedCount 集';
    } else if (curCached) {
      cacheLabel = '本章已缓存 · 本地秒开';
    }

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) {
          _snapBack.stop(); // 中途再按住可继续拖（打断回弹）
        },
        onVerticalDragUpdate: (d) {
          final v = _minimizeDragN.value + d.delta.dy;
          _minimizeDragN.value = v < 0 ? 0 : v; // 只更新位移层，不再 setState 整页
        },
        onVerticalDragCancel: _startSnapBack,
        onVerticalDragEnd: (d) {
          final vy = d.velocity.pixelsPerSecond.dy;
          if (_minimizeDragN.value > 110 || vy > 800) {
            // 保持位移直接弹出（不要先复位——复位会先弹回一帧再退场，看起来就是“弹一下”）
            final nav = Navigator.of(context);
            nav.maybePop().then((ok) {
              if (!ok && mounted) _startSnapBack();
            });
          } else {
            // 未过阈值：动画平滑回弹
            _startSnapBack();
          }
        },
        child: ValueListenableBuilder<double>(
          valueListenable: _minimizeDragN,
          child: RepaintBoundary(
            // 重绘隔离：拖拽时只移动图层，整页（含大模糊背景）不重绘
            child: Stack(
              children: [
          Positioned.fill(child: ColoredBox(color: dark ? C.dBg : C.bg)),
          Positioned(
            top: -80,
            left: -60,
            right: -60,
            height: 460,
            child: IgnorePointer(
              child: Opacity(
                opacity: dark ? 0.30 : 0.38,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 64, sigmaY: 64),
                  child: HavenCover(item.id, item.meta.title, width: w + 120, height: 460, radius: 0),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 顶部栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _RoundIcon(icon: Icons.keyboard_arrow_down, onTap: () => Navigator.pop(context)),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(track?.title ?? item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: C.text2)),
                          ],
                        ),
                      ),
                      _RoundIcon(icon: Icons.bookmark_add_outlined, onTap: () => _addBookmark(context, engine)),
                      const SizedBox(width: 8),
                      _RoundIcon(icon: Icons.more_horiz, onTap: () => _moreSheet(context, engine)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 44),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 30, offset: const Offset(0, 12))],
                              ),
                              child: HavenCover(item.id, item.meta.title, size: w.clamp(0, 430) * 0.58, radius: 20),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(item.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(
                            '${item.meta.authorText}${engine.tracks.isEmpty ? '' : ' · ${engine.index + 1}/${engine.tracks.length}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: C.text2),
                          ),
                          if (cacheLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: GestureDetector(
                                onTap: () => showDownloadSheet(
                                  context: context,
                                  item: item,
                                  detail: engine.detail,
                                  currentIndex: engine.index,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: C.teal.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(cacheActive > 0 ? Icons.downloading : Icons.check_circle, size: 13, color: C.teal),
                                      const SizedBox(width: 4),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 250),
                                        child: Text(cacheLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11, color: C.teal)),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.expand_more, size: 14, color: C.teal),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (engine.error != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: R.card),
                    child: Row(
                      children: [
                        Expanded(child: Text(engine.error!, style: const TextStyle(color: C.red, fontSize: 12.5))),
                        TextButton(onPressed: () => engine.playAt(engine.index), child: const Text('重试')),
                      ],
                    ),
                  ),
                // 底部液态玻璃面板：进度 + 控制键 + 功能区
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Glass(
                    radius: 26,
                    highlight: false,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (buffering)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8)),
                                const SizedBox(width: 8),
                                Text('缓冲中…', style: TS.mini.copyWith(fontSize: 11.5)),
                              ],
                            ),
                          ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          ),
                          child: Slider(
                            value: chapPos.isNaN ? 0 : chapPos,
                            max: chapDur <= 0 ? 1 : chapDur,
                            onChangeStart: (v) => setState(() {
                              _dragging = true;
                              _dragValue = v;
                            }),
                            onChanged: (v) => setState(() => _dragValue = v),
                            onChangeEnd: (v) {
                              setState(() => _dragging = false);
                              engine.seekAbsolute(chapStart + v);
                            },
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(fmtDur(chapPos), style: TS.mini.copyWith(fontSize: 12)),
                            const Spacer(),
                            Text(fmtDur(chapDur), style: TS.mini.copyWith(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SeekBtn(icon: Icons.replay, label: '${settings.rewindStep}s', onTap: () => engine.seekRelative(-settings.rewindStep.toDouble())),
                            SizedBox(height: 44, child: Center(child: _RoundIcon(icon: Icons.skip_previous_rounded, size: 40, iconSize: 30, onTap: () => engine.prevTrack()))),
                            SizedBox(
                              height: 44,
                              child: Center(
                                child: GestureDetector(
                                  onTap: engine.toggle,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: C.navy,
                                      boxShadow: [BoxShadow(color: C.navy.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                                    ),
                                    child: Icon(engine.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 42, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 44, child: Center(child: _RoundIcon(icon: Icons.skip_next_rounded, size: 40, iconSize: 30, onTap: () => engine.nextTrack(userInitiated: true)))),
                            _SeekBtn(icon: Icons.forward, label: '${settings.forwardStep}s', onTap: () => engine.seekRelative(settings.forwardStep.toDouble())),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _BottomAction(icon: Icons.speed, label: '${_fmtSpeed(engine.player.speed)}x', onTap: () => _speedSheet(context, engine))),
                            Expanded(child: _BottomAction(icon: Icons.vertical_align_top, label: settings.skipIntro > 0 ? '片头 ${settings.skipIntro}s' : '片头', onTap: () => _skipSheet(context, engine))),
                            Expanded(child: _BottomAction(icon: Icons.vertical_align_bottom, label: settings.skipOutro > 0 ? '片尾 ${settings.skipOutro}s' : '片尾', onTap: () => _skipSheet(context, engine))),
                            Expanded(child: _BottomAction(
                              icon: Icons.bedtime_outlined,
                              label: engine.sleepMode == SleepMode.timed && engine.sleepRemaining != null
                                  ? _fmtRemain(engine.sleepRemaining!)
                                  : (engine.sleepMode == SleepMode.endOfChapter ? '本章后' : '定时'),
                              active: engine.sleepMode != SleepMode.off,
                              onTap: () => _sleepSheet(context, engine),
                            )),
                            Expanded(child: _BottomAction(icon: Icons.format_list_bulleted, label: '目录', onTap: () => _chaptersSheet(context, engine))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      ),
      ),
    );
  }

  String _fmtSpeed(double s) {
    final v = s.toStringAsFixed(1);
    return v.endsWith('.0') ? v.substring(0, v.length - 2) : v;
  }

  String _fmtRemain(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _addBookmark(BuildContext context, PlayerEngine engine) async {
    final item = engine.item;
    if (item == null) return;
    try {
      await context.read<AppState>().addBookmarkAt(item, engine.absolute, engine.track?.title ?? '');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('书签已添加 · ${fmtDur(engine.absolute)}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败：$e')));
      }
    }
  }

  void _moreSheet(BuildContext context, PlayerEngine engine) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.bookmark_outline, color: Colors.deepOrange),
            title: const Text('书签（查看 / 跳转）'),
            onTap: () {
              Navigator.pop(ctx);
              final it = engine.item;
              if (it != null) {
                showBookmarkSheet(context: context, api: engine.api, item: it, engine: engine);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh, color: C.primary),
            title: const Text('重新加载当前章节'),
            onTap: () {
              Navigator.pop(ctx);
              engine.playAt(engine.index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: C.teal),
            title: const Text('查看书籍详情'),
            onTap: () {
              Navigator.pop(ctx);
              if (engine.item != null) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: engine.item!)));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined, color: C.red),
            title: const Text('停止播放（同步进度并关闭会话）'),
            onTap: () {
              Navigator.pop(ctx);
              engine.stopAndClose();
              Navigator.of(context).pop();
            },
          ),
        ]),
      ),
    );
  }

  void _speedSheet(BuildContext context, PlayerEngine engine) {
    var v = engine.player.speed;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Text('倍速 · ${_fmtSpeed(v)}x', style: TS.title)),
                const SizedBox(height: 8),
                Slider(
                  value: v.clamp(0.5, 3.0),
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  label: '${_fmtSpeed(v)}x',
                  onChanged: (x) {
                    setSheet(() => v = x);
                    engine.setSpeed(x);
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in [0.8, 1.0, 1.25, 1.5, 2.0])
                      ChoiceChip(
                        label: Text('${_fmtSpeed(s)}x'),
                        selected: (v - s).abs() < 0.01,
                        onSelected: (_) {
                          setSheet(() => v = s);
                          engine.setSpeed(s);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('此倍速会记住在本书记忆点，不影响其他书', style: TS.mini),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _skipSheet(BuildContext context, PlayerEngine engine) {
    final s = engine.settings;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Text('跳过片头 / 片尾', style: TS.title)),
                const SizedBox(height: 12),
                const Text('跳过片头（每章开头）', style: TextStyle(fontSize: 13, color: C.text2)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in [0, 5, 10, 15, 20, 30, 60])
                      ChoiceChip(
                        label: Text(v == 0 ? '关闭' : '${v}s'),
                        selected: s.skipIntro == v,
                        onSelected: (_) {
                          s.skipIntro = v;
                          setSheet(() {});
                          engine.touch();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('跳过片尾（每章结尾）', style: TextStyle(fontSize: 13, color: C.text2)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in [0, 5, 10, 15, 20, 30, 60])
                      ChoiceChip(
                        label: Text(v == 0 ? '关闭' : '${v}s'),
                        selected: s.skipOutro == v,
                        onSelected: (_) {
                          s.skipOutro = v;
                          setSheet(() {});
                          engine.touch();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sleepSheet(BuildContext context, PlayerEngine engine) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(12), child: Text('定时关闭', style: TS.title)),
          ListTile(
            leading: const Icon(Icons.bedtime_off_outlined),
            title: const Text('关闭定时'),
            selected: engine.sleepMode == SleepMode.off,
            onTap: () {
              engine.setSleep(SleepMode.off);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('播完本章'),
            selected: engine.sleepMode == SleepMode.endOfChapter,
            onTap: () {
              engine.setSleep(SleepMode.endOfChapter);
              Navigator.pop(ctx);
            },
          ),
          for (final m in [15, 30, 45, 60, 90])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$m 分钟后'),
              onTap: () {
                engine.setSleep(SleepMode.timed, duration: Duration(minutes: m));
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }

  void _chaptersSheet(BuildContext context, PlayerEngine engine) {
    final tracks = engine.tracks;
    final item = engine.item;
    if (tracks.isEmpty || item == null) return;
    // 精准锚定当前播放集：行高用 itemExtent=50 强制一致，并把当前集滚到视口中央
    const kRowExtent = 50.0;
    final viewportH = MediaQuery.of(context).size.height * 0.72;
    final maxOffset = (tracks.length * kRowExtent - viewportH).clamp(0.0, double.infinity);
    final controller = ScrollController(
      initialScrollOffset: (engine.index * kRowExtent - viewportH / 2 + kRowExtent / 2).clamp(0.0, maxOffset),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('目录 · 共 ${tracks.length} 章', style: TS.title),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemExtent: kRowExtent,
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  final cur = i == engine.index;
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cur ? C.primary.withValues(alpha: 0.15) : null,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('${t.index}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cur ? C.primary : null)),
                    ),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: cur ? FontWeight.w700 : FontWeight.w400, color: cur ? C.primary : null)),
                    trailing: Text(fmtDur(t.duration), style: TS.mini),
                    onTap: () {
                      Navigator.pop(ctx);
                      engine.playAt(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.size = 38, this.iconSize = 22});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (dark ? C.dCard : Colors.white).withValues(alpha: 0.75),
        ),
        child: Icon(icon, size: iconSize),
      ),
    );
  }
}

class _SeekBtn extends StatelessWidget {
  const _SeekBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 44px 图标区：与上一集/下一集/播放按钮同一垂直中心
          SizedBox(
            height: 44,
            child: Center(child: Icon(icon, size: 30)),
          ),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 10, color: C.text2)),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final c = active ? C.primary : C.text2;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: c),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10.5, color: c, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
