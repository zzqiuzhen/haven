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
  int retries = 0;
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
  final Map<String, int> _okFiles = {}; // 已通过内容校验的文件（path -> 校验时尺寸）
  final Map<String, String> _sniffedExt = {}; // path -> 内容魔数推断的扩展名

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

  /// 已完整缓存则返回本地路径；[validate] 为 true 时校验文件内容
  /// （损坏/截断自动清除并回退网络；旧版奇怪扩展名自动纠正为音频扩展名）
  String? completePath(String bookId, String ino, String ext, {bool validate = false}) {
    if (kIsWeb || _root == null) return null;
    final f = _dataFile(bookId, ino, ext);
    if (!f.existsSync() || !_doneFile(bookId, ino).existsSync()) return null;
    if (!validate) return f.path;
    int len;
    try {
      len = f.lengthSync();
    } catch (_) {
      return null;
    }
    if (len < 4096) {
      debugPrint('缓存文件过小，清除重下: ${f.path}');
      removeCacheFile(f.path);
      return null;
    }
    if (!_validateFileContent(f, len)) {
      debugPrint('缓存文件内容校验失败（疑似截断/损坏），清除重下: ${f.path}');
      removeCacheFile(f.path);
      return null;
    }
    // 旧扩展名（如 .strm）→ 按内容魔数改名为音频扩展名（AVPlayer 可靠识别）
    if (!_mediaExts.contains(ext)) {
      final sniff = _sniffedExt[f.path];
      if (sniff != null) {
        final np = _renameCache(f, sniff);
        if (np != null) return np;
      }
    }
    return f.path;
  }

  // ---------------- 内容校验 ----------------

  /// 读取文件头，返回内容对应的音频扩展名（不认识则 null）
  static String? _sniffExt(List<int> h) {
    if (h.length >= 8 && h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70) return '.m4a'; // ftyp
    if (h.length >= 3 && h[0] == 0x49 && h[1] == 0x44 && h[2] == 0x33) return '.mp3'; // ID3
    if (h.length >= 2 && h[0] == 0xFF && (h[1] & 0xE0) == 0xE0) return '.mp3'; // MPEG 帧同步
    if (h.length >= 4 && h[0] == 0x4F && h[1] == 0x67 && h[2] == 0x67 && h[3] == 0x53) return '.ogg'; // OggS
    if (h.length >= 4 && h[0] == 0x66 && h[1] == 0x4C && h[2] == 0x61 && h[3] == 0x43) return '.flac'; // fLaC
    if (h.length >= 4 && h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46) return '.wav'; // RIFF
    if (h.length >= 4 && h[0] == 0x63 && h[1] == 0x61 && h[2] == 0x66 && h[3] == 0x66) return '.caf'; // caff
    return null;
  }

  static int _be32(List<int> b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// MP4/m4a 完整性校验：按 box 声明尺寸走链，检查 moov 是否存在、box 是否越界（截断必拒）
  static bool _mp4LooksComplete(RandomAccessFile raf, int fileLen) {
    try {
      var off = 0;
      var sawMoov = false;
      var guard = 0;
      while (off + 8 <= fileLen && guard++ < 16384) {
        raf.setPositionSync(off);
        final hdr = raf.readSync(16);
        if (hdr.length < 8) break;
        var size = _be32(hdr, 0);
        final type = String.fromCharCodes(hdr.sublist(4, 8));
        var headerLen = 8;
        if (size == 1) {
          if (hdr.length < 16) return sawMoov;
          size = (hdr[8] << 56) |
              (hdr[9] << 48) |
              (hdr[10] << 40) |
              (hdr[11] << 32) |
              (hdr[12] << 24) |
              (hdr[13] << 16) |
              (hdr[14] << 8) |
              hdr[15];
          headerLen = 16;
        } else if (size == 0) {
          // 延伸到文件尾
          return sawMoov || type == 'moov';
        }
        if (type == 'moov') sawMoov = true;
        if (size < headerLen) return false;
        final next = off + size;
        if (next > fileLen) {
          // box 越界 = 文件截断（无法完整解析）→ 判为无效，触发续传/重下
          return false;
        }
        off = next;
      }
      return sawMoov;
    } catch (_) {
      return true; // 解析异常不误删
    }
  }

  bool _validateFileContent(File f, int len) {
    final memo = _okFiles[f.path];
    if (memo == len) return true; // 本会话已校验过且尺寸未变
    // 新版 .done 带字节数戳记：尺寸一致 + 头部魔数即可（播放路径毫秒级，不再全文件走链）
    final stamp = _doneStampedSize(f);
    if (stamp != null) {
      if (stamp != len) {
        debugPrint('缓存文件尺寸与完成标记不符（疑似截断）: ${f.path}');
        return false;
      }
      RandomAccessFile? rafS;
      try {
        rafS = f.openSync();
        final head = rafS.readSync(24);
        final sniff = _sniffExt(head);
        if (sniff == null) return false;
        _okFiles[f.path] = len;
        _sniffedExt[f.path] = sniff;
        return true;
      } catch (e) {
        debugPrint('缓存校验读取异常（不删除）: $e');
        return true;
      } finally {
        try {
          rafS?.closeSync();
        } catch (_) {}
      }
    }
    RandomAccessFile? raf;
    try {
      raf = f.openSync();
      final head = raf.readSync(24);
      if (head.length < 12) return false;
      final sniff = _sniffExt(head);
      if (sniff == null) {
        debugPrint('缓存文件头非已知音频格式: ${f.path}');
        return false;
      }
      if (sniff == '.m4a' && !_mp4LooksComplete(raf, len)) {
        debugPrint('m4a 结构不完整（疑似截断）: ${f.path}');
        return false;
      }
      _okFiles[f.path] = len;
      _sniffedExt[f.path] = sniff;
      return true;
    } catch (e) {
      debugPrint('缓存校验读取异常（不删除）: $e');
      return true;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  /// 下载完成时的强校验：头部魔数 + m4a 全量走链（截断必拒；guard 足以覆盖超长文件）
  static bool _strictContentOk(File f) {
    try {
      final len = f.lengthSync();
      if (len < 4096) return false;
      final raf = f.openSync();
      try {
        final head = raf.readSync(24);
        final sniff = _sniffExt(head);
        if (sniff == null) return false;
        if (sniff == '.m4a' && !_mp4LooksComplete(raf, len)) return false;
        return true;
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// 读取 .done 里记录的完整字节数（无戳记的旧标记返回 null）
  int? _doneStampedSize(File dataFile) {
    try {
      final base = p.basenameWithoutExtension(dataFile.path);
      final done = File(p.join(p.dirname(dataFile.path), '$base.done'));
      if (!done.existsSync()) return null;
      final txt = done.readAsStringSync();
      final nl = txt.indexOf('\n');
      if (nl < 0) return null;
      return int.tryParse(txt.substring(nl + 1).trim());
    } catch (_) {
      return null;
    }
  }

  // ---------------- 删除 / 改名 ----------------

  bool isUnderRoot(String path) {
    if (_root == null) return false;
    try {
      final rp = _root!.path;
      return path == rp || p.isWithin(rp, path);
    } catch (_) {
      return false;
    }
  }

  /// 删除某缓存数据文件（连同同 ino 的 .done/.part 与内存索引）
  void removeCacheFile(String dataPath) {
    if (_root == null) return;
    try {
      final base = p.basenameWithoutExtension(dataPath);
      final dir = p.dirname(dataPath);
      final bookId = p.basename(dir);
      for (final c in [dataPath, '$dataPath.part', p.join(dir, '$base.done')]) {
        try {
          final f = File(c);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      _okFiles.remove(dataPath);
      _sniffedExt.remove(dataPath);
      _cachedInos[bookId]?.remove(base);
      _sizes.remove(bookId);
      notifyListeners();
    } catch (e) {
      debugPrint('removeCacheFile failed: $e');
    }
  }

  /// 把缓存文件改名为按内容识别的音频扩展名（返回新路径；失败返回 null 不强制）
  String? _renameCache(File f, String newExt) {
    try {
      final base = p.basenameWithoutExtension(f.path);
      final dir = p.dirname(f.path);
      final target = File(p.join(dir, '$base$newExt'));
      if (target.path == f.path) return f.path;
      if (target.existsSync()) {
        try {
          target.deleteSync();
        } catch (_) {}
      }
      final oldLen = f.lengthSync();
      f.renameSync(target.path);
      _okFiles.remove(f.path);
      _sniffedExt.remove(f.path);
      _okFiles[target.path] = oldLen;
      _sniffedExt[target.path] = newExt;
      debugPrint('缓存扩展名纠正: ${p.basename(f.path)} -> ${p.basename(target.path)}');
      return target.path;
    } catch (e) {
      debugPrint('缓存改名失败（保留原名）: $e');
      return null;
    }
  }

  /// 缓存目录快照（诊断上报用：前 N 个文件名的简要列表）
  String dirSnippet(String bookId, {int max = 12}) {
    if (_root == null) return '';
    try {
      final dir = Directory(p.join(_root!.path, bookId));
      if (!dir.existsSync()) return 'nocache';
      final names = <String>[];
      for (final f in dir.listSync()) {
        if (f is File && names.length < max) names.add(p.basename(f.path));
      }
      names.sort();
      return names.isEmpty ? 'empty' : names.join(',');
    } catch (_) {
      return 'err';
    }
  }

  bool isDownloaded(String bookId, String ino) => hasMark(bookId, ino);

  bool hasMark(String bookId, String ino) => !kIsWeb && _root != null && _doneFile(bookId, ino).existsSync();

  List<CacheTask> get tasks => _tasks.values.toList();
  CacheTask? taskFor(String bookId, String ino) => _tasks[_key(bookId, ino)];

  /// 缓存查找的可尝试扩展名（按优先级；player_engine 共用）
  static const List<String> fallbackExts = ['.m4a', '.mp3', '.aac', '.ogg', '.opus', '.m4b', '.flac'];

  /// 旧版本可能用过的非音频扩展名（查到时按内容魔数纠正为真实扩展名）
  static const List<String> _legacyCacheExts = ['.strm'];

  /// 允许作为缓存文件名的音频扩展名
  static const List<String> _mediaExts = [
    '.m4a', '.mp3', '.m4b', '.mp4', '.aac', '.ogg', '.opus', '.flac', '.wav', '.aif', '.aiff', '.caf',
  ];

  /// 归一化出适合 iOS 播放的缓存扩展名：
  /// 优先已有扩展名（当它本身是音频格式时），否则按 mimeType/codec 推断，兜底 .m4a
  static String mediaExt({String ext = '', String mimeType = '', String codec = ''}) {
    var e = ext.toLowerCase().trim();
    if (e.isNotEmpty && !e.startsWith('.')) e = '.$e';
    if (_mediaExts.contains(e)) return e;
    final mt = mimeType.toLowerCase();
    final c = codec.toLowerCase();
    if (mt.contains('mp4') || mt.contains('aac') || mt.contains('m4a') || c.startsWith('mp4a') || c == 'aac') {
      return '.m4a';
    }
    if (mt.contains('mpeg') || mt.contains('mp3') || c == 'mp3' || c == 'mp2') return '.mp3';
    if (mt.contains('opus') || c.contains('opus')) return '.opus';
    if (mt.contains('ogg') || c.contains('vorbis')) return '.ogg';
    if (mt.contains('flac') || c == 'flac') return '.flac';
    if (mt.contains('wav') || c.contains('pcm_')) return '.wav';
    return '.m4a';
  }

  /// 查找已完成的缓存文件（任意已知扩展名；含旧扩展名自动纠正）
  String? _findComplete(String bookId, String ino, String preferExt) {
    final wantExt = mediaExt(ext: preferExt);
    for (final e in {wantExt, ...fallbackExts, ..._legacyCacheExts}) {
      final path = completePath(bookId, ino, e, validate: true);
      if (path != null) return path;
    }
    // .done 存在但数据文件全缺失 → 清理孤儿标记（否则会一直"假显示已缓存"）
    final done = _doneFile(bookId, ino);
    if (done.existsSync()) {
      try {
        done.deleteSync();
        _cachedInos[bookId]?.remove(ino);
        debugPrint('清理孤儿缓存标记: $bookId/$ino');
      } catch (_) {}
    }
    return null;
  }

  void enqueue({required String bookId, required String ino, required String ext, required String url}) {
    if (kIsWeb || _root == null) return;
    // 已完整缓存（任意扩展名，含可纠正的旧扩展名）→ 跳过
    if (_findComplete(bookId, ino, ext) != null) return;
    final k = _key(bookId, ino);
    final t = _tasks[k];
    if (t != null && (t.state == 'downloading' || t.state == 'queued')) return;
    _tasks[k] = CacheTask(bookId: bookId, ino: ino, ext: mediaExt(ext: ext), url: url);
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
      if (_findComplete(t.bookId, t.ino, t.ext) != null) {
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
        final n = await _api.downloadTrack(t.url, part.path, onProgress: (r, total) {
          t.received = r.toDouble();
          if (total > 0) t.total = total.toDouble();
        }, resume: true);
        if (n <= 0) throw ApiException('下载内容为空');
        if (t.total > 0 && n < t.total) throw ApiException('下载不完整（$n/${t.total}）');
        // 强校验：截断/损坏文件绝不写入完成标记（保留 .part 续传补齐；chunked 响应也不例外）
        if (!_strictContentOk(part)) throw ApiException('文件校验未通过，续传补齐后重试');
        if (f.existsSync()) await f.delete();
        await part.rename(f.path);
        await _doneFile(t.bookId, t.ino).writeAsString('${DateTime.now().toIso8601String()}\n$n');
        t.state = 'done';
        _sizes.remove(t.bookId);
        _cachedInos.putIfAbsent(t.bookId, () => <String>{}).add(t.ino);
        notifyListeners();
        unawaited(_enforceLimit());
      } catch (e) {
        debugPrint('cache download failed: $e');
        if (t.retries < 2) {
          // 失败自动重试（保留 .part 续传；4 秒后重新排队）
          t.retries += 1;
          t.state = 'queued';
          _queue.add(k);
          notifyListeners();
          await Future.delayed(const Duration(seconds: 4));
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
        final ino = p.basenameWithoutExtension(f.path);
        final done = File(p.join(f.parent.path, '$ino.done'));
        if (!done.existsSync()) continue;
        final st = f.statSync();
        entries.add((path: f.path, size: st.size, mtime: st.modified.millisecondsSinceEpoch));
      }
    }
    entries.sort((a, b) => a.mtime.compareTo(b.mtime));
    for (final e in entries) {
      if (total <= maxBytes) break;
      try {
        final ino = p.basenameWithoutExtension(e.path);
        await File(e.path).delete();
        final done = File(p.join(p.dirname(e.path), '$ino.done'));
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
