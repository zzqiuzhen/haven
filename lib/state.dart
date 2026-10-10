/// 全局应用状态：登录 / 首页数据 / 书库缓存 / 设置入口
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'cache_manager.dart';
import 'consts.dart';
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
    cache.maxCacheGB = settings.maxCacheGB;
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
  /// 首页“我的书库”点击后待打开的书库 id（书库页消费）
  String? pendingLibId;
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

  /// 该书的续播点（秒）：本机最后播放位置与服务端进度取新者；时间接近时取较大值防回跳
  double resumeAbsFor(String libraryItemId) {
    final pg = progressOf(libraryItemId);
    final srv = pg?.currentTime ?? 0;
    final srvTs = pg?.updatedAt?.millisecondsSinceEpoch ?? 0;
    final lp = settings.lastPos;
    if (lp != null && lp.$1 == libraryItemId) {
      final gap = (lp.$3 - srvTs).abs();
      if (srvTs == 0 || gap < 120000) return lp.$2 > srv ? lp.$2 : srv;
      return lp.$3 > srvTs ? lp.$2 : srv;
    }
    return srv;
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
        await maybeSwitchLan(); // 内网可达优先
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

  Future<bool> login(String server, String username, String password, {String? lanServer}) async {
    await settings.setLanServerUrl(lanServer);
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
    unawaited(maybeSwitchLan());
    return true;
  }


  DateTime? _lanProbeAt;
  bool _lanLastOk = false;

  Future<bool> _lanReachable(String lan) async {
    try {
      final p = Api(lan);
      return await p.reachable('$lan/healthcheck', timeout: const Duration(milliseconds: 1500));
    } catch (_) {
      return false;
    }
  }

  /// 内网可达则切到内网地址，否则用主地址（飞牛式自动切换；结果缓存 30 秒）
  Future<void> maybeSwitchLan() async {
    if (settings.token == null) return; // 未登录不折腾
    final lan = settings.lanServerUrl;
    final ext = settings.serverUrl;
    if (lan == null || lan.isEmpty || ext == null) return;
    final now = DateTime.now();
    if (_lanProbeAt == null || now.difference(_lanProbeAt!) > const Duration(seconds: 30)) {
      _lanLastOk = await _lanReachable(lan);
      _lanProbeAt = now;
    }
    final target = _lanLastOk ? lan : ext;
    if (target == api.baseUrl) return;
    final tok = api.token;
    api = Api(target);
    api.token = tok;
    engine.api = api;
    cache.setApi(api);
    sharedApi = api;
    notifyListeners();
  }

  Future<void> logout() async {
    // 先立即切到登录页（UI 即时生效），清理动作放后台，避免慢网络下“点了没反应”
    me = null;
    continueList = [];
    libraries = [];
    itemCache.clear();
    detailCache.clear();
    libItems.clear();
    libTotals.clear();
    stats = ListeningStats();
    notifyListeners();
    try {
      await settings.logout();
    } catch (_) {}
    try {
      await engine.stopAndClose().timeout(const Duration(seconds: 6));
    } catch (_) {}
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
      // 冷启动自动恢复上次播放（优先本机位置；不自动播放，仅加载到引擎 → 迷你播放器立即出现）
      unawaited(engine.restoreLast());
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
    // 磁盘缓存优先（冷启动/离线秒开），后台再刷新
    final diskRaw = cache.readDetailJson(id);
    if (diskRaw != null) {
      try {
        final d = BookDetail.fromJson(jsonDecode(diskRaw) as Map<String, dynamic>);
        detailCache[id] = d;
        unawaited(_refreshDetail(id));
        return d;
      } catch (_) {}
    }
    final raw = await api.itemDetailRaw(id);
    final d = BookDetail.fromJson(raw);
    detailCache[id] = d;
    unawaited(cache.writeDetailJson(id, jsonEncode(raw)));
    return d;
  }

  Future<void> _refreshDetail(String id) async {
    try {
      final raw = await api.itemDetailRaw(id);
      final d = BookDetail.fromJson(raw);
      detailCache[id] = d;
      await cache.writeDetailJson(id, jsonEncode(raw));
      notifyListeners();
    } catch (_) {}
  }

  /// 播放设置里的缓存上限变更后调用，同步给 CacheManager
  void applyCacheLimit() {
    cache.maxCacheGB = settings.maxCacheGB;
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
      if (t.ino.isEmpty) continue;
      if (codecNeedsTranscode(t.codec, t.mimeType)) continue; // 转码书（WMA 等）无整文件可预热
      // 预热统一走服务端：触发服务端解析 302 并缓存直链（起播时服务端已就绪）
      unawaited(api.warm(api.fileUrlFor(it.id, t.ino)));
    }
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// 直接打开书库页并选中指定书库（供首页“我的书库”入口使用）
  void openLibrary(String libraryId) {
    pendingLibId = libraryId;
    setTab(1);
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

  // ---- 发现页模块（显隐与排序）----
  List<(String, bool)> get homeModules => settings.homeModules;

  Future<void> updateHomeModules(List<(String, bool)> v) async {
    await settings.setHomeModules(v);
    notifyListeners();
  }

  // ---- 书签（服务端 + 本地索引同步维护）----
  Future<void> addBookmarkAt(LibItem? item, double abs, String title) async {
    if (item == null || abs <= 0) return;
    await api.addBookmark(item.id, abs, title);
    await settings.recordBookmark(
      itemId: item.id,
      bookTitle: item.meta.title,
      author: item.meta.authorText,
      time: abs,
      title: title,
    );
  }

  Future<void> removeBookmarkAt(LibItem? item, double time) async {
    if (item == null) return;
    await api.removeBookmark(item.id, time);
    await settings.unrecordBookmark(item.id, time);
  }

  // ---- 任务栏（底部导航）----
  bool get navShowDiscover => settings.navShowDiscover;
  bool get navShowLibrary => settings.navShowLibrary;
  bool get navIconsOnly => settings.navIconsOnly;

  Future<void> setNavPrefs({bool? discover, bool? library, bool? iconsOnly}) async {
    await settings.setNavPrefs(discover: discover, library: library, iconsOnly: iconsOnly);
    // 若当前所在 tab 被隐藏 → 自动切到第一个可见的
    final visible = <int>[
      if (settings.navShowDiscover) 0,
      if (settings.navShowLibrary) 1,
      2,
    ];
    if (!visible.contains(tab)) tab = visible.first;
    notifyListeners();
  }

  // ---- 搜索历史 ----
  List<String> get recentSearches => settings.recentSearches;

  Future<void> addRecentSearch(String q) async {
    await settings.addRecentSearch(q);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    await settings.clearRecentSearches();
    notifyListeners();
  }

  // ---- 自定义分类 ----
  Map<String, List<String>> get bookCategories => settings.bookCategories;

  Future<void> addCategory(String name) async {
    await settings.addCategory(name);
    notifyListeners();
  }

  Future<void> renameCategory(String o, String n) async {
    await settings.renameCategory(o, n);
    notifyListeners();
  }

  Future<void> removeCategory(String name) async {
    await settings.removeCategory(name);
    notifyListeners();
  }

  Future<void> toggleBookCategory(String cat, String bookId) async {
    await settings.toggleBookCategory(cat, bookId);
    notifyListeners();
  }

  /// 在所有已加载书库中按 id 找书
  LibItem? itemById(String id) {
    for (final l in libItems.values) {
      for (final it in l) {
        if (it.id == id) return it;
      }
    }
    return null;
  }

  // ---- 本地元数据覆盖 ----
  String effTitle(LibItem item) => settings.overrideTitle(item.id) ?? item.meta.title;
  String effAuthor(LibItem item) => settings.overrideAuthor(item.id) ?? item.meta.authorText;

  Future<void> setMetaOverride(String bookId, {String? title, String? author}) async {
    await settings.setMetaOverride(bookId, title: title, author: author);
    notifyListeners();
  }

  Future<void> clearMetaOverride(String bookId) async {
    await settings.clearMetaOverride(bookId);
    notifyListeners();
  }
}
