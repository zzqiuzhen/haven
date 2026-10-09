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
  final Set<String> _directBadInos = {}; // 直连打不开的具体章节（CDN attachment 等），跳过直连走服务端
  int _directFailCount = 0;
  int _loadSeq = 0; // 加载序号：后发加载取代先发，先发的失败/中断静默忽略
  bool _loading = false; // 是否有加载请求在途（错误流事件在此期间交给 catch 统一处理）
  bool _recovering = false; // 回退重试单飞锁，杜绝多重回退互相打断
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
  double get duration => (detail?.duration ?? 0) > 0 ? detail!.duration : (session?.duration ?? 0);
  double get absolute => _absolute;
  double get trackPosition => player.position.inMilliseconds / 1000.0;

  /// 全书已缓冲到的位置（秒）
  double get bufferedAbsolute {
    if (session == null) return 0;
    final b = player.bufferedPosition.inMilliseconds / 1000.0;
    if (isTranscode) return b;
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
    // 优先本机最后播放记录（最新最准），其次服务端最近进度
    String? id;
    double abs = 0;
    final lp = settings.lastPos;
    if (lp != null && lp.$1.isNotEmpty) {
      id = lp.$1;
      abs = lp.$2;
    } else {
      final m = o.me;
      if (m == null) return;
      final ps = m.mediaProgress
          .where((p) => !p.hideFromContinue && !p.isFinished && p.currentTime > 1)
          .toList();
      if (ps.isEmpty) return;
      ps.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
      id = ps.first.libraryItemId;
      abs = ps.first.currentTime;
    }
    if (id == null || id.isEmpty) return;
    try {
      final d = await _loadDetail(id);
      final it = await o.ensureItem(id);
      item = it;
      detail = d;
      index = _trackIndexForAbsolute(abs);
      _absolute = abs;
      loading = false;
      error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('restoreLast failed: $e');
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
    await stopAndClose(closeSession: true);
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
        // 转码书必须先建会话拿 HLS 地址；详情页若已预热且未过期则直接复用
        final pre = _preSession;
        if (pre != null && _preItem?.id == it.id && DateTime.now().difference(_preAt).inMinutes < 5) {
          session = pre;
        } else {
          session = await api.startPlay(it.id, forceTranscode: true);
        }
        _preSession = null;
        _preItem = null;
        await _startAt(start, autoplay: autoplay);
        _startSyncLoop();
      } else {
        // 直连/代理书：立即起播（缓存命中秒开，无需等会话），会话后台创建
        await _startAt(start, autoplay: autoplay);
        unawaited(_ensureSession());
      }
      unawaited(_ensureArt());
    } catch (e) {
      if (!'$e'.contains('nterrupte')) {
        error = '$e';
      }
      debugPrint('open book failed: $e');
    }
    loading = false;
    notifyListeners();
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
    if (isTranscode) {
      if (session == null) {
        error = '转码会话创建失败，请检查网络后重试';
        notifyListeners();
        return;
      }
      // HLS 冷启动预热：服务端转码器需先产出首个分片（未就绪前请求会 404），
      // 轮询等待“播放列表中的首个真实分片”可用（不请求 output-0.ts——当续播点
      // 非 0 时服务端会因回退请求而 Reset Transcode，把转码起点重置到 0）
      await _warmHlsStream();
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(_hlsUrl()), headers: api.authHeaders),
      );
      await player.seek(Duration(milliseconds: (abs * 1000).round()));
      index = _trackIndexForAbsolute(abs);
      _absolute = abs;
      if (autoplay) unawaited(player.play());
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
  LibItem? _preItem;
  DateTime _preAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 进入书籍详情页时调用：提前创建转码会话并触发一次播放列表请求，起播免等冷启动
  Future<void> prewarmTranscode(LibItem it) async {
    if (session != null || player.playing || _closing) return;
    if (_preSession != null && _preItem?.id == it.id) return;
    try {
      final s = await api.startPlay(it.id, forceTranscode: true);
      _preSession = s;
      _preItem = it;
      _preAt = DateTime.now();
      // 只请求播放列表做预热；不请求 output-0.ts（避免服务端误判而重置转码起点）
      unawaited(() async {
        try {
          await api.dio.get<String>(
            api.fullTrackUrl('/hls/${s.id}/output.m3u8'),
            options: Options(
              headers: api.authHeaders,
              responseType: ResponseType.plain,
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
        } catch (_) {}
      }());
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

  void _markDirectFailed(Track? t) {
    if (t != null && t.ino.isNotEmpty) _directBadInos.add(t.ino);
    _directFailCount += 1;
    if (_directFailCount >= 2) _directOk = false; // 多次失败视为网络层不可达，本次运行不再尝试直连
  }

  /// 回退到服务端地址重试（单飞：同一时间只允许一个回退重试在途）
  Future<void> _recoverToServer(Track t, {required double inTrack, required bool autoplay, required bool wasDirect}) async {
    if (_recovering || _closing) return;
    _recovering = true;
    try {
      _usedFallback = true;
      if (wasDirect) _markDirectFailed(t);
      debugPrint('回退服务端重试: ${t.title}');
      await _playTrackIndex(index, inTrack: inTrack, autoplay: autoplay, forceProxy: true);
    } finally {
      _recovering = false;
    }
  }

  ({String url, Map<String, String> headers}) _sourceForTrack(int ti, {bool forceProxy = false}) {
    final t = tracks[ti];
    final ext = t.ext.isNotEmpty ? t.ext : '.mp3';
    // 本地缓存（带有效性校验：损坏文件自动清除并回退网络）
    final local = cache.completePath(item!.id, t.ino, ext, validate: true);
    if (local != null) return (url: Uri.file(local).toString(), headers: const {});
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

  Future<void> _playTrackIndex(int ti, {double inTrack = 0, bool autoplay = true, bool forceProxy = false}) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    final src = _sourceForTrack(ti, forceProxy: forceProxy);
    index = ti;
    _absolute = t.startOffset + inTrack;
    _lastSourceDirect = !forceProxy && t.path.startsWith('http') && src.url == t.path;
    var pos = inTrack;
    if (ti == 0 && settings.skipIntro > 0 && pos < 1) pos = settings.skipIntro.toDouble();
    final mySeq = ++_loadSeq;
    _loading = true;
    try {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(src.url), headers: src.headers),
        initialPosition: Duration(milliseconds: (pos * 1000).round()),
      ).timeout(const Duration(seconds: 10));
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
      if (!forceProxy && !_usedFallback) {
        final fb = _fallbackUrlFor(t);
        if (fb != null) {
          await _recoverToServer(t, inTrack: inTrack, autoplay: autoplay, wasDirect: _lastSourceDirect);
          return;
        }
      }
      error = '无法播放：$e';
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
    if (isTranscode) {
      await seekAbsolute(tracks[ti].startOffset + 0.01);
    } else {
      _usedFallback = false;
      await _playTrackIndex(ti, inTrack: 0, autoplay: true);
    }
  }

  Future<void> nextTrack({bool userInitiated = false}) async {
    if (!hasBook || tracks.isEmpty) return;
    if (isTranscode) {
      final ni = min(index + 1, tracks.length - 1);
      await seekAbsolute(tracks[ni].startOffset + 0.01);
    } else if (index < tracks.length - 1) {
      _usedFallback = false;
      await _playTrackIndex(index + 1);
    }
  }

  Future<void> prevTrack() async {
    if (!hasBook || tracks.isEmpty) return;
    if (isTranscode) {
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
    if (isTranscode) {
      await player.seek(Duration(milliseconds: (tgt * 1000).round()));
      index = _trackIndexForAbsolute(tgt);
      _reportMediaItem();
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
    if (session != null && isTranscode) {
      _absolute = pos;
      final ti = _trackIndexForAbsolute(pos);
      if (ti != index) {
        index = ti;
        _reportMediaItem();
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
    if (_closing) return;
    if (sleepMode == SleepMode.endOfChapter) {
      sleepMode = SleepMode.off;
      notifyListeners();
      return;
    }
    if (isTranscode) {
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
    if (!_usedFallback && !isTranscode && t != null && _lastSourceDirect) {
      final fb = _fallbackUrlFor(t);
      if (fb != null) {
        await _recoverToServer(t,
            inTrack: player.position.inMilliseconds / 1000.0, autoplay: player.playing, wasDirect: true);
        return;
      }
    }
    error = '播放出错：$e';
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

  /// 预热某章：直连可用时先走直连预热（顺带预检 CDN 是否会返回 attachment——
  /// 这类文件 AVPlayer 会拒播，提前拉黑避免用户点击时中断）；否则走服务端预热。
  Future<void> warmTrack(int ti) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    try {
      final canTryDirect = settings.directMode &&
          _directOk != false &&
          !_directBadInos.contains(t.ino) &&
          t.path.startsWith('http');
      if (canTryDirect) {
        final r = await api.warm(t.path);
        if (r != null) {
          if (_directOk == null) _directOk = true;
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

  /// 预取后续章节：[probe] 控制是否顺带做 2 字节预热请求；
  /// 下载统一走服务端地址（本地镜像优先服务，稳定且快）。
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
      // 转码书籍（WMA 等）不支持轨道级离线缓存（服务端按需转码，无整文件可下）
      if (codecNeedsTranscode(nt.codec, nt.mimeType)) continue;
      if (probe) unawaited(warmTrack(i));
      final ext = nt.ext.isNotEmpty ? nt.ext : '.mp3';
      final url = (nt.contentUrl != null && nt.contentUrl!.isNotEmpty) ? api.fullTrackUrl(nt.contentUrl!) : api.fileUrlFor(it.id, nt.ino);
      cache.enqueue(bookId: it.id, ino: nt.ino, ext: ext, url: url);
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
