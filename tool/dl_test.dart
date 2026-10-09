// 下载链行为测试：验证 dio.download 对 ABS /file/ 的实际请求模式（UA、Range）
// 运行: e:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/dl_test.dart
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final token = File(r'C:\Users\Admin\.hermes\cache\scratch\abs\token.txt').readAsStringSync().trim();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': 'Haven/1.0 (iOS; Audiobookshelf Client)'},
    validateStatus: (s) => s != null && s < 500,
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }));
  final url = 'http://0.0.0.0:13378/audiobookshelf/api/items/b5845ccb-21ca-479e-a249-b2ac6196eaf5/file/11112631';
  final out = r'C:\Users\Admin\.hermes\cache\scratch\abs\dl_test_out.m4a';
  if (File(out).existsSync()) File(out).deleteSync();
  final t0 = DateTime.now();
  final r = await dio.download(
    url,
    out,
    options: Options(
      followRedirects: true,
      receiveTimeout: null,
      headers: {'Accept-Encoding': 'identity'},
    ),
    onReceiveProgress: (recv, total) {
      final pct = total > 0 ? (recv * 100 ~/ total) : -1;
      if (recv % (2 * 1024 * 1024) < 65536 || recv == total) {
        print('progress $recv/$total ($pct%)');
      }
    },
  );
  print('status=${r.statusCode} ct=${r.headers.value('content-type')}');
  print('elapsed=${DateTime.now().difference(t0).inMilliseconds}ms size=${File(out).lengthSync()}');
  print('DONE');
}
