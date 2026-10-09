/// 播放引擎：会话管理 / 快速起播 / 缓存预取 / 进度同步 / 睡眠定时
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'audio_handler.dart';
import 'cache_manager.dart';
import 'consts.dart';
import 'models.dart';
import 'settings.dart';
import 'state.dart';

enum SleepMode { off, endOfChapter, timed }

class PlayerEngine extends ChangeNotifier {
  PlayerEngine({required this.api, required this.cache, required this.settings}) {
    _init();
  }

  Api api;
  final CacheManager cache;
  final Settings settings;
  final AudioPlayer player = AudioPlayer();
  HavenAudioHandler? handler;
  AppState? owner;

  LibItem? item;
  BookDetail? detail;
  PlaySession? session;
  int index = 0;
  bool loading = false;
  String? error;

  double _absolute = 0;
  double _unsynced = 0;
  double _lastSyncedAbs = -1;
  bool _closing = false;
  bool _queueReported = false;
  bool _lastSourceDirect = false;
  bool _usedFallback = false;
  bool? _directOk; // 直连可用性：null=未验证 / true=可用 / false=不可用（本次运行内有效）
  Future<bool>? _directProbing; // 直连探测单飞（多个调用共享同一探测）
  final Set<String> _directBadInos = {}; // 直连打不开的具体章节（CDN attachment 等），跳过直连走服务端
  int _directFailCount = 0;
  bool _aacMode = false; // 转码书（WMA 等）：AAC 缓存模式（服务器单集转码缓存，手机可缓存秒播）
  int _loadSeq = 0; // 加载序号：后发加载取代先发，先发的失败/中断静默忽略
  bool _loading = false; // 是否有加载请求在途（错误流事件在此期间交给 catch 统一处理）
  bool _recovering = false; // 回退重试单飞锁，杜绝多重回退互相打断
  final Set<String> _badLocalInos = {}; // 本地文件加载失败的章节（本运行内不再读本地）
  String? _lastLoadUrl; // 最近一次加载的音源 URL（用于失败自愈判定）
  Uri? _artUri;
  DateTime _lastNotify = DateTime.now();
  DateTime _lastMeRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  SleepMode sleepMode = SleepMode.off;
  DateTime? _sleepUntil;
  Duration? get sleepRemaining {
    if (sleepMode != SleepMode.timed || _sleepUntil == null) return null;
    final d = _sleepUntil!.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Timer? _syncTimer;
  Timer? _listenTimer;

  List<Track> get tracks => (detail != null && detail!.tracks.isNotEmpty) ? detail!.tracks : (session?.tracks ?? const []);
  Track? get track => (index >= 0 && index < tracks.length) ? tracks[index] : null;
  bool get playing => player.playing;
  bool get isTranscode => session?.isTranscode ?? false;
  /// HLS 转码模式（传统）：仅当会话为转码且未启用 AAC 缓存模式
  bool get hlsMode => isTranscode && !_aacMode;
  double get duration => (detail?.duration ?? 0) > 0 ? detail!.duration : (session?.duration ?? 0);
  double get absolute => _absolute;
  double get trackPosition => player.position.inMilliseconds / 1000.0;

  /// 全书已缓冲到的位置（秒）
  double get bufferedAbsolute {
    if (session == null) return 0;
    final b = player.bufferedPosition.inMilliseconds / 1000.0;
    if (hlsMode) return b;
    final t = track;
    return (t?.startOffset ?? 0) + b;
  }

  double get bufferedFraction => duration > 0 ? (bufferedAbsolute / duration).clamp(0.0, 1.0).toDouble() : 0.0;
  bool get hasBook => item != null;
  String get bookId => item?.id ?? '';

  /// 供 UI 触发刷新（替代外部直接调用 notifyListeners）
  void touch() => notifyListeners();

  /// 冷启动恢复：把上次播放的书加载进引擎（不自动播放），让迷你播放器/继续收听立即可用
  Future<void> restoreLast() async {
    if (hasBook) return; // 已有书在播/已加载，不覆盖
    final o = owner;
    if (o == null) return;
    // 1) 优先本机最后播放记录（最新最准）
    final lp = settings.lastPos;
    if (lp != null && lp.$1.isNotEmpty) {
      try {
        final d = await _loadDetail(lp.$1);
        final it = await o.ensureItem(lp.$1);
        item = it;
        detail = d;
        index = _trackIndexForAbsolute(lp.$2);
        _absolute = lp.$2;
        loading = false;
        error = null;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('restoreLast 本机记录失效（可能已删除），自愈清除: $e');
        await settings.clearLastPos();
      }
    }
    // 2) 服务端最近进度
    final m = o.me;
    if (m == null) return;
    final ps = m.mediaProgress
        .where((pr) => !pr.hideFromContinue && !pr.isFinished && pr.currentTime > 1)
        .toList();
    if (ps.isEmpty) return;
    ps.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
    final id2 = ps.first.libraryItemId;
    final abs2 = ps.first.currentTime;
    if (id2 == null || id2.isEmpty) return;
    try {
      final d = await _loadDetail(id2);
      final it = await o.ensureItem(id2);
      item = it;
      detail = d;
      index = _trackIndexForAbsolute(abs2);
      _absolute = abs2;
      loading = false;
      error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('restoreLast 服务端进度恢复失败: $e');
    }
  }

  void _init() {
    player.positionStream.listen((pos) {
      _updateAbsolute(pos.inMilliseconds / 1000.0);
      final now = DateTime.now();
      if (now.difference(_lastNotify).inMilliseconds > 300) {
        _lastNotify = now;
        notifyListeners();
      }
    });
    player.playingStream.listen((_) {
      _ensureListenTimer();
      notifyListeners();
    });
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        unawaited(_onCompleted());
      }
      notifyListeners();
    });
    player.errorStream.listen(_onPlayerError);
  }

  // ---------------- 打开 / 关闭 ----------------

  /// 打开一本书并起播。[startAt] 为全书绝对秒数（续播点）
  Future<void> open(LibItem it, {double startAt = 0, bool autoplay = true}) async {
    if (session != null && item?.id == it.id) {
      if (autoplay) unawaited(player.play());
      return;
    }
    // 切书瞬时化：旧会话的关闭同步放到后台（进度已本地持久化），不阻塞新书加载；
    // 播放器无需 stop——下一次 setAudioSource 会自然接替旧音源
    _closeSessionInBackground();
    _syncTimer?.cancel();
    _syncTimer = null;
    _listenTimer?.cancel();
    _listenTimer = null;
    item = it;
    detail = null;
    session = null;
    index = 0;
    _absolute = 0;
    _queueReported = false;
    error = null;
    loading = true;
    notifyListeners();
    try {
      detail = await _loadDetail(it.id);
      var start = startAt;
      if (detail != null && detail!.duration > 0 && start >= detail!.duration - 20) start = 0;
      final sp = settings.speedFor(it.id);
      await player.setSpeed(sp);
      final needTranscode = detail!.tracks.any((t) => codecNeedsTranscode(t.codec, t.mimeType));
      if (needTranscode) {
        // WMA 等转码书：AAC 缓存模式（服务器按需边转边播单集，手机缓存后本地秒播）
        _aacMode = true;
        await _startAt(start, autoplay: autoplay);
        unawaited(_ensureSession());
        _startSyncLoop();
      } else {
        _aacMode = false;
        // 直连/代理书：立即起播（缓存命中秒开，无需等会话），会话后台创建
        if (settings.directMode) {
          // 提前做一次直连就绪探测（后台跑，等用户点章节时已有结论）
          final hp = detail!.tracks.where((t) => t.path.startsWith('http'));
          if (hp.isNotEmpty) unawaited(_ensureDirectProbed(hp.first.path));
        }
        await _startAt(start, autoplay: autoplay);
        unawaited(_ensureSession());
      }
      unawaited(_ensureArt());
    } catch (e) {
      final msg = '$e';
      if (msg.contains('404') || msg.contains('not found') || msg.contains('资源不存在')) {
        unawaited(settings.clearLastPos());
        error = '这本书已不在服务器上（可能已被删除），请返回书库刷新后重新选择';
      } else if (!msg.contains('nterrupte')) {
        error = msg;
      }
      debugPrint('open book failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  /// 后台关闭旧会话（切书不等待网络；进度已本地持久化，失败无碍）
  void _closeSessionInBackground() {
    final s = session;
    final abs = _absolute;
    final listened = _unsynced;
    final dur = duration;
    _persistPos(force: true);
    if (s != null) {
      if (abs > 0.5) {
        unawaited(api.closeSession(s.id, sync: {
          'currentTime': abs,
          'timeListened': listened,
          'duration': dur,
        }).catchError((_) {}));
      } else {
        unawaited(api.closeSession(s.id).catchError((_) {}));
      }
    }
    unawaited(_refreshMe());
  }

  /// 后台补建播放会话（用于进度同步与后续章节 contentUrl）；失败不阻塞播放
  Future<void> _ensureSession() async {
    final it = item;
    if (it == null || session != null) return;
    try {
      final s = await api.startPlay(it.id, forceTranscode: false);
      if (item?.id != it.id) return;
      session = s;
      if (!s.isTranscode && detail != null) {
        for (final st in s.tracks) {
          final di = detail!.tracks.indexWhere((d) => (d.ino.isNotEmpty && d.ino == st.ino) || d.index == st.index);
          if (di >= 0) {
            detail!.tracks[di].contentUrl = st.contentUrl;
          }
        }
      }
      _startSyncLoop();
      unawaited(syncNow());
    } catch (e) {
      debugPrint('ensureSession failed: $e');
      final msg = '$e';
      if (msg.contains('404') || msg.contains('not found') || msg.contains('资源不存在')) {
        // 条目已从服务器删除：自愈（清本地记录 + 提示 + 退出该书）
        final it2 = item;
        if (it2 != null) {
          final title = it2.meta.title;
          unawaited(settings.clearLastPos());
          unawaited(stopAndClose(closeSession: false));
          error = '《$title》已不在服务器上（可能已被删除），请返回书库重新选择';
          notifyListeners();
        }
      }
    }
  }

  Future<BookDetail> _loadDetail(String id) async {
    if (detail != null && detail!.id == id) return detail!;
    final o = owner;
    if (o != null) return o.detail(id); // 走 state 的磁盘缓存（冷启动秒开）
    final cached = o?.detailCache[id];
    if (cached != null) return cached;
    final d = await api.itemDetail(id);
    o?.detailCache[id] = d;
    return d;
  }

  Future<void> _startAt(double abs, {bool autoplay = true}) async {
    if (tracks.isEmpty) return;
    error = null;
    _usedFallback = false;
    if (hlsMode) {
      if (session == null) {
        error = '转码会话创建失败，请检查网络后重试';
        notifyListeners();
        return;
      }
      // HLS 冷启动预热：轮询等待“播放列表中的首个真实分片”可用（不请求 output-0.ts，
      // 避免服务端因回退请求 Reset Transcode 把转码起点重置到 0）
      await _warmHlsStream();
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(_hlsUrl()), headers: api.authHeaders),
      );
      await player.seek(Duration(milliseconds: (abs * 1000).round()));
      index = _trackIndexForAbsolute(abs);
      _absolute = abs;
      if (autoplay) unawaited(player.play());
      // 触发服务端窗口本地化（HLS 转码书）
      unawaited(warmTrack(index));
    } else {
      final ti = _trackIndexForAbsolute(abs);
      final inTrack = max(0.0, abs - tracks[ti].startOffset);
      await _playTrackIndex(ti, inTrack: inTrack, autoplay: autoplay);
    }
    _reportMediaItem(forceQueue: true);
    _ensureListenTimer();
    notifyListeners();
  }

  String _hlsUrl() {
    final cu = session?.tracks.isNotEmpty == true ? session!.tracks.first.contentUrl : null;
    if (cu != null) return api.fullTrackUrl(cu);
    return api.fullTrackUrl('/hls/${session?.id}/output.m3u8');
  }

  /// 轮询等待 HLS 转码就绪（先取播放列表，拿首个真实分片名再探测）
  Future<bool> _warmHlsStream() async {
    final s = session;
    if (s == null) return false;
    return _pollHlsReady(s.id, playlistUrl: _hlsUrl(), maxTries: 32);
  }

  Future<bool> _pollHlsReady(String sessionId, {String? playlistUrl, int maxTries = 24}) async {
    final pl = playlistUrl ?? api.fullTrackUrl('/hls/$sessionId/output.m3u8');
    for (int i = 0; i < maxTries; i++) {
      if (session?.id != sessionId && _preSession?.id != sessionId) return false;
      try {
        final r = await api.dio.get<String>(
          pl,
          options: Options(
            headers: api.authHeaders,
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          final seg = _firstSegmentName(r.data ?? '');
          if (seg != null) {
            final sr = await api.dio.get<List<int>>(
              api.fullTrackUrl('/hls/$sessionId/$seg'),
              options: Options(
                headers: {...api.authHeaders, 'Range': 'bytes=0-1'},
                responseType: ResponseType.bytes,
                receiveTimeout: const Duration(seconds: 15),
              ),
            );
            final c = sr.statusCode ?? 0;
            if (c >= 200 && c < 300) return true;
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1800));
    }
    return false;
  }

  String? _firstSegmentName(String m3u8) {
    for (final raw in m3u8.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.contains('.ts')) {
        final s = line.split('/').last.split('?').first;
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  // ---------------- 转码书预热 ----------------

  PlaySession? _preSession;

  /// 进入书籍详情页时调用：转码书（AAC 模式）提前把“当前集+下一集”排队下载到手机
  /// （下载请求会驱动服务器提前边转边播并落缓存），用户点播放时已就绪或正在流水
  Future<void> prewarmTranscode(LibItem it) async {
    if (kIsWeb || _closing) return;
    try {
      final d = detail != null && detail!.id == it.id ? detail! : await _loadDetail(it.id);
      if (!d.tracks.any((t) => codecNeedsTranscode(t.codec, t.mimeType))) return;
      final abs = owner?.progressOf(it.id)?.currentTime ?? 0;
      int ti = 0;
      for (int i = d.tracks.length - 1; i >= 0; i--) {
        if (abs >= d.tracks[i].startOffset - 0.5) {
          ti = i;
          break;
        }
      }
      for (final i in [ti, ti + 1]) {
        if (i < 0 || i >= d.tracks.length) continue;
        final t = d.tracks[i];
        if (t.ino.isEmpty) continue;
        cache.enqueue(bookId: it.id, ino: t.ino, ext: '.m4a', url: api.transcodedFileUrlFor(it.id, t.ino));
      }
    } catch (_) {}
  }

  // ---------------- 轨道切换 ----------------

  int _trackIndexForAbsolute(double abs) {
    final ts = tracks;
    for (int i = ts.length - 1; i >= 0; i--) {
      if (abs >= ts[i].startOffset - 0.5) return i;
    }
    return 0;
  }

  /// 服务端回退地址：优先会话 contentUrl，其次 /file/ 直链（不依赖会话）
  String? _fallbackUrlFor(Track t) {
    if (t.contentUrl != null && t.contentUrl!.isNotEmpty) return api.fullTrackUrl(t.contentUrl!);
    if (t.ino.isNotEmpty && item != null) return api.fileUrlFor(item!.id, t.ino);
    return null;
  }

  /// 本地缓存查找：
  /// 1) 转码书：固定 .m4a（AAC 缓存格式）
  /// 2) 普通书：扩展名回退序列（含旧版可能写入的扩展名，命中后自动纠正）
  /// [skipLocal] 或本运行内曾加载失败（_badLocalInos）时直接跳过本地
  String? _localCachedFor(Track t, {bool skipLocal = false}) {
    final it = item;
    if (it == null || t.ino.isEmpty) return null;
    if (skipLocal || _badLocalInos.contains(t.ino)) return null;
    if (codecNeedsTranscode(t.codec, t.mimeType)) {
      return cache.completePath(it.id, t.ino, '.m4a', validate: true);
    }
    final declared = t.ext.isNotEmpty ? t.ext : null;
    final candidates = declared != null
        ? <String>[declared, ...CacheManager.fallbackExts.where((e) => e != declared)]
        : CacheManager.fallbackExts;
    for (final ext in candidates) {
      final p = cache.completePath(it.id, t.ino, ext, validate: true);
      if (p != null) return p;
    }
    return null;
  }

  void _markDirectFailed(Track? t) {
    if (t != null && t.ino.isNotEmpty) _directBadInos.add(t.ino);
    _directFailCount += 1;
    if (_directFailCount >= 2) _directOk = false; // 多次失败视为网络层不可达，本次运行不再尝试直连
  }

  /// 本地文件加载失败时自愈：拉黑该章节、删除坏文件、后台重新排队下载
  void _selfHealLocalFile(Track t, String fileUrl, {required String reason}) {
    try {
      final fp = Uri.parse(fileUrl).toFilePath();
      if (!cache.isUnderRoot(fp)) return;
      _badLocalInos.add(t.ino);
      if (reason.toLowerCase().contains('timed out')) {
        // 超时可能只是系统忙：先拉黑走网络，文件保留待下次会话再试
        return;
      }
      debugPrint('本地缓存加载失败，自愈删除并重下: ${p.basename(fp)} ($reason)');
      cache.removeCacheFile(fp);
      final it = item;
      if (it != null && t.ino.isNotEmpty) {
        final isTrans = codecNeedsTranscode(t.codec, t.mimeType);
        final url2 = isTrans
            ? api.transcodedFileUrlFor(it.id, t.ino)
            : ((t.contentUrl != null && t.contentUrl!.isNotEmpty)
                ? api.fullTrackUrl(t.contentUrl!)
                : api.fileUrlFor(it.id, t.ino));
        cache.enqueue(
          bookId: it.id,
          ino: t.ino,
          ext: isTrans ? '.m4a' : CacheManager.mediaExt(ext: t.ext, mimeType: t.mimeType, codec: t.codec),
          url: url2,
        );
      }
    } catch (e) {
      debugPrint('self-heal failed: $e');
    }
  }

  /// 直连就绪探测：≤1.5 秒快速判断直连地址是否可达；结果缓存（一次/运行）
  Future<bool> _ensureDirectProbed(String url) {
    if (_directOk != null) return Future.value(_directOk!);
    return _directProbing ??= api.reachable(url).then((ok) {
      _directOk = ok;
      _directProbing = null;
      if (!ok) debugPrint('直连不可达，本次运行使用服务端路径');
      return ok;
    }).catchError((_) {
      _directProbing = null;
      return false;
    });
  }

  /// 回退到服务端地址重试（单飞：同一时间只允许一个回退重试在途）
  Future<void> _recoverToServer(Track t, {required double inTrack, required bool autoplay, required bool wasDirect}) async {
    if (_recovering || _closing) return;
    _recovering = true;
    try {
      _usedFallback = true;
      if (wasDirect) _markDirectFailed(t);
      debugPrint('回退服务端重试: ${t.title}');
      await _playTrackIndex(index, inTrack: inTrack, autoplay: autoplay, forceProxy: true, skipLocal: true);
    } finally {
      _recovering = false;
    }
  }

  /// 创建 HLS 转码会话（AAC 模式失败时的安全网）
  Future<void> _ensureHlsSession() async {
    final it = item;
    if (it == null) return;
    if (session != null && session!.isTranscode) return;
    try {
      session = await api.startPlay(it.id, forceTranscode: true);
    } catch (e) {
      debugPrint('hls session 创建失败: $e');
    }
  }

  String _friendlyPlayError(String raw) {
    if (raw.contains('-1100') || raw.contains('404') || raw.contains('not found') || raw.contains('资源不存在')) {
      return '内容已不存在（404）：该条目可能已在服务器上被删除，请返回书库刷新后重新选择';
    }
    if (raw.contains('-1004')) {
      return '无法连接服务器（-1004）：请检查手机网络（家中 WiFi 或 Tailscale）后重试';
    }
    if (raw.contains('-1001') || raw.toLowerCase().contains('timed out')) {
      return '网络超时：请检查手机网络后重试';
    }
    return '无法播放：$raw';
  }

  ({String url, Map<String, String> headers}) _sourceForTrack(int ti, {bool forceProxy = false, bool skipLocal = false}) {
    final t = tracks[ti];
    final allowLocal = !skipLocal && !_badLocalInos.contains(t.ino);
    // 转码书（AAC 缓存模式）：手机缓存的 AAC 文件 → 服务端单集转码直链
    if (codecNeedsTranscode(t.codec, t.mimeType)) {
      final aac = (allowLocal && t.ino.isNotEmpty)
          ? cache.completePath(item!.id, t.ino, '.m4a', validate: true)
          : null;
      if (aac != null) return (url: Uri.file(aac).toString(), headers: const {});
      if (t.ino.isNotEmpty && item != null) {
        return (url: api.transcodedFileUrlFor(item!.id, t.ino), headers: api.authHeaders);
      }
    }
    // 1) 本地缓存（扩展名回退 + 内容校验）
    if (allowLocal) {
      final declared = t.ext.isNotEmpty ? t.ext : null;
      final candidates = declared != null
          ? <String>[declared, ...CacheManager.fallbackExts.where((e) => e != declared)]
          : CacheManager.fallbackExts;
      for (final ext in candidates) {
        final local = cache.completePath(item!.id, t.ino, ext, validate: true);
        if (local != null) return (url: Uri.file(local).toString(), headers: const {});
      }
    }
    // 极速直连（302 到 115 CDN）：仅在可用时启用
    if (!forceProxy &&
        settings.directMode &&
        _directOk != false &&
        !_directBadInos.contains(t.ino) &&
        t.path.startsWith('http')) {
      return (url: t.path, headers: const {});
    }
    if (t.contentUrl != null && t.contentUrl!.isNotEmpty) {
      return (url: api.fullTrackUrl(t.contentUrl!), headers: api.authHeaders);
    }
    if (t.ino.isNotEmpty && item != null) {
      return (url: api.fileUrlFor(item!.id, t.ino), headers: api.authHeaders);
    }
    return (url: t.path, headers: const {});
  }

  Future<void> _playTrackIndex(int ti, {double inTrack = 0, bool autoplay = true, bool forceProxy = false, bool skipLocal = false}) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    // 缓存优先：命中本地文件时绝不做任何网络探测（真·秒播）
    final cachedLocal = _localCachedFor(t, skipLocal: skipLocal);
    if (cachedLocal == null &&
        !skipLocal &&
        !forceProxy &&
        settings.directMode &&
        _directOk == null &&
        t.path.startsWith('http') &&
        !codecNeedsTranscode(t.codec, t.mimeType) &&
        !_directBadInos.contains(t.ino)) {
      await _ensureDirectProbed(t.path);
    }
    final src = _sourceForTrack(ti, forceProxy: forceProxy, skipLocal: skipLocal);
    _lastLoadUrl = src.url;
    index = ti;
    _absolute = t.startOffset + inTrack;
    _lastSourceDirect = !forceProxy && t.path.startsWith('http') && src.url == t.path;
    var pos = inTrack;
    if (ti == 0 && settings.skipIntro > 0 && pos < 1) pos = settings.skipIntro.toDouble();
    final mySeq = ++_loadSeq;
    _loading = true;
    // AAC 模式首播要等服务器"边转边播"的首包，放宽超时；普通文件 10 秒足够
    final loadTimeout = _aacMode ? const Duration(seconds: 45) : const Duration(seconds: 10);
    try {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(src.url), headers: src.headers),
        initialPosition: Duration(milliseconds: (pos * 1000).round()),
      ).timeout(loadTimeout);
    } on PlayerInterruptedException {
      // 被更新的加载请求取代：正常切换流程，静默忽略
      debugPrint('加载被新请求取代（忽略）');
      return;
    } catch (e) {
      final msg = '$e';
      if (msg.contains('nterrupte')) {
        // 兼容以字符串形式出现的 Loading interrupted（被更新的加载取代）
        debugPrint('加载被取代（忽略）: $msg');
        return;
      }
      debugPrint('setAudioSource 失败: $e');
      if (mySeq != _loadSeq) return; // 已有更新的加载在跑，交给它处理
      // 本地文件加载失败：自愈（拉黑 + 删除坏文件 + 后台重下），随后回退网络
      if (src.url.startsWith('file://')) {
        _selfHealLocalFile(t, src.url, reason: msg);
      }
      // AAC 缓存模式失败 → 回退 HLS 转码模式（安全网）
      if (_aacMode && !forceProxy && codecNeedsTranscode(t.codec, t.mimeType)) {
        _aacMode = false;
        debugPrint('AAC 缓存模式失败，回退 HLS 转码');
        await _ensureHlsSession();
        await _startAt(_absolute, autoplay: autoplay);
        return;
      }
      if (!forceProxy && !_usedFallback) {
        final fb = _fallbackUrlFor(t);
        if (fb != null) {
          await _recoverToServer(t, inTrack: inTrack, autoplay: autoplay, wasDirect: _lastSourceDirect);
          return;
        }
      }
      error = _friendlyPlayError(msg);
      notifyListeners();
      return;
    } finally {
      if (mySeq == _loadSeq) _loading = false;
    }
    if (mySeq != _loadSeq) return; // 已被更新的加载取代，别覆盖它的状态
    if (_lastSourceDirect) _directOk = true;
    error = null;
    _reportMediaItem();
    _persistPos(force: true);
    if (autoplay) unawaited(player.play());
    _ensureListenTimer();
    _warmAhead();
    // 初始跳转保险：个别流 initialPosition 不生效时，起播 6 秒后仍在开头则强制 seek 到续播点
    if (autoplay && pos > 30) {
      final expect = pos;
      final myIdx = ti;
      unawaited(() async {
        await Future.delayed(const Duration(seconds: 6));
        if (_closing || index != myIdx || !player.playing) return;
        final cur = player.position.inMilliseconds / 1000.0;
        if (cur < 3.0) {
          try {
            await player.seek(Duration(milliseconds: (expect * 1000).round()));
          } catch (_) {}
        }
      }());
    }
    notifyListeners();
  }

  Future<void> playAt(int ti) async {
    if (ti < 0 || ti >= tracks.length) return;
    if (hlsMode) {
      await seekAbsolute(tracks[ti].startOffset + 0.01);
    } else {
      _usedFallback = false;
      await _playTrackIndex(ti, inTrack: 0, autoplay: true);
    }
  }

  Future<void> nextTrack({bool userInitiated = false}) async {
    if (!hasBook || tracks.isEmpty) return;
    if (hlsMode) {
      final ni = min(index + 1, tracks.length - 1);
      await seekAbsolute(tracks[ni].startOffset + 0.01);
    } else if (index < tracks.length - 1) {
      _usedFallback = false;
      await _playTrackIndex(index + 1);
    }
  }

  Future<void> prevTrack() async {
    if (!hasBook || tracks.isEmpty) return;
    if (hlsMode) {
      final pi = max(index - 1, 0);
      await seekAbsolute(tracks[pi].startOffset + 0.01);
      return;
    }
    if (player.position.inSeconds > 5) {
      await player.seek(Duration.zero);
    } else if (index > 0) {
      _usedFallback = false;
      await _playTrackIndex(index - 1);
    } else {
      await player.seek(Duration.zero);
    }
  }

  Future<void> toggle() async {
    if (!hasBook) return;
    if (player.playing) {
      await player.pause();
      _persistPos(force: true);
      unawaited(syncNow());
    } else {
      // 恢复态（item 已加载但还没起播）：需要真正 open 起播
      if (session == null && player.processingState == ProcessingState.idle) {
        final it = item;
        if (it != null) {
          final abs = _absolute;
          await stopAndClose(closeSession: false);
          await open(it, startAt: abs, autoplay: true);
          return;
        }
      }
      unawaited(player.play());
    }
  }

  Future<void> seekRelative(double delta) async {
    if (!hasBook) return;
    final target = (_absolute + delta).clamp(0.0, max(0.0, duration - 1)).toDouble();
    await seekAbsolute(target);
  }

  Future<void> seekAbsolute(double abs) async {
    if (!hasBook || tracks.isEmpty) return;
    final tgt = abs.clamp(0.0, max(0.0, duration - 1)).toDouble();
    _absolute = tgt;
    if (hlsMode) {
      await player.seek(Duration(milliseconds: (tgt * 1000).round()));
      index = _trackIndexForAbsolute(tgt);
      _reportMediaItem();
      // 触发服务端窗口本地化（HLS 转码书：探测当前集所在文件）
      unawaited(warmTrack(index));
      notifyListeners();
    } else {
      final ti = _trackIndexForAbsolute(tgt);
      final inTrack = max(0.0, tgt - tracks[ti].startOffset);
      if (ti == index && (player.processingState == ProcessingState.ready || player.processingState == ProcessingState.buffering)) {
        await player.seek(Duration(milliseconds: (inTrack * 1000).round()));
      } else {
        _usedFallback = false;
        await _playTrackIndex(ti, inTrack: inTrack, autoplay: true);
      }
      // AAC 转码书：目标集排队下载（重听秒播）
      if (_aacMode) {
        final t2 = tracks[ti];
        if (t2.ino.isNotEmpty && item != null) {
          cache.enqueue(bookId: item!.id, ino: t2.ino, ext: '.m4a', url: api.transcodedFileUrlFor(item!.id, t2.ino));
        }
      }
    }
    _warmAhead();
  }

  Future<void> setSpeed(double s, {bool persist = true}) async {
    await player.setSpeed(s);
    if (persist && item != null) {
      await settings.setSpeedFor(item!.id, s);
    }
    notifyListeners();
  }

  void setSleep(SleepMode mode, {Duration? duration}) {
    sleepMode = mode;
    _sleepUntil = (mode == SleepMode.timed && duration != null) ? DateTime.now().add(duration) : null;
    _ensureListenTimer();
    notifyListeners();
  }

  // ---------------- 事件处理 ----------------

  void _updateAbsolute(double pos) {
    if (!hasBook || tracks.isEmpty) return;
    if (session != null && hlsMode) {
      _absolute = pos;
      final ti = _trackIndexForAbsolute(pos);
      if (ti != index) {
        index = ti;
        _reportMediaItem();
        // HLS 转码书自然跨集：触发服务端窗口本地化滑动
        unawaited(warmTrack(ti));
      }
    } else {
      final t = track;
      _absolute = (t?.startOffset ?? 0) + pos;
      if (settings.skipOutro > 0 && t != null && t.duration > settings.skipOutro + 5) {
        if (pos > t.duration - settings.skipOutro && pos < t.duration - 0.5 && player.playing) {
          unawaited(nextTrack());
        }
      }
    }
    _persistPos();
  }

  int _lastPosSaveMs = 0;

  /// 本地持久化播放位置（节流 2.5s；force 立即写）
  void _persistPos({bool force = false}) {
    final it = item;
    if (it == null || _absolute <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastPosSaveMs < 2500) return;
    _lastPosSaveMs = now;
    unawaited(settings.saveLastPos(it.id, _absolute));
  }

  Future<void> _onCompleted() async {
    if (_closing || loading) return;
    if (sleepMode == SleepMode.endOfChapter) {
      sleepMode = SleepMode.off;
      notifyListeners();
      return;
    }
    if (hlsMode) {
      await syncNow();
      return;
    }
    if (index < tracks.length - 1) {
      _usedFallback = false;
      await _playTrackIndex(index + 1);
    } else {
      await syncNow();
    }
  }

  void _onPlayerError(Object e) async {
    if (_closing) return;
    // 被更新的加载取代产生的“中断”不是真错误，静默忽略
    if (e is PlayerInterruptedException || '$e'.contains('nterrupte')) return;
    // 加载在途时错误交给 _playTrackIndex 的 catch 统一处理（防止双重回退竞态）
    if (_loading || _recovering) return;
    final t = track;
    debugPrint('player error: $e');
    // 本地文件播放中出错：自愈并回退网络
    final lastUrl = _lastLoadUrl;
    if (t != null && lastUrl != null && lastUrl.startsWith('file://')) {
      _selfHealLocalFile(t, lastUrl, reason: '$e');
    }
    if (!_usedFallback && !hlsMode && t != null && (_lastSourceDirect || (lastUrl?.startsWith('file://') ?? false))) {
      final fb = _fallbackUrlFor(t);
      if (fb != null) {
        await _recoverToServer(t,
            inTrack: player.position.inMilliseconds / 1000.0, autoplay: player.playing, wasDirect: _lastSourceDirect);
        return;
      }
    }
    error = _friendlyPlayError('$e');
    notifyListeners();
  }

  // ---------------- 同步 ----------------

  void _startSyncLoop() {
    _syncTimer?.cancel();
    final secs = settings.syncInterval.clamp(5, 600);
    _syncTimer = Timer.periodic(Duration(seconds: secs), (_) {
      // 会话缺失自愈：快速起播时后台建会话失败则重试
      if (session == null && hasBook) unawaited(_ensureSession());
      syncNow();
      // 流水线补货：保持“后续 N 章”缓存队列持续推进
      _warmAhead(probe: false);
    });
  }

  Future<void> syncNow() async {
    final s = session;
    if (s == null || _closing) return;
    final listen = _unsynced;
    final abs = _absolute;
    // 防呆：无有效位置且无收听时长时不发送（避免把服务端进度刷成 0）
    if (abs < 0.5 && listen < 0.5) return;
    if (listen < 0.5 && (abs - _lastSyncedAbs).abs() < 0.5) return;
    try {
      await api.syncSession(s.id, currentTime: abs, timeListened: listen, duration: duration);
      _unsynced = 0;
      _lastSyncedAbs = abs;
      // 节流刷新 me（每 30 秒），让 progressOf / continueList 拿到最新进度
      if (DateTime.now().difference(_lastMeRefresh).inSeconds > 30) {
        _lastMeRefresh = DateTime.now();
        unawaited(_refreshMe());
      }
    } catch (e) {
      debugPrint('sync failed: $e');
      final msg = '$e';
      if (msg.contains('404') || msg.contains('资源不存在')) {
        // 会话已失效（会话过期/条目被删）：清掉，由同步环自愈重建
        session = null;
      }
    }
  }

  Future<void> _refreshMe() async {
    try {
      final m = await api.me();
      final o = owner;
      if (o != null) {
        o.me = m;
        o.notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> stopAndClose({bool closeSession = true}) async {
    if (session == null && item == null) return;
    _closing = true;
    _syncTimer?.cancel();
    _syncTimer = null;
    _listenTimer?.cancel();
    _listenTimer = null;
    try {
      await player.pause();
    } catch (_) {}
    _persistPos(force: true);
    final s = session;
    if (s != null && closeSession) {
      try {
        if (_absolute > 0.5) {
          await api.closeSession(s.id, sync: {
            'currentTime': _absolute,
            'timeListened': _unsynced,
            'duration': duration,
          });
        } else {
          // 无有效位置时不做带 sync 的关闭（避免把服务端进度刷成 0）
          await api.closeSession(s.id);
        }
      } catch (e) {
        debugPrint('close session failed: $e');
      }
    }
    try {
      await player.stop();
    } catch (_) {}
    session = null;
    item = null;
    detail = null;
    index = 0;
    _absolute = 0;
    _unsynced = 0;
    _queueReported = false;
    loading = false;
    _closing = false;
    notifyListeners();
    // 关闭后刷新进度列表（继续收听/迷你播放器）
    unawaited(_refreshMe());
  }

  void _ensureListenTimer() {
    final need = player.playing || sleepMode == SleepMode.timed;
    if (need && _listenTimer == null) {
      _listenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (player.playing) _unsynced += 1;
        if (sleepMode == SleepMode.timed) {
          if (_sleepUntil != null && DateTime.now().isAfter(_sleepUntil!)) {
            sleepMode = SleepMode.off;
            _sleepUntil = null;
            player.pause();
            unawaited(syncNow());
          }
          notifyListeners();
        }
      });
    } else if (!need && _listenTimer != null) {
      _listenTimer!.cancel();
      _listenTimer = null;
    }
  }

  // ---------------- 预取 / 预热 ----------------

  /// 预热某章（同时承担“触发服务端窗口本地化 / AAC 生成”的职责）：
  /// - 转码书 AAC 模式：排队下载该集到手机（服务端边转边播并将结果落盘）
  /// - 传统 HLS 转码书：探测 /file/ 入口触发窗口本地化
  /// - 直连已确认可用：走直连预热（顺带预检 CDN attachment，提前拉黑这类文件）
  /// - 其他：走服务端预热（解析 302 直链）
  Future<void> warmTrack(int ti) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    try {
      if (codecNeedsTranscode(t.codec, t.mimeType)) {
        if (item == null || t.ino.isEmpty) return;
        if (_aacMode) {
          cache.enqueue(bookId: item!.id, ino: t.ino, ext: '.m4a', url: api.transcodedFileUrlFor(item!.id, t.ino));
        } else {
          // 传统 HLS：探测 /file/ 入口触发窗口本地化
          await api.warm(api.fileUrlFor(item!.id, t.ino));
        }
        return;
      }
      final canTryDirect = settings.directMode &&
          _directOk == true &&
          !_directBadInos.contains(t.ino) &&
          t.path.startsWith('http');
      if (canTryDirect) {
        final r = await api.warm(t.path);
        if (r != null) {
          final cd = (r.headers.value('content-disposition') ?? '').toLowerCase();
          if (cd.contains('attachment')) {
            _directBadInos.add(t.ino);
            debugPrint('直连预检：CDN 返回 attachment，跳过直连: ${t.title}');
          }
          return;
        }
        // 直连预热失败（不可达/超时）：继续做服务端预热
      }
      if (t.contentUrl != null && t.contentUrl!.isNotEmpty) {
        await api.warm(api.fullTrackUrl(t.contentUrl!));
      } else if (item != null && t.ino.isNotEmpty) {
        await api.warm(api.fileUrlFor(item!.id, t.ino));
      }
    } catch (_) {}
  }

  /// 预取后续章节：[probe] 控制是否顺带做 2 字节预热请求。
  /// - 普通书：下载服务端原文件到手机（本地镜像优先，稳定且快）
  /// - 转码书 AAC 模式：下载服务端单集转码结果（.m4a）到手机 → 本地秒播；当前集也下载
  /// - 传统 HLS 转码书：对“下一集”发一次探测，触发服务端窗口本地化
  void _warmAhead({bool probe = true}) {
    final it = item;
    if (it == null || tracks.isEmpty) return;
    final whole = settings.autoCacheWholeBook;
    final nextN = settings.autoCacheNext.clamp(0, 10);
    if (!whole && nextN == 0) return;
    final last = whole ? tracks.length - 1 : min(index + nextN, tracks.length - 1);
    for (int i = index + 1; i <= last; i++) {
      final nt = tracks[i];
      if (nt.ino.isEmpty) continue;
      final isTrans = codecNeedsTranscode(nt.codec, nt.mimeType);
      if (isTrans) {
        if (_aacMode) {
          cache.enqueue(bookId: it.id, ino: nt.ino, ext: '.m4a', url: api.transcodedFileUrlFor(it.id, nt.ino));
        } else if (probe && i == index + 1) {
          // 传统转码书：对“下一集”发一次探测，触发服务端窗口本地化
          unawaited(warmTrack(i));
        }
        continue;
      }
      if (probe) unawaited(warmTrack(i));
      // 缓存扩展名归一化：.strm 等非音频扩展 → 按 mime/codec 推断成音频扩展
      final ext = CacheManager.mediaExt(ext: nt.ext, mimeType: nt.mimeType, codec: nt.codec);
      final url = (nt.contentUrl != null && nt.contentUrl!.isNotEmpty) ? api.fullTrackUrl(nt.contentUrl!) : api.fileUrlFor(it.id, nt.ino);
      cache.enqueue(bookId: it.id, ino: nt.ino, ext: ext, url: url);
    }
    // AAC 模式：把“当前集”也排队下载到手机（重听/回退时本地秒播）
    if (_aacMode && index >= 0 && index < tracks.length) {
      final cur = tracks[index];
      if (cur.ino.isNotEmpty) {
        cache.enqueue(bookId: it.id, ino: cur.ino, ext: '.m4a', url: api.transcodedFileUrlFor(it.id, cur.ino));
      }
    }
  }

  // ---------------- 媒体信息上报 ----------------

  void _reportMediaItem({bool forceQueue = false}) {
    final h = handler;
    final it = item;
    if (h == null || it == null || tracks.isEmpty) return;
    if (forceQueue || !_queueReported) {
      h.reportQueue(tracks, it, artUri: _artUri);
      _queueReported = true;
    } else {
      h.updateIndex(index.clamp(0, tracks.length - 1), it, artUri: _artUri);
    }
  }

  Future<void> _ensureArt() async {
    final it = item;
    if (it == null || kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'haven_cache', 'covers'));
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, '${it.id}.jpg'));
      if (!f.existsSync()) {
        final resp = await api.dio.get<List<int>>(
          api.coverUrl(it.id, width: 600),
          options: Options(responseType: ResponseType.bytes, headers: api.authHeaders),
        );
        await f.writeAsBytes(resp.data ?? const []);
      }
      _artUri = Uri.file(f.path);
      _reportMediaItem(forceQueue: true);
    } catch (_) {}
  }
}
