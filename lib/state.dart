/// 全局应用状态：登录 / 首页数据 / 书库缓存 / 设置入口
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'cache_manager.dart';
import 'models.dart';
import 'player_engine.dart';
import 'settings.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.settings,
    required this.cache,
    required this.engine,
  }) {
    engine.owner = this;
    sharedApi = api;
  }

  Api api;
  final Settings settings;
  final CacheManager cache;
  final PlayerEngine engine;

  AbsUser? me;
  ServerStatus? serverInfo;
  List<Library> libraries = [];
  List<(LibItem, MediaProgress)> continueList = [];
  ListeningStats stats = ListeningStats();
  final Map<String, LibItem> itemCache = {};
  final Map<String, BookDetail> detailCache = {};
  final Map<String, List<LibItem>> libItems = {};
  final Map<String, int> libTotals = {};

  bool booted = false;
  bool loadingHome = false;
  String? homeError;
  String debugInfo = '';
  int tab = 0;

  bool get loggedIn => me != null;

  MediaProgress? progressOf(String libraryItemId) {
    for (final p in me?.mediaProgress ?? const <MediaProgress>[]) {
      if (p.libraryItemId == libraryItemId) return p;
    }
    return null;
  }

  Future<void> boot() async {
    // 开发调试注入（--dart-define=HAVEN_DEV_TOKEN / HAVEN_DEV_SERVER，正式包不含）
    const devToken = String.fromEnvironment('HAVEN_DEV_TOKEN');
    const devServer = String.fromEnvironment('HAVEN_DEV_SERVER');
    if (devToken.isNotEmpty) {
      if (devServer.isNotEmpty && api.baseUrl != devServer) {
        api = Api(devServer);
        engine.api = api;
        cache.setApi(api);
        sharedApi = api;
      }
      api.token = devToken;
      try {
        me = await api.me();
        serverInfo = await api.status();
        booted = true;
        notifyListeners();
        unawaited(refreshHome());
      } catch (e) {
        debugPrint('dev boot failed: $e');
        booted = true;
        notifyListeners();
      }
      return;
    }
    try {
      if (settings.token != null && settings.serverUrl != null) {
        api.token = settings.token;
        me = await api.me();
        serverInfo = await api.status();
      }
    } catch (e) {
      debugPrint('boot failed: $e');
      if (e is ApiException && e.statusCode == 401) {
        await settings.logout();
      }
    }
    booted = true;
    notifyListeners();
    if (loggedIn) unawaited(refreshHome());
  }

  Future<bool> login(String server, String username, String password) async {
    if (api.baseUrl != server) {
      api = Api(server);
      engine.api = api;
      cache.setApi(api);
      sharedApi = api;
    }
    final u = await api.login(username, password);
    me = u;
    final tok = u.token ?? api.token ?? '';
    api.token = tok;
    await settings.saveLogin(server, tok, username);
    notifyListeners();
    unawaited(refreshHome());
    return true;
  }

  Future<void> logout() async {
    try {
      await engine.stopAndClose();
    } catch (_) {}
    await settings.logout();
    me = null;
    continueList = [];
    libraries = [];
    itemCache.clear();
    detailCache.clear();
    libItems.clear();
    libTotals.clear();
    stats = ListeningStats();
    notifyListeners();
  }

  Future<void> refreshHome() async {
    loadingHome = true;
    notifyListeners();
    try {
      libraries = await api.libraries();
      unawaited(api.listeningStats().then((s) {
        stats = s;
        notifyListeners();
      }).catchError((_) {}));
      final m = await api.me();
      me = m;
      if (libraries.isNotEmpty) {
        try {
          final loaded = await loadLibrary(libraries.first.id, page: 0, refresh: true);
          debugInfo = 'L=${libraries.length} I=${loaded.length}';
        } catch (e) {
          debugInfo = 'L=${libraries.length} E=$e';
        }
      } else {
        debugInfo = 'L=0';
      }
      final ps = m.mediaProgress.where((p) => !p.hideFromContinue && !p.isFinished).toList();
      ps.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
      final top = ps.take(12).toList();
      final results = await Future.wait(top.map((pg) async {
        final id = pg.libraryItemId;
        if (id == null || id.isEmpty) return null;
        try {
          final it = await ensureItem(id).timeout(const Duration(seconds: 8));
          return (it, pg);
        } catch (_) {
          return null;
        }
      }));
      continueList = [for (final r in results) if (r != null) r];
      homeError = null;
    } catch (e) {
      homeError = '$e';
    }
    loadingHome = false;
    notifyListeners();
  }

  Future<BookDetail> detail(String id) async {
    final c = detailCache[id];
    if (c != null) return c;
    final d = await api.itemDetail(id);
    detailCache[id] = d;
    return d;
  }

  Future<LibItem> ensureItem(String id) async {
    final c = itemCache[id];
    if (c != null) return c;
    final d = await detail(id);
    final li = LibItem(
      id: d.id,
      ino: '',
      libraryId: d.libraryId,
      mediaType: 'book',
      addedAt: 0,
      meta: d.meta,
      duration: d.duration,
      numTracks: d.tracks.length,
      size: d.size,
      isMissing: false,
    );
    itemCache[id] = li;
    return li;
  }

  Future<List<LibItem>> loadLibrary(String libId, {int page = 0, bool refresh = false, String sort = 'addedAt', bool desc = true}) async {
    if (refresh) libItems[libId] = [];
    final cur = libItems[libId] ?? [];
    final r = await api.items(libId, page: page, sort: sort, desc: desc);
    libTotals[libId] = r.total;
    final merged = [...cur, ...r.items];
    libItems[libId] = merged;
    for (final it in r.items) {
      itemCache[it.id] = it;
    }
    notifyListeners();
    return merged;
  }

  Future<List<LibItem>> searchAll(String q) async {
    final out = <LibItem>[];
    final seen = <String>{};
    for (final l in libraries) {
      try {
        for (final it in await api.search(l.id, q)) {
          if (seen.add(it.id)) out.add(it);
        }
      } catch (_) {}
    }
    return out;
  }

  /// 阅读记录（按最近更新排序）
  Future<List<(LibItem, MediaProgress)>> recentList({int limit = 50}) async {
    final m = me;
    if (m == null) return [];
    final ps = [...m.mediaProgress];
    ps.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
    final out = <(LibItem, MediaProgress)>[];
    for (final pg in ps) {
      if (out.length >= limit) break;
      final id = pg.libraryItemId;
      if (id == null || id.isEmpty) continue;
      try {
        out.add((await ensureItem(id), pg));
      } catch (_) {}
    }
    return out;
  }

  /// 打开书前预热：对服务端发起 Range 0-1 请求，提前解析 MP 302 并缓存直链
  void prewarm(LibItem it, BookDetail d, double resumeAbs) {
    if (d.tracks.isEmpty) return;
    int ti = d.tracks.length - 1;
    for (int i = 0; i < d.tracks.length; i++) {
      if (resumeAbs < d.tracks[i].end) {
        ti = i;
        break;
      }
    }
    for (final i in [ti, ti + 1]) {
      if (i < 0 || i >= d.tracks.length) continue;
      final t = d.tracks[i];
      if (t.path.startsWith('http') && settings.directMode) {
        unawaited(api.warm(t.path));
      } else if (t.ino.isNotEmpty) {
        unawaited(api.warm(api.fileUrlFor(it.id, t.ino)));
      }
    }
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    if (mode == 'light') {
      settings.themeMode = ThemeMode.light;
    } else if (mode == 'dark') {
      settings.themeMode = ThemeMode.dark;
    } else {
      settings.themeMode = ThemeMode.system;
    }
    notifyListeners();
  }
}
