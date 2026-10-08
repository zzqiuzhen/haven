/// 章节音频磁盘缓存 / 预取管理器
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'util.dart';

class CacheTask {
  CacheTask({required this.bookId, required this.ino, required this.ext, required this.url});
  final String bookId;
  final String ino;
  final String ext;
  final String url;
  String state = 'queued'; // queued / downloading / done / failed
  double received = 0;
  double total = 0;
  String? error;
  bool retried = false;
  double get progress => total > 0 ? (received / total).clamp(0, 1) : 0;
}

class CacheManager extends ChangeNotifier {
  CacheManager(this._api);
  Api _api;
  void setApi(Api a) {
    _api = a;
  }
  Directory? _root;
  final Map<String, CacheTask> _tasks = {};
  final List<String> _queue = [];
  bool _working = false;
  final Map<String, int> _sizes = {}; // bookId -> bytes
  final Map<String, Set<String>> _cachedInos = {}; // bookId -> 已缓存章节 ino 集合
  final Set<String> _scannedBooks = {}; // 已扫描过目录的 bookId
  int maxCacheGB = 10; // 缓存总大小上限（GB，0=不限）；由 AppState 同步

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      _root = Directory(p.join(base.path, 'haven_cache'));
      await _root!.create(recursive: true);
    } catch (e) {
      debugPrint('cache init failed: $e');
    }
  }

  String _key(String b, String i) => '$b:$i';
  File _dataFile(String b, String ino, String ext) => File(p.join(_root!.path, b, '$ino$ext'));
  File _doneFile(String b, String ino) => File(p.join(_root!.path, b, '$ino.done'));

  /// 已完整缓存则返回本地路径
  String? completePath(String bookId, String ino, String ext) {
    if (kIsWeb || _root == null) return null;
    final f = _dataFile(bookId, ino, ext);
    if (f.existsSync() && _doneFile(bookId, ino).existsSync()) return f.path;
    return null;
  }

  bool isDownloaded(String bookId, String ino) => hasMark(bookId, ino);

  bool hasMark(String bookId, String ino) => !kIsWeb && _root != null && _doneFile(bookId, ino).existsSync();

  List<CacheTask> get tasks => _tasks.values.toList();
  CacheTask? taskFor(String bookId, String ino) => _tasks[_key(bookId, ino)];

  void enqueue({required String bookId, required String ino, required String ext, required String url}) {
    if (kIsWeb || _root == null) return;
    if (hasMark(bookId, ino)) return;
    final k = _key(bookId, ino);
    final t = _tasks[k];
    if (t != null && (t.state == 'downloading' || t.state == 'queued')) return;
    _tasks[k] = CacheTask(bookId: bookId, ino: ino, ext: ext, url: url);
    _queue.add(k);
    notifyListeners();
    _pump();
  }

  void enqueueNext({required String bookId, required List<({String ino, String ext, String url})> next}) {
    for (final t in next) {
      enqueue(bookId: bookId, ino: t.ino, ext: t.ext, url: t.url);
    }
  }

  Future<void> _pump() async {
    if (_working || kIsWeb || _root == null) return;
    _working = true;
    while (_queue.isNotEmpty) {
      final k = _queue.removeAt(0);
      final t = _tasks[k];
      if (t == null) continue;
      if (hasMark(t.bookId, t.ino)) {
        _tasks.remove(k);
        notifyListeners();
        continue;
      }
      t.state = 'downloading';
      notifyListeners();
      try {
        final f = _dataFile(t.bookId, t.ino, t.ext);
        await f.parent.create(recursive: true);
        final part = File('${f.path}.part');
        await _api.downloadTrack(t.url, part.path, onProgress: (r, total) {
          t.received = r.toDouble();
          if (total > 0) t.total = total.toDouble();
        });
        if (f.existsSync()) await f.delete();
        await part.rename(f.path);
        await _doneFile(t.bookId, t.ino).writeAsString(DateTime.now().toIso8601String());
        t.state = 'done';
        _sizes.remove(t.bookId);
        _cachedInos.putIfAbsent(t.bookId, () => <String>{}).add(t.ino);
        notifyListeners();
        unawaited(_enforceLimit());
      } catch (e) {
        if (!t.retried) {
          // 失败自动重试一次（3 秒后重新排队）
          t.retried = true;
          t.state = 'queued';
          _queue.add(k);
          notifyListeners();
          await Future.delayed(const Duration(seconds: 3));
        } else {
          t.state = 'failed';
          t.error = '$e';
          notifyListeners();
        }
      }
    }
    _working = false;
    notifyListeners();
  }

  /// 某本书已缓存字节数
  Future<int> bookSize(String bookId) async {
    if (_root == null) return 0;
    if (_sizes.containsKey(bookId)) return _sizes[bookId]!;
    var sum = 0;
    final dir = Directory(p.join(_root!.path, bookId));
    if (await dir.exists()) {
      await for (final f in dir.list(recursive: false)) {
        if (f is File) sum += await f.length();
      }
    }
    _sizes[bookId] = sum;
    return sum;
  }

  /// 所有缓存书籍（bookId -> {count, bytes}）
  Future<Map<String, ({int count, int bytes})>> allBooks() async {
    final out = <String, ({int count, int bytes})>{};
    if (_root == null) return out;
    if (!await _root!.exists()) return out;
    await for (final d in _root!.list()) {
      if (d is Directory) {
        final bookId = p.basename(d.path);
        var count = 0, bytes = 0;
        await for (final f in d.list()) {
          if (f is File) {
            if (f.path.endsWith('.done')) count++;
            bytes += await f.length();
          }
        }
        if (count > 0) out[bookId] = (count: count, bytes: bytes);
      }
    }
    return out;
  }

  Future<void> deleteBook(String bookId) async {
    if (_root == null) return;
    for (final k in _tasks.keys.where((k) => k.startsWith('$bookId:')).toList()) {
      _tasks.remove(k);
    }
    final dir = Directory(p.join(_root!.path, bookId));
    if (await dir.exists()) await dir.delete(recursive: true);
    _sizes.remove(bookId);
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (_root == null) return;
    _tasks.clear();
    _queue.clear();
    if (await _root!.exists()) await _root!.delete(recursive: true);
    await _root!.create(recursive: true);
    _sizes.clear();
    notifyListeners();
  }

  /// 某本书已缓存章节的 ino 集合（首次访问时扫描目录一次）
  Set<String> cachedInosFor(String bookId) {
    if (_root == null) return const {};
    if (!_scannedBooks.contains(bookId)) {
      _scannedBooks.add(bookId);
      final set = <String>{};
      try {
        final dir = Directory(p.join(_root!.path, bookId));
        if (dir.existsSync()) {
          for (final f in dir.listSync()) {
            if (f is File && f.path.endsWith('.done')) {
              set.add(p.basename(f.path).replaceAll(RegExp(r'\.done$'), ''));
            }
          }
        }
      } catch (_) {}
      _cachedInos[bookId] = set;
    }
    return _cachedInos[bookId] ?? const {};
  }

  /// 全部缓存占用字节数（不含详情缓存）
  Future<int> totalSize() async {
    if (_root == null) return 0;
    var sum = 0;
    await for (final d in _root!.list()) {
      if (d is! Directory || p.basename(d.path) == '_details') continue;
      await for (final f in d.list()) {
        if (f is File && !f.path.endsWith('.done') && !f.path.endsWith('.part')) {
          sum += await f.length();
        }
      }
    }
    return sum;
  }

  /// 超过总量上限时，按缓存时间从旧到新删除，直到回落到上限内
  Future<void> _enforceLimit() async {
    if (_root == null) return;
    final maxBytes = maxCacheGB <= 0 ? 0 : maxCacheGB * 1024 * 1024 * 1024;
    if (maxBytes <= 0) return;
    var total = await totalSize();
    if (total <= maxBytes) return;
    final entries = <({String path, int size, int mtime})>[];
    await for (final d in _root!.list()) {
      if (d is! Directory || p.basename(d.path) == '_details') continue;
      await for (final f in d.list()) {
        if (f is! File || f.path.endsWith('.done') || f.path.endsWith('.part')) continue;
        final done = File('${f.path}.done');
        if (!done.existsSync()) continue;
        final st = f.statSync();
        entries.add((path: f.path, size: st.size, mtime: st.modified.millisecondsSinceEpoch));
      }
    }
    entries.sort((a, b) => a.mtime.compareTo(b.mtime));
    for (final e in entries) {
      if (total <= maxBytes) break;
      try {
        await File(e.path).delete();
        final done = File('${e.path}.done');
        if (done.existsSync()) await done.delete();
        total -= e.size;
      } catch (_) {}
    }
    notifyListeners();
  }

  /// 书籍详情 JSON 落盘缓存（冷启动秒开用）
  String? readDetailJson(String id) {
    final f = _detailFile(id);
    if (f == null || !f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDetailJson(String id, String json) async {
    final f = _detailFile(id);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(json);
    } catch (_) {}
  }

  File? _detailFile(String id) => _root == null ? null : File(p.join(_root!.path, '_details', '$id.json'));

  String humanSize(int bytes) => fmtBytes(bytes.toDouble());
}
