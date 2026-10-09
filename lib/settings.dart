/// 本地设置存取
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consts.dart';

class Settings {
  Settings(this._sp);
  final SharedPreferences _sp;

  // ---- 账户/服务器 ----
  String? get serverUrl => _sp.getString('server_url');
  String? get token => _sp.getString('token');
  String? get username => _sp.getString('username');
  Future<void> saveLogin(String server, String token, String username) async {
    await _sp.setString('server_url', server);
    await _sp.setString('token', token);
    await _sp.setString('username', username);
  }

  Future<void> logout() async {
    await _sp.remove('token');
  }

  // ---- 播放 ----
  double get speed => _sp.getDouble('speed') ?? PlayDefaults.speed;
  set speed(double v) => _sp.setDouble('speed', v);

  int get rewindStep => _sp.getInt('rewind_step') ?? PlayDefaults.rewindStep;
  set rewindStep(int v) => _sp.setInt('rewind_step', v);

  int get forwardStep => _sp.getInt('forward_step') ?? PlayDefaults.forwardStep;
  set forwardStep(int v) => _sp.setInt('forward_step', v);

  int get syncInterval => _sp.getInt('sync_interval') ?? PlayDefaults.syncInterval;
  set syncInterval(int v) => _sp.setInt('sync_interval', v);

  int get autoCacheNext => _sp.getInt('auto_cache_next') ?? PlayDefaults.autoCacheNext;
  set autoCacheNext(int v) => _sp.setInt('auto_cache_next', v);

  /// 自动缓存整本（当前章之后的全部章节）
  bool get autoCacheWholeBook => _sp.getBool('auto_cache_whole') ?? false;
  set autoCacheWholeBook(bool v) => _sp.setBool('auto_cache_whole', v);

  /// 缓存总大小上限（GB；0=不限）。超过后自动删除最早缓存的内容
  int get maxCacheGB => _sp.getInt('max_cache_gb') ?? PlayDefaults.maxCacheGB;
  set maxCacheGB(int v) => _sp.setInt('max_cache_gb', v);

  int get skipIntro => _sp.getInt('skip_intro') ?? PlayDefaults.skipIntro;
  set skipIntro(int v) => _sp.setInt('skip_intro', v);

  int get skipOutro => _sp.getInt('skip_outro') ?? PlayDefaults.skipOutro;
  set skipOutro(int v) => _sp.setInt('skip_outro', v);

  bool get pauseOnHeadsetDisconnect => _sp.getBool('pause_headset') ?? true;
  set pauseOnHeadsetDisconnect(bool v) => _sp.setBool('pause_headset', v);

  /// 锁屏控件模式：chapters=上一章/下一章，seek=快进/快退
  String get lockButtons => _sp.getString('lock_buttons') ?? 'chapters';
  set lockButtons(String v) => _sp.setString('lock_buttons', v);

  /// 极速直连（直接跟 MP 302 到 115 CDN，失败自动回退服务端代理）
  /// 默认开：起播优先走 strm302 最快；不可达/打不开会自动切服务端并在本次运行内记住
  bool get directMode => _sp.getBool('direct_mode') ?? true;
  set directMode(bool v) => _sp.setBool('direct_mode', v);

  // ---- 外观 ----
  ThemeMode get themeMode {
    final v = _sp.getString('theme_mode') ?? 'light';
    return v == 'light' ? ThemeMode.light : (v == 'dark' ? ThemeMode.dark : ThemeMode.system);
  }

  set themeMode(ThemeMode m) => _sp.setString('theme_mode', m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system'));

  // ---- 单本书记忆（倍速/跳过） ----
  Map<String, dynamic> get _bookPrefs {
    try {
      return (jsonDecode(_sp.getString('book_prefs') ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  double speedFor(String bookId) {
    final b = _bookPrefs[bookId];
    if (b is Map && b['speed'] is num) return (b['speed'] as num).toDouble();
    return speed;
  }

  Future<void> setSpeedFor(String bookId, double v) async {
    final m = _bookPrefs;
    final b = (m[bookId] is Map) ? Map<String, dynamic>.from(m[bookId] as Map) : <String, dynamic>{};
    b['speed'] = v;
    m[bookId] = b;
    await _sp.setString('book_prefs', jsonEncode(m));
  }

  // ---- 本机最后播放位置（本地续播优先，杜绝服务端进度滞后导致回跳）----
  /// 返回 (libraryItemId, 绝对秒数, 保存时间戳ms)；无则 null
  (String, double, int)? get lastPos {
    try {
      final raw = _sp.getString('last_pos');
      if (raw == null || raw.isEmpty) return null;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final id = m['id']?.toString() ?? '';
      final abs = (m['abs'] is num) ? (m['abs'] as num).toDouble() : 0.0;
      final ts = (m['ts'] is num) ? (m['ts'] as num).toInt() : 0;
      if (id.isEmpty || abs <= 0) return null;
      return (id, abs, ts);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastPos(String bookId, double abs) async {
    if (bookId.isEmpty || abs <= 0) return;
    await _sp.setString(
      'last_pos',
      jsonEncode({'id': bookId, 'abs': abs, 'ts': DateTime.now().millisecondsSinceEpoch}),
    );
  }

  /// 清除本机最后播放记录（条目已失效/被删除时自愈用）
  Future<void> clearLastPos() async {
    await _sp.remove('last_pos');
  }

  // ---- 发现页模块（显隐与排序）----
  static const List<String> homeModuleIds = ['continue', 'stats', 'new', 'cats', 'libs'];

  List<(String, bool)> get homeModules {
    try {
      final raw = _sp.getString('home_modules');
      if (raw != null && raw.isNotEmpty) {
        final l = jsonDecode(raw) as List;
        final out = <(String, bool)>[];
        for (final e in l) {
          if (e is Map) {
            final id = e['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            out.add((id, e['on'] != false));
          }
        }
        // 升级场景：补齐后新增的模块（追加到末尾，默认显示）
        for (final id in homeModuleIds) {
          if (!out.any((m) => m.$1 == id)) out.add((id, true));
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return [for (final id in homeModuleIds) (id, true)];
  }

  Future<void> setHomeModules(List<(String, bool)> v) async {
    await _sp.setString('home_modules', jsonEncode([for (final m in v) {'id': m.$1, 'on': m.$2}]));
  }

  // ---- 自定义分类（分类名 -> 书籍 id 列表）----
  Map<String, List<String>> get bookCategories {
    try {
      final raw = _sp.getString('book_categories');
      if (raw == null || raw.isEmpty) return const {};
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final out = <String, List<String>>{};
      m.forEach((k, v) {
        if (v is List) out[k] = v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _setCategories(Map<String, List<String>> c) => _sp.setString('book_categories', jsonEncode(c));

  Future<void> addCategory(String name) async {
    final c = Map<String, List<String>>.from(bookCategories);
    c.putIfAbsent(name, () => <String>[]);
    await _setCategories(c);
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final c = Map<String, List<String>>.from(bookCategories);
    final books = c.remove(oldName) ?? <String>[];
    c[newName] = books;
    await _setCategories(c);
  }

  Future<void> removeCategory(String name) async {
    final c = Map<String, List<String>>.from(bookCategories);
    c.remove(name);
    await _setCategories(c);
  }

  Future<void> toggleBookCategory(String catName, String bookId) async {
    final c = Map<String, List<String>>.from(bookCategories);
    final list = c.putIfAbsent(catName, () => <String>[]);
    if (list.contains(bookId)) {
      list.remove(bookId);
    } else {
      list.add(bookId);
    }
    if (list.isEmpty) c.remove(catName);
    await _setCategories(c);
  }

  // ---- 书签本地索引（书库页全局书签用）----
  List<Map<String, dynamic>> get bookmarkIndex {
    try {
      final raw = _sp.getString('bookmark_index');
      if (raw == null || raw.isEmpty) return [];
      return [for (final e in (jsonDecode(raw) as List)) if (e is Map) e.cast<String, dynamic>()];
    } catch (_) {
      return [];
    }
  }

  Future<void> setBookmarkIndex(List<Map<String, dynamic>> v) async {
    await _sp.setString('bookmark_index', jsonEncode(v));
  }

  bool get bookmarksSeeded => _sp.getBool('bookmark_seeded_v1') ?? false;
  Future<void> setBookmarksSeeded(bool v) async => _sp.setBool('bookmark_seeded_v1', v);

  Future<void> recordBookmark({
    required String itemId,
    required String bookTitle,
    required String author,
    required double time,
    required String title,
  }) async {
    final list = bookmarkIndex;
    list.removeWhere((e) {
      final t = (e['time'] as num?)?.toDouble() ?? -9e9;
      return e['itemId'] == itemId && (t - time).abs() < 1.0;
    });
    list.add({
      'itemId': itemId,
      'bookTitle': bookTitle,
      'author': author,
      'time': time,
      'title': title,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    await setBookmarkIndex(list);
  }

  Future<void> unrecordBookmark(String itemId, double time) async {
    final list = bookmarkIndex;
    list.removeWhere((e) {
      final t = (e['time'] as num?)?.toDouble() ?? -9e9;
      return e['itemId'] == itemId && (t - time).abs() < 1.0;
    });
    await setBookmarkIndex(list);
  }

  /// 用服务端扫描结果同步（替换已扫描书籍的书签；未扫描的保留）
  Future<void> syncBookmarksFromServer(Set<String> scannedIds, List<Map<String, dynamic>> found) async {
    final list = bookmarkIndex.where((e) => !scannedIds.contains(e['itemId']?.toString() ?? '')).toList();
    list.addAll(found);
    await setBookmarkIndex(list);
  }

  // ---- 任务栏（底部导航）----
  bool get navShowDiscover => _sp.getBool('nav_show_discover') ?? true;
  bool get navShowLibrary => _sp.getBool('nav_show_library') ?? true;
  bool get navIconsOnly => _sp.getBool('nav_icons_only') ?? false;

  Future<void> setNavPrefs({bool? discover, bool? library, bool? iconsOnly}) async {
    if (discover != null) await _sp.setBool('nav_show_discover', discover);
    if (library != null) await _sp.setBool('nav_show_library', library);
    if (iconsOnly != null) await _sp.setBool('nav_icons_only', iconsOnly);
  }

  // ---- 搜索历史 ----
  List<String> get recentSearches => _sp.getStringList('recent_searches') ?? const [];
  Future<void> addRecentSearch(String q) async {
    final list = _sp.getStringList('recent_searches') ?? <String>[];
    list.remove(q);
    list.insert(0, q);
    if (list.length > 10) list.removeRange(10, list.length);
    await _sp.setStringList('recent_searches', list);
  }
  Future<void> clearRecentSearches() => _sp.setStringList('recent_searches', <String>[]);

  // ---- 本地元数据覆盖（书名/作者手改，锁屏与界面生效）----
  Map<String, Map<String, String>> get metaOverrides {
    try {
      final raw = _sp.getString('meta_overrides');
      if (raw == null || raw.isEmpty) return const {};
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final out = <String, Map<String, String>>{};
      m.forEach((k, v) {
        if (v is Map) out[k] = v.map((kk, vv) => MapEntry(kk.toString(), vv.toString()));
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  String? overrideTitle(String bookId) => metaOverrides[bookId]?['title'];
  String? overrideAuthor(String bookId) => metaOverrides[bookId]?['author'];

  Future<void> setMetaOverride(String bookId, {String? title, String? author}) async {
    final m = Map<String, Map<String, String>>.from(metaOverrides);
    final entry = Map<String, String>.from(m[bookId] ?? const {});
    if (title != null && title.isNotEmpty) entry['title'] = title;
    if (author != null && author.isNotEmpty) entry['author'] = author;
    if (entry.isEmpty) {
      m.remove(bookId);
    } else {
      m[bookId] = entry;
    }
    await _sp.setString('meta_overrides', jsonEncode(m));
  }

  Future<void> clearMetaOverride(String bookId) async {
    final m = Map<String, Map<String, String>>.from(metaOverrides);
    m.remove(bookId);
    await _sp.setString('meta_overrides', jsonEncode(m));
  }

  // ---- 后台状态持久化（锁屏/进程被杀后回前台判定直达用）----
  int? get bgAtMs {
    final v = _sp.getInt('bg_at_ms');
    return (v == null || v <= 0) ? null : v;
  }

  bool get bgPlaying => _sp.getBool('bg_playing') ?? false;

  Future<void> saveBgState(int ms, bool playing) async {
    await _sp.setInt('bg_at_ms', ms);
    await _sp.setBool('bg_playing', playing);
  }
}
