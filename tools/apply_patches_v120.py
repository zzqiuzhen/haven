#!/usr/bin/env python3
"""v1.2.0 补丁：HLS冷启动预热 / 转码书预热+跳过缓存 / 锁屏直达强化 / 首页版本号。"""
import io
import os

ROOT = r"E:\dev\haven"


def edit(path, reps):
    src = io.open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    for i, (o, n) in enumerate(reps, 1):
        o2 = o.replace('\n', nl)
        n2 = n.replace('\n', nl)
        c = src.count(o2)
        assert c == 1, f"{path} anchor#{i} count={c}:\n{o[:160]}"
        src = src.replace(o2, n2)
    io.open(path, 'w', encoding='utf-8', newline='').write(src)
    print(f"patched {os.path.basename(path)} ({len(reps)} edits)")


# ============ player_engine.dart ============
E = []
E.append(('''      if (session == null) {
        error = '转码会话创建失败，请检查网络后重试';
        notifyListeners();
        return;
      }
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(_hlsUrl()), headers: api.authHeaders),
      );''',
'''      if (session == null) {
        error = '转码会话创建失败，请检查网络后重试';
        notifyListeners();
        return;
      }
      // HLS 冷启动预热：服务端转码器需先拉起源文件（首个分片就绪前请求会 404），
      // 直接交给播放器会因分片 404 报错；这里轮询等待首个分片可用（最长约 60 秒）
      await _warmHlsStream();
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(_hlsUrl()), headers: api.authHeaders),
      );'''))
E.append(('''  String _hlsUrl() {
    final cu = session?.tracks.isNotEmpty == true ? session!.tracks.first.contentUrl : null;
    if (cu != null) return api.fullTrackUrl(cu);
    return api.fullTrackUrl('/hls/${session?.id}/output.m3u8');
  }''',
'''  String _hlsUrl() {
    final cu = session?.tracks.isNotEmpty == true ? session!.tracks.first.contentUrl : null;
    if (cu != null) return api.fullTrackUrl(cu);
    return api.fullTrackUrl('/hls/${session?.id}/output.m3u8');
  }

  /// 轮询等待转码首个分片就绪（HLS 冷启动；返回是否就绪）
  Future<bool> _warmHlsStream() async {
    final s = session;
    if (s == null) return false;
    final segUrl = api.fullTrackUrl('/hls/${s.id}/output-0.ts');
    for (int i = 0; i < 32; i++) {
      if (session?.id != s.id) return false;
      try {
        final r = await api.dio.get<List<int>>(
          segUrl,
          options: Options(
            headers: {...api.authHeaders, 'Range': 'bytes=0-1'},
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1800));
    }
    return false;
  }

  // ---------------- 转码书预热 ----------------

  PlaySession? _preSession;
  LibItem? _preItem;
  DateTime _preAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 进入书籍详情页时调用：提前创建转码会话并触发一次分片请求，起播免等冷启动
  Future<void> prewarmTranscode(LibItem it) async {
    if (session != null || player.playing || _closing) return;
    if (_preSession != null && _preItem?.id == it.id) return;
    try {
      final s = await api.startPlay(it.id, forceTranscode: true);
      _preSession = s;
      _preItem = it;
      _preAt = DateTime.now();
      final segUrl = api.fullTrackUrl('/hls/${s.id}/output-0.ts');
      unawaited(() async {
        try {
          await api.dio.get<List<int>>(
            segUrl,
            options: Options(
              headers: {...api.authHeaders, 'Range': 'bytes=0-1'},
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
        } catch (_) {}
      }());
    } catch (_) {}
  }'''))
E.append(('''      if (needTranscode) {
        // 转码书必须先建会话拿 HLS 地址
        session = await api.startPlay(it.id, forceTranscode: true);
        await _startAt(start, autoplay: autoplay);
        _startSyncLoop();
      } else {''',
'''      if (needTranscode) {
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
      } else {'''))
E.append(('''      final nt = tracks[i];
      if (nt.ino.isEmpty) continue;
      unawaited(warmTrack(i));
      // WMA/转码书：缓存下载的是服务端代理的音频流（mp3/aac），不是 .strm 文本
      final needsTrans = codecNeedsTranscode(nt.codec, nt.mimeType);
      final ext = needsTrans ? '.mp3' : (nt.ext.isNotEmpty ? nt.ext : '.mp3');
      String url;
      if (needsTrans && session != null) {
        // 转码书缓存：用 HLS 分片（服务端已转码为 aac/mp4）
        url = api.fullTrackUrl('/hls/${session!.id}/output.m3u8');
      } else if (settings.directMode && nt.path.startsWith('http')) {
        url = nt.path;
      } else if (nt.contentUrl != null && nt.contentUrl!.isNotEmpty) {
        url = api.fullTrackUrl(nt.contentUrl!);
      } else {
        url = api.fileUrlFor(it.id, nt.ino);
      }
      cache.enqueue(bookId: it.id, ino: nt.ino, ext: ext, url: url);''',
'''      final nt = tracks[i];
      if (nt.ino.isEmpty) continue;
      // 转码书籍（WMA 等）不支持轨道级离线缓存（服务端按需转码，无整文件可下）
      if (codecNeedsTranscode(nt.codec, nt.mimeType)) continue;
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
      cache.enqueue(bookId: it.id, ino: nt.ino, ext: ext, url: url);'''))
E.append(('''    final ext = t.ext.isNotEmpty ? t.ext : '.mp3';
    // WMA/转码书：缓存下载的是服务端代理的音频流（mp3/aac），不是 .strm 文本
    final cacheExt = codecNeedsTranscode(t.codec, t.mimeType) ? '.mp3' : ext;
    final local = cache.completePath(item!.id, t.ino, cacheExt);''',
'''    final ext = t.ext.isNotEmpty ? t.ext : '.mp3';
    final local = cache.completePath(item!.id, t.ino, ext);'''))
edit(os.path.join(ROOT, 'lib', 'player_engine.dart'), E)

# ============ book_page.dart ============
B = []
B.append(("import '../cache_manager.dart';",
'''import '../cache_manager.dart';
import '../consts.dart';'''))
B.append(('''      if (!_didPrewarm) {
        _didPrewarm = true;
        app.prewarm(widget.item, d, abs);
      }''',
'''      if (!_didPrewarm) {
        _didPrewarm = true;
        app.prewarm(widget.item, d, abs);
        // 转码书（WMA 等）：进入详情页即预热转码会话，起播免等冷启动
        if (d.tracks.any((t) => codecNeedsTranscode(t.codec, t.mimeType))) {
          unawaited(context.read<PlayerEngine>().prewarmTranscode(widget.item));
        }
      }'''))
B.append(('''    var n = 0;
    for (final i in idx) {
      if (i < 0 || i >= d.tracks.length) continue;
      final t = d.tracks[i];
      if (t.ino.isEmpty) continue;
      final url = (t.path.startsWith('http') && app.settings.directMode)
          ? t.path
          : app.api.fileUrlFor(widget.item.id, t.ino);
      cache.enqueue(bookId: widget.item.id, ino: t.ino, ext: t.ext.isNotEmpty ? t.ext : '.mp3', url: url);
      n++;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已加入缓存队列（$n 章）')));''',
'''    var n = 0, skipped = 0;
    for (final i in idx) {
      if (i < 0 || i >= d.tracks.length) continue;
      final t = d.tracks[i];
      if (t.ino.isEmpty) continue;
      if (codecNeedsTranscode(t.codec, t.mimeType)) { skipped++; continue; }
      final url = (t.path.startsWith('http') && app.settings.directMode)
          ? t.path
          : app.api.fileUrlFor(widget.item.id, t.ino);
      cache.enqueue(bookId: widget.item.id, ino: t.ino, ext: t.ext.isNotEmpty ? t.ext : '.mp3', url: url);
      n++;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(skipped > 0 ? '已加入缓存队列（$n 章）· $skipped 章为转码书暂不支持' : '已加入缓存队列（$n 章）')));'''))
edit(os.path.join(ROOT, 'lib', 'pages', 'book_page.dart'), B)

# ============ home_page.dart ============
H = []
H.append(("import '../models.dart';",
'''import '../consts.dart';
import '../models.dart';'''))
H.append(('''              const Text('发现', style: TS.h1),
              const SizedBox(height: 4),
              Text(todayLabel(), style: TS.sub),''',
'''              const Text('发现', style: TS.h1),
              const SizedBox(height: 4),
              Text('${todayLabel()} · v$kAppVersion', style: TS.sub),'''))
edit(os.path.join(ROOT, 'lib', 'pages', 'home_page.dart'), H)

# ============ main.dart ============
M = []
M.append(('''    } else if (state == AppLifecycleState.resumed) {
      final since = _hiddenAt;
      _hiddenAt = null;
      final awaySec = since == null ? 0 : DateTime.now().difference(since).inSeconds;
      // 从锁屏/后台回来且有正在播放的书、且不在播放页 → 直达播放器
      // （锁屏点“正在播放”卡片会唤起 App，awaySec 可能很短；带重试以适配导航就绪时机）
      // 只在真正播放中才直达，避免手动切回时弹播放页
      if (widget.app.engine.hasBook && widget.app.loggedIn && !playerPageOpen && widget.app.engine.playing) {
        _openPlayerSoon();
      }
    }
  }

  /// 回到前台后直达播放页（重试 2 次：引擎/导航就绪时间不确定）
  void _openPlayerSoon({int attempt = 0}) {
    Future.delayed(Duration(milliseconds: 450 + attempt * 700), () {
      if (!mounted || playerPageOpen) return;
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 2) _openPlayerSoon(attempt: attempt + 1);
        return;
      }
      nav.push(PlayerPage.route());
    });
  }''',
'''    } else if (state == AppLifecycleState.resumed) {
      final since = _hiddenAt;
      _hiddenAt = null;
      final awaySec = since == null ? 0 : DateTime.now().difference(since).inSeconds;
      // 从锁屏/后台回来且有正在播放的书 → 直达播放页
      // （锁屏“正在播放”卡片点开会唤起 App；awaySec 可能很短，播放中即触发；带多次重试）
      if (widget.app.engine.hasBook &&
          widget.app.loggedIn &&
          !playerPageOpen &&
          (widget.app.engine.playing || awaySec >= 2)) {
        _openPlayerSoon();
      }
    }
  }

  DateTime _lastOpenPushAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 回到前台后直达播放页（多次重试：引擎/导航就绪时间不确定）
  void _openPlayerSoon({int attempt = 0}) {
    if (attempt == 0) {
      final now = DateTime.now();
      if (now.difference(_lastOpenPushAt).inSeconds < 3) return; // 防抖
      _lastOpenPushAt = now;
    }
    Future.delayed(Duration(milliseconds: attempt == 0 ? 400 : 700), () {
      if (!mounted || playerPageOpen) return;
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 4) _openPlayerSoon(attempt: attempt + 1);
        return;
      }
      nav.push(PlayerPage.route());
    });
  }'''))
edit(os.path.join(ROOT, 'lib', 'main.dart'), M)

# ============ 版本号 ============
edit(os.path.join(ROOT, 'pubspec.yaml'), [("version: 1.1.2+13", "version: 1.2.0+14")])
edit(os.path.join(ROOT, 'lib', 'consts.dart'), [("const kAppVersion = '1.1.2';", "const kAppVersion = '1.2.0';")])

print('ALL V120 DART PATCHES APPLIED')
