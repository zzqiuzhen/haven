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
  Uri? _artUri;
  DateTime _lastNotify = DateTime.now();

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
  bool get hasBook => session != null && item != null;
  String get bookId => item?.id ?? '';

  /// 供 UI 触发刷新（替代外部直接调用 notifyListeners）
  void touch() => notifyListeners();

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
      if (autoplay) await player.play();
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
      final needTranscode = detail!.tracks.any((t) => codecNeedsTranscode(t.codec, t.mimeType));
      session = await api.startPlay(it.id, forceTranscode: needTranscode);
      if (!session!.isTranscode) {
        for (final st in session!.tracks) {
          final di = detail!.tracks.indexWhere((d) => (d.ino.isNotEmpty && d.ino == st.ino) || d.index == st.index);
          if (di >= 0) {
            detail!.tracks[di].contentUrl = st.contentUrl;
          }
        }
      }
      var start = startAt;
      if (duration > 0 && start >= duration - 20) start = 0;
      final sp = settings.speedFor(it.id);
      await player.setSpeed(sp);
      await _startAt(start, autoplay: autoplay);
      _startSyncLoop();
      unawaited(_ensureArt());
    } catch (e) {
      error = '$e';
      debugPrint('open book failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<BookDetail> _loadDetail(String id) async {
    if (detail != null && detail!.id == id) return detail!;
    return await api.itemDetail(id);
  }

  Future<void> _startAt(double abs, {bool autoplay = true}) async {
    if (session == null || tracks.isEmpty) return;
    error = null;
    if (isTranscode) {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(_hlsUrl()), headers: api.authHeaders),
      );
      await player.seek(Duration(milliseconds: (abs * 1000).round()));
      index = _trackIndexForAbsolute(abs);
      _absolute = abs;
      if (autoplay) await player.play();
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

  // ---------------- 轨道切换 ----------------

  int _trackIndexForAbsolute(double abs) {
    final ts = tracks;
    for (int i = ts.length - 1; i >= 0; i--) {
      if (abs >= ts[i].startOffset - 0.5) return i;
    }
    return 0;
  }

  ({String url, Map<String, String> headers}) _sourceForTrack(int ti, {bool forceProxy = false}) {
    final t = tracks[ti];
    final ext = t.ext.isNotEmpty ? t.ext : '.mp3';
    final local = cache.completePath(item!.id, t.ino, ext);
    if (local != null) return (url: Uri.file(local).toString(), headers: const {});
    if (!forceProxy && settings.directMode && t.path.startsWith('http')) {
      return (url: t.path, headers: const {});
    }
    if (t.contentUrl != null && t.contentUrl!.isNotEmpty) {
      return (url: api.fullTrackUrl(t.contentUrl!), headers: api.authHeaders);
    }
    return (url: t.path, headers: const {});
  }

  Future<void> _playTrackIndex(int ti, {double inTrack = 0, bool autoplay = true, bool forceProxy = false}) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    final src = _sourceForTrack(ti, forceProxy: forceProxy);
    index = ti;
    _absolute = t.startOffset + inTrack;
    _usedFallback = false;
    _lastSourceDirect = !forceProxy && settings.directMode && t.path.startsWith('http') && !src.url.startsWith('file:');
    var pos = inTrack;
    if (ti == 0 && settings.skipIntro > 0 && pos < 1) pos = settings.skipIntro.toDouble();
    try {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(src.url), headers: src.headers),
        initialPosition: Duration(milliseconds: (pos * 1000).round()),
      );
    } catch (e) {
      debugPrint('setAudioSource failed: $e');
      if (!forceProxy && t.contentUrl != null) {
        await _playTrackIndex(ti, inTrack: inTrack, autoplay: autoplay, forceProxy: true);
        return;
      }
      error = '无法播放：$e';
      notifyListeners();
      return;
    }
    error = null;
    _reportMediaItem();
    if (autoplay) await player.play();
    _ensureListenTimer();
    _warmAhead();
    notifyListeners();
  }

  Future<void> playAt(int ti) async {
    if (ti < 0 || ti >= tracks.length) return;
    if (isTranscode) {
      await seekAbsolute(tracks[ti].startOffset + 0.01);
    } else {
      await _playTrackIndex(ti, inTrack: 0, autoplay: true);
    }
  }

  Future<void> nextTrack({bool userInitiated = false}) async {
    if (!hasBook || tracks.isEmpty) return;
    if (isTranscode) {
      final ni = min(index + 1, tracks.length - 1);
      await seekAbsolute(tracks[ni].startOffset + 0.01);
    } else if (index < tracks.length - 1) {
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
      await _playTrackIndex(index - 1);
    } else {
      await player.seek(Duration.zero);
    }
  }

  Future<void> toggle() async {
    if (!hasBook) return;
    if (player.playing) {
      await player.pause();
      unawaited(syncNow());
    } else {
      await player.play();
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
    if (session == null) return;
    if (isTranscode) {
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
      await _playTrackIndex(index + 1);
    } else {
      await syncNow();
    }
  }

  void _onPlayerError(Object e) async {
    if (_closing) return;
    final t = track;
    debugPrint('player error: $e');
    if (!_usedFallback && _lastSourceDirect && t != null && t.contentUrl != null && !isTranscode) {
      _usedFallback = true;
      debugPrint('直连失败，回退服务端代理');
      await _playTrackIndex(index, inTrack: player.position.inMilliseconds / 1000.0, autoplay: true, forceProxy: true);
      return;
    }
    error = '播放出错：$e';
    notifyListeners();
  }

  // ---------------- 同步 ----------------

  void _startSyncLoop() {
    _syncTimer?.cancel();
    final secs = settings.syncInterval.clamp(5, 600);
    _syncTimer = Timer.periodic(Duration(seconds: secs), (_) => syncNow());
  }

  Future<void> syncNow() async {
    final s = session;
    if (s == null || _closing) return;
    final listen = _unsynced;
    final abs = _absolute;
    if (listen < 0.5 && (abs - _lastSyncedAbs).abs() < 0.5) return;
    try {
      await api.syncSession(s.id, currentTime: abs, timeListened: listen, duration: duration);
      _unsynced = 0;
      _lastSyncedAbs = abs;
    } catch (e) {
      debugPrint('sync failed: $e');
    }
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
    final s = session;
    if (s != null && closeSession) {
      try {
        await api.closeSession(s.id, sync: {
          'currentTime': _absolute,
          'timeListened': _unsynced,
          'duration': duration,
        });
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

  /// 预热某章：让服务端提前解析 302 直链（取 2 字节）；直连模式顺手预热 CDN
  Future<void> warmTrack(int ti) async {
    if (ti < 0 || ti >= tracks.length) return;
    final t = tracks[ti];
    try {
      if (settings.directMode && t.path.startsWith('http')) {
        await api.warm(t.path);
      } else if (t.contentUrl != null && t.contentUrl!.isNotEmpty) {
        await api.warm(api.fullTrackUrl(t.contentUrl!));
      } else if (item != null && t.ino.isNotEmpty) {
        await api.warm(api.fileUrlFor(item!.id, t.ino));
      }
    } catch (_) {}
  }

  void _warmAhead() {
    final it = item;
    if (it == null) return;
    final nextN = settings.autoCacheNext.clamp(0, 10);
    if (nextN == 0) return;
    for (int i = index + 1; i <= min(index + nextN, tracks.length - 1); i++) {
      final nt = tracks[i];
      if (nt.ino.isEmpty) continue;
      unawaited(warmTrack(i));
      final ext = nt.ext.isNotEmpty ? nt.ext : '.mp3';
      String url;
      if (settings.directMode && nt.path.startsWith('http')) {
        url = nt.path;
      } else if (nt.contentUrl != null && nt.contentUrl!.isNotEmpty) {
        url = api.fullTrackUrl(nt.contentUrl!);
      } else {
        url = api.fileUrlFor(it.id, nt.ino);
      }
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
