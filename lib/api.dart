/// Audiobookshelf API 客户端
library;

import 'dart:io';

import 'package:dio/dio.dart';

import 'consts.dart';
import 'models.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class Api {
  Api(this.baseUrl) {
    final uri = Uri.parse(baseUrl);
    origin = '${uri.scheme}://${uri.authority}';
    basePath = uri.path.replaceAll(RegExp(r'/+$'), '');
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'User-Agent': kUserAgent},
      validateStatus: (s) => s != null && s < 500,
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (token != null) o.headers['Authorization'] = 'Bearer $token';
      if (o.headers['Content-Type'] == null) o.headers['Content-Type'] = 'application/json';
      h.next(o);
    }));
  }

  final String baseUrl;
  late final String origin;
  late final String basePath;
  late final Dio dio;
  String? token;

  String get deviceId => _deviceId ??= 'haven-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';
  String? _deviceId;

  String url(String rel) {
    if (rel.startsWith('http')) return rel;
    if (basePath.isNotEmpty && rel.startsWith('$basePath/')) return origin + rel;
    return baseUrl + rel;
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query, int? timeout}) async {
    try {
      final r = await dio.get(url(path), queryParameters: query, options: timeout == null ? null : Options(receiveTimeout: Duration(seconds: timeout)));
      return _unwrap(r);
    } on DioException catch (e) {
      throw _conv(e);
    }
  }

  Future<dynamic> _post(String path, {Object? data, Map<String, dynamic>? query}) async {
    try {
      final r = await dio.post(url(path), data: data, queryParameters: query);
      return _unwrap(r);
    } on DioException catch (e) {
      throw _conv(e);
    }
  }

  Future<dynamic> _delete(String path) async {
    try {
      final r = await dio.delete(url(path));
      return _unwrap(r);
    } on DioException catch (e) {
      throw _conv(e);
    }
  }

  dynamic _unwrap(Response r) {
    final code = r.statusCode ?? 0;
    if (code >= 200 && code < 300) return r.data;
    if (code == 401) throw ApiException('未登录或登录已过期', statusCode: 401);
    if (code == 403) throw ApiException('没有权限', statusCode: 403);
    if (code == 404) throw ApiException('资源不存在 (404)', statusCode: 404);
    throw ApiException('请求失败 ($code)', statusCode: code);
  }

  ApiException _conv(DioException e) {
    final t = e.type;
    if (t == DioExceptionType.connectionTimeout || t == DioExceptionType.receiveTimeout) {
      return ApiException('连接超时，请检查服务器地址或网络');
    }
    if (t == DioExceptionType.connectionError) {
      return ApiException('无法连接服务器（${e.message ?? ''}）');
    }
    return ApiException(e.message ?? '网络错误');
  }

  Map<String, dynamic> _asMap(dynamic d) => (d as Map?)?.cast<String, dynamic>() ?? const {};

  // ---------------- 基础 ----------------

  Future<ServerStatus> status() async => ServerStatus.fromJson(_asMap(await _get('/status')));

  /// 登录（ABS：POST /login）
  Future<AbsUser> login(String username, String password) async {
    final data = _asMap(await _post('/login', data: {'username': username, 'password': password}));
    final u = (data['user'] as Map?)?.cast<String, dynamic>() ?? data;
    final user = AbsUser.fromJson(u);
    token = user.token;
    return user;
  }

  Future<AbsUser> me() async => AbsUser.fromJson(_asMap(await _get('/api/me')));

  Future<List<Library>> libraries() async {
    final d = _asMap(await _get('/api/libraries'));
    return ((d['libraries'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Library.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<({List<LibItem> items, int total})> items(String libraryId,
      {int page = 0, int limit = 50, String sort = 'addedAt', bool desc = true}) async {
    final d = _asMap(await _get('/api/libraries/$libraryId/items', query: {
      'limit': limit,
      'page': page,
      'sort': sort,
      'desc': desc ? 1 : 0,
      'minified': 1,
    }));
    return (
      items: ((d['results'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LibItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
      total: (d['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 搜索（返回图书条目）
  Future<List<LibItem>> search(String libraryId, String q) async {
    final d = _asMap(await _get('/api/libraries/$libraryId/search', query: {'q': q}));
    final out = <LibItem>[];
    for (final group in ['book', 'books']) {
      for (final e in ((d[group] as List?) ?? const [])) {
        if (e is Map && e['libraryItem'] is Map) {
          out.add(LibItem.fromJson((e['libraryItem'] as Map).cast<String, dynamic>()));
        }
      }
    }
    return out;
  }

  Future<BookDetail> itemDetail(String id) async =>
      BookDetail.fromJson(_asMap(await _get('/api/items/$id', query: {'expanded': 1})));

  // ---------------- 播放会话 ----------------

  Future<PlaySession> startPlay(String itemId, {bool forceTranscode = false}) async {
    final d = _asMap(await _post('/api/items/$itemId/play', data: {
      'deviceInfo': {'clientName': kAppName, 'deviceId': deviceId, 'deviceType': 'ios'},
      'mediaPlayer': kAppName,
      if (forceTranscode) 'forceTranscode': true,
      'supportedMimeTypes': ['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/x-m4a', 'audio/flac', 'audio/wav'],
    }));
    return PlaySession.fromJson(d);
  }

  Future<void> syncSession(String sessionId, {required double currentTime, required double timeListened, double? duration}) async {
    await _post('/api/session/$sessionId/sync', data: {
      'currentTime': currentTime,
      'timeListened': timeListened,
      if (duration != null && duration > 0) 'duration': duration,
    });
  }

  Future<void> closeSession(String sessionId, {Map<String, dynamic>? sync}) async {
    await _post('/api/session/$sessionId/close', data: sync ?? {});
  }

  // ---------------- 进度 / 统计 ----------------

  Future<List<MediaProgress>> progressAll() async {
    final d = _asMap(await _get('/api/me/progress'));
    return ((d['mediaProgress'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MediaProgress.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<MediaProgress?> progressFor(String libraryItemId) async {
    try {
      final d = _asMap(await _get('/api/me/progress/$libraryItemId'));
      final mp = (d['mediaProgress'] as Map?)?.cast<String, dynamic>() ?? d;
      return MediaProgress.fromJson(mp);
    } catch (_) {
      return null;
    }
  }

  /// 继续收听列表（含进度）
  Future<List<(LibItem, MediaProgress)>> itemsInProgress() async {
    final d = _asMap(await _get('/api/me/items-in-progress'));
    final out = <(LibItem, MediaProgress)>[];
    for (final e in ((d['items'] as List?) ?? const [])) {
      if (e is! Map) continue;
      final j = e.cast<String, dynamic>();
      final li = (j['libraryItem'] as Map?)?.cast<String, dynamic>();
      final mp = (j['mediaProgress'] as Map?)?.cast<String, dynamic>() ?? (j['progress'] as Map?)?.cast<String, dynamic>();
      if (li != null && mp != null) {
        out.add((LibItem.fromJson(li), MediaProgress.fromJson(mp)));
      }
    }
    return out;
  }

  Future<ListeningStats> listeningStats() async {
    try {
      return ListeningStats.fromJson(_asMap(await _get('/api/me/listening-stats')));
    } catch (_) {
      return ListeningStats();
    }
  }

  // ---------------- 书签 ----------------

  Future<void> addBookmark(String itemId, double time, String title) async {
    await _post('/api/me/item/$itemId/bookmark', data: {'time': time, 'title': title});
  }

  Future<void> removeBookmark(String itemId, double time) async {
    await _delete('/api/me/item/$itemId/bookmark/${time.round()}');
  }

  Future<List<Bookmark>> bookmarks(String itemId) async {
    try {
      final d = _asMap(await _get('/api/me/bookmarks/$itemId'));
      return ((d['bookmarks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Bookmark.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------- 封面 / 音频 URL ----------------

  String coverUrl(String itemId, {int? width}) => url('/api/items/$itemId/cover') + (width != null ? '?width=$width' : '');

  Map<String, String> get authHeaders => token == null ? const {} : {'Authorization': 'Bearer $token'};

  /// 把会话中的 contentUrl 转成完整可请求地址
  String fullTrackUrl(String contentUrl) => url(contentUrl);

  /// 轨道文件直链（无需会话即可访问，用于预取）
  String fileUrlFor(String itemId, String ino) => url('/api/items/$itemId/file/$ino');

  /// 预热：取 2 字节，触发服务端提前解析 MP 302 并缓存直链（也顺带预热 CDN 连接）
  Future<void> warm(String trackUrl) async {
    try {
      await dio.get(trackUrl,
          options: Options(
            headers: {...authHeaders, 'Range': 'bytes=0-1'},
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 20),
          ));
    } catch (_) {}
  }

  /// 磁盘缓存下载（流式写盘）；完成返回实际写入字节
  Future<int> downloadTrack(String trackUrl, String savePath,
      {required void Function(int received, int total) onProgress, CancelToken? cancel}) async {
    final f = File(savePath);
    await f.parent.create(recursive: true);
    await dio.download(
      trackUrl,
      savePath,
      options: Options(
        followRedirects: true,
        receiveTimeout: null,
        headers: {...authHeaders, 'Accept-Encoding': 'identity'},
      ),
      cancelToken: cancel,
      onReceiveProgress: onProgress,
    );
    return f.lengthSync();
  }
}
