/// 自定义分类管理 + 分类内书籍列表
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_page.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});
  static Route<void> route() => MaterialPageRoute(builder: (_) => const CategoriesPage());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cats = app.bookCategories;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的分类'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: '新建分类', onPressed: () => _add(context)),
        ],
      ),
      body: cats.isEmpty
          ? const EmptyView('还没有分类\n点右上角 + 新建', icon: Icons.category_outlined)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              itemCount: cats.length,
              itemBuilder: (context, i) {
                final name = cats.keys.elementAt(i);
                final count = cats[name]!.length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: dark ? C.dCard : Colors.white,
                    borderRadius: R.card,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.category_outlined, color: C.primary, size: 22),
                    ),
                    title: Text(name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    subtitle: Text('$count 本', style: const TextStyle(fontSize: 12, color: C.text2)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: C.text2), onPressed: () => _rename(context, name)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: C.text2), onPressed: () => _remove(context, name)),
                    ]),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryBooksPage(name: name))),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final name = await _prompt(context, title: '新建分类', hint: '例如：探险、科幻、悬疑');
    if (name != null && name.isNotEmpty) await context.read<AppState>().addCategory(name);
  }

  Future<void> _rename(BuildContext context, String oldName) async {
    final name = await _prompt(context, title: '重命名分类', initial: oldName);
    if (name != null && name.isNotEmpty && name != oldName) {
      await context.read<AppState>().renameCategory(oldName, name);
    }
  }

  Future<void> _remove(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('删除分类？'),
        content: Text('“$name”将从分类中移除，但不会删除书籍本身。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await context.read<AppState>().removeCategory(name);
  }

  Future<String?> _prompt(BuildContext context, {required String title, String hint = '', String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
  }
}

class CategoryBooksPage extends StatelessWidget {
  const CategoryBooksPage({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ids = app.bookCategories[name] ?? const <String>[];
    final items = <LibItem>[];
    for (final id in ids) {
      final it = app.itemById(id);
      if (it != null) items.add(it);
    }
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: items.isEmpty
          ? const EmptyView('该分类还没有书\n在书籍详情页「加入分类」', icon: Icons.category_outlined)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final it = items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: dark ? C.dCard : Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: HavenCover(it.id, it.meta.title, size: 48, radius: 10),
                    title: Text(it.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    subtitle: Text(it.meta.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.text2)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: C.text2),
                      tooltip: '移出分类',
                      onPressed: () => app.toggleBookCategory(name, it.id),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookPage(item: it))),
                  ),
                );
              },
            ),
    );
  }
}
