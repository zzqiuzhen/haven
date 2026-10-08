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
  /// 默认关：直连需要手机能访问 MoviePilot，真机在外网/蜂窝下往往不可达，走服务端代理最稳且同样快
  bool get directMode => _sp.getBool('direct_mode') ?? false;
  set directMode(bool v) => _sp.setBool('direct_mode', v);

  // ---- 外观 ----
  ThemeMode get themeMode {
    final v = _sp.getString('theme_mode') ?? 'system';
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
}
