import 'package:flutter_test/flutter_test.dart';

import 'package:haven/api.dart';

/// 实网联调测试（需要本地代理 127.0.0.1:8899 + TOK define）：
/// flutter test --dart-define=TOK=xxx test/live_api_test.dart
void main() {
  test('live items fetch & parse', () async {
    const tok = String.fromEnvironment('TOK');
    if (tok.isEmpty) {
      print('SKIP: no TOK');
      return;
    }
    final api = Api('http://127.0.0.1:8899')..token = tok;
    final libs = await api.libraries();
    print('LIBS: ${libs.map((l) => l.name).toList()}');
    final r = await api.items(libs.first.id, page: 0, sort: 'addedAt', desc: true);
    print('ITEMS total=${r.total} got=${r.items.length}');
    if (r.items.isNotEmpty) {
      final it = r.items.first;
      print('FIRST: ${it.meta.title} / ${it.meta.authorText} / dur=${it.duration} / tracks=${it.numTracks}');
      final d = await api.itemDetail(it.id);
      print('DETAIL: ${d.meta.title} tracks=${d.tracks.length}');
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
