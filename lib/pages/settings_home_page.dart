/// 发现页设置：模块显隐与排序
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings.dart';
import '../state.dart';
import '../theme.dart';

class HomeSettingsPage extends StatefulWidget {
  const HomeSettingsPage({super.key});
  @override
  State<HomeSettingsPage> createState() => _HomeSettingsPageState();
}

class _HomeSettingsPageState extends State<HomeSettingsPage> {
  late List<(String, bool)> _mods;

  static const Map<String, (String, String, IconData)> _meta = {
    'continue': ('继续收听', '最近在听的书籍，横向滑动', Icons.play_circle_outline),
    'stats': ('聆听数据', '今日 / 本周 / 连续 / 累计统计', Icons.insights_outlined),
    'new': ('最新入库', '最近添加的书籍封面墙', Icons.fiber_new_outlined),
    'libs': ('我的书库', '各书库入口列表', Icons.library_books_outlined),
  };

  @override
  void initState() {
    super.initState();
    _mods = List.of(context.read<AppState>().homeModules);
  }

  Future<void> _save() async {
    await context.read<AppState>().updateHomeModules(_mods);
  }

  Future<void> _reset() async {
    setState(() => _mods = [for (final id in Settings.homeModuleIds) (id, true)]);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现页设置'),
        actions: [TextButton(onPressed: _reset, child: const Text('恢复默认'))],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              '按住右侧图标拖动调整顺序；开关控制模块是否显示。\n例如：把「最新入库」拖到「聆听数据」上面。',
              style: TextStyle(fontSize: 12.5, color: C.text2, height: 1.6),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 40),
              itemCount: _mods.length,
              onReorder: (oldIndex, newIndex) async {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final m = _mods.removeAt(oldIndex);
                  _mods.insert(newIndex, m);
                });
                await _save();
              },
              itemBuilder: (context, i) {
                final (id, on) = _mods[i];
                final meta = _meta[id] ?? (id, '', Icons.widgets_outlined);
                return Container(
                  key: ValueKey(id),
                  margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  decoration: BoxDecoration(
                    color: dark ? C.dCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: Icon(meta.$3, color: on ? C.primary : C.text3),
                    title: Text(
                      meta.$1,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: on ? null : C.text3),
                    ),
                    subtitle: meta.$2.isEmpty ? null : Text(meta.$2, style: const TextStyle(fontSize: 11.5, color: C.text2)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: on,
                          activeThumbColor: C.primary,
                          onChanged: (v) async {
                            setState(() => _mods[i] = (id, v));
                            await _save();
                          },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.drag_handle, color: C.text3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
