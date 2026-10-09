/// 搜索页（独立全屏路由：只弹键盘 + 最近搜索历史，不带底部任务栏/迷你播放器）
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

  static Route<void> route() => MaterialPageRoute(builder: (_) => const SearchPage());

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<LibItem> _results = [];
  bool _busy = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    // 打开即弹出键盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    final qq = q.trim();
    if (qq.isNotEmpty) {
      await context.read<AppState>().addRecentSearch(qq);
    }
    setState(() {
      _q = qq;
      if (qq.isEmpty) _results = [];
    });
    if (qq.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<AppState>().searchAll(qq);
      if (mounted && _q == qq) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败：$e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  void _applyRecent(String q) {
    _ctl.text = q;
    _ctl.selection = TextSelection.collapsed(offset: q.length);
    _search(q);
  }

  Widget _recentView(List<String> recent) {
    if (recent.isEmpty) {
      return const EmptyView('输入关键词，搜索你的有声书库', icon: Icons.search);
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Row(children: [
          const Text('最近搜索', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () => context.read<AppState>().clearRecentSearches(),
            child: const Icon(Icons.delete_outline, size: 18, color: C.text2),
          ),
        ]),
        const SizedBox(height: 6),
        for (final q in recent)
          InkWell(
            onTap: () => _applyRecent(q),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(children: [
                const Icon(Icons.history, size: 17, color: C.text2),
                const SizedBox(width: 10),
                Expanded(child: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5))),
                const Icon(Icons.north_west, size: 14, color: C.text3),
              ]),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? C.dBg : C.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 22, color: C.text2),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    focusNode: _focus,
                    autofocus: true,
                    onChanged: _onChanged,
                    onSubmitted: (v) => _search(v.trim()),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索书名 / 作者',
                      isDense: true,
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
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const LoadingView()
                  : (_q.isEmpty
                      ? _recentView(app.recentSearches)
                      : (_results.isEmpty
                          ? const EmptyView('没有找到相关书籍')
                          : ListView.separated(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                              itemCount: _results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final it = _results[i];
                                return GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: it))),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: dark ? C.dCard : Colors.white,
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
                                        if (it.duration > 0) Text(fmtDur(it.duration), style: TS.mini),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ))),
            ),
          ],
        ),
      ),
    );
  }
}
