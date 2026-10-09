/// 搜索页
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'book_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<LibItem> _results = [];
  bool _busy = false;
  String _q = '';

  @override
  void dispose() {
    _ctl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    setState(() {
      _q = q;
      if (q.isEmpty) _results = [];
    });
    if (q.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<AppState>().searchAll(q);
      if (mounted && _q == q) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败：$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 12), child: Text('搜索', style: TS.h1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _ctl,
              onChanged: _onChanged,
              onSubmitted: (v) => _search(v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索书名 / 作者',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _ctl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _ctl.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _busy
                ? const LoadingView()
                : (_q.isEmpty
                    ? const EmptyView('输入关键词，搜索你的有声书库', icon: Icons.search)
                    : (_results.isEmpty
                        ? const EmptyView('没有找到相关书籍')
                        : ListView.separated(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 220),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final it = _results[i];
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: it))),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark ? C.dCard : Colors.white,
                                    borderRadius: R.card,
                                  ),
                                  child: Row(
                                    children: [
                                      HavenCover(it.id, it.meta.title, size: 54, radius: 10),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(it.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            Text(
                                              [it.meta.authorText, if (it.meta.narrators.isNotEmpty) '演播 ${it.meta.narratorText}'].join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, color: C.text2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (it.duration > 0)
                                        Text(fmtDur(it.duration), style: TS.mini),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ))),
          ),
        ],
      ),
    );
  }
}
