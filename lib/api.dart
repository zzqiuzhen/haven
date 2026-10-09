/// Audiobookshelf API 客户端
library;

import 'dart:io';

import 'package:dio/dio.dart';

import 'consts.dart';
import 'models.dart';

/// 全局共享的 API 实例（供无法访问 Provider 的组件使用，如封面组件；
/// 由 AppState 在构造 / 切换服务器 / 开发注入时更新）
Api? sharedApi;

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

  Future<Map<String, dynamic>> itemDetailRaw(String id) async =>
      _asMap(await _get('/api/items/$id', query: {'expanded': 1}));

  Future<BookDetail> itemDetail(String id) async => BookDetail.fromJson(await itemDetailRaw(id));

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

  /// 单集转码缓存直链（WMA→AAC；服务端首次请求时生成并缓存，供手机缓存秒播）
  String transcodedFileUrlFor(String itemId, String ino) => url('/api/items/$itemId/file/$ino?transcoded=1');

  /// 预热：取 2 字节，触发服务端提前解析 MP 302 并缓存直链（也顺带预热 CDN 连接）；
  /// 返回最终响应（供直连预检读取 content-disposition，判断该文件能否被 AVPlayer 直接播放）
  Future<Response?> warm(String trackUrl) async {
    try {
      return await dio.get(trackUrl,
          options: Options(
            headers: {...authHeaders, 'Range': 'bytes=0-1'},
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 20),
          ));
    } catch (_) {
      return null;
    }
  }

  /// 快速探测 URL 是否可达（用于决定是否走“极速直连”）
  /// 硬上限 [timeout] 封顶：超时立即取消请求并返回 false（TCP 挂起不会拖住调用方）
  Future<bool> reachable(String trackUrl, {Duration timeout = const Duration(milliseconds: 1500)}) async {
    final ct = CancelToken();
    try {
      final r = await dio.get(trackUrl,
          options: Options(
            followRedirects: false,
            validateStatus: (s) => s != null,
            receiveTimeout: timeout,
            sendTimeout: timeout,
            headers: {...authHeaders, 'Range': 'bytes=0-1'},
          ),
          cancelToken: ct).timeout(timeout);
      final c = r.statusCode ?? 0;
      return c >= 200 && c < 400;
    } catch (_) {
      try {
        ct.cancel('probe timeout');
      } catch (_) {}
      return false;
    }
  }

  /// 磁盘缓存下载（断点续传 + 完整性校验；完成返回文件字节数）
  ///
  /// [savePath] 已存在且 [resume] 为 true 时从现有长度继续（网络抖动可续传）；
  /// 服务器不支持 Range 时自动回退为全量重下；单次 45 秒无数据自动续传重试。
  Future<int> downloadTrack(String trackUrl, String savePath,
      {required void Function(int received, int total) onProgress,
      CancelToken? cancel,
      bool resume = true}) async {
    final f = File(savePath);
    await f.parent.create(recursive: true);
    if (!resume && await f.exists()) await f.delete();
    var have = await f.exists() ? await f.length() : 0;
    var total = 0;
    Object? lastErr;
    const maxTries = 6;
    for (var attempt = 0; attempt < maxTries; attempt++) {
      if (cancel?.isCancelled == true) break;
      try {
        final headers = <String, dynamic>{...authHeaders, 'Accept-Encoding': 'identity'};
        if (have > 0) headers['Range'] = 'bytes=$have-';
        final resp = await dio.get<ResponseBody>(
          trackUrl,
          options: Options(
            followRedirects: true,
            responseType: ResponseType.stream,
            headers: headers,
            receiveTimeout: const Duration(seconds: 45),
          ),
          cancelToken: cancel,
        );
        final code = resp.statusCode ?? 0;
        final body = resp.data;
        if (body == null) throw ApiException('下载失败：空响应');
        if (code == 206) {
          final cr = resp.headers.value('content-range') ?? '';
          final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
          if (m == null) throw ApiException('下载失败：缺少 Content-Range');
          final t = int.tryParse(m.group(1)!);
          if (t != null && t > 0) total = t;
        } else if (code == 200) {
          if (have > 0) {
            // 服务器不支持断点续传：从头开始
            await f.delete();
            have = 0;
          }
          final cl = resp.headers.value('content-length');
          final t = cl == null ? null : int.tryParse(cl);
          if (t != null && t > 0) total = t;
        } else if (code == 416) {
          await f.delete();
          have = 0;
          lastErr = ApiException('响应 416，重新开始');
          continue;
        } else {
          throw ApiException('下载失败 ($code)');
        }
        final sink = f.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
        var got = have;
        try {
          await for (final chunk in body.stream) {
            sink.add(chunk);
            got += chunk.length;
            onProgress(got, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        have = await f.exists() ? await f.length() : got;
        if (total > 0 && have >= total) return have;
        if (total == 0 && have > 1024) return have;
        lastErr = ApiException('连接中断（$have/${total > 0 ? total : '?'}），自动续传');
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) break;
        lastErr = _conv(e);
      } catch (e) {
        lastErr = e;
      }
      if (attempt < maxTries - 1) {
        await Future.delayed(Duration(milliseconds: 1000 + attempt * 900));
      }
      have = await f.exists() ? await f.length() : 0;
    }
    throw lastErr is Exception ? lastErr : ApiException('下载中断');
  }
}
