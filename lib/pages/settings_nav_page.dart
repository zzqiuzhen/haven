/// 任务栏设置：底部导航按钮显隐 / 是否显示文字
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';

class NavSettingsPage extends StatelessWidget {
  const NavSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? C.dCard : Colors.white;

    return Scaffold(
      appBar: AppBar(title: const Text('任务栏设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('显示「发现」', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: const Text('隐藏后仍可通过其他页面返回', style: TextStyle(fontSize: 12, color: C.text2)),
                  value: app.navShowDiscover,
                  activeThumbColor: C.primary,
                  onChanged: (v) => app.setNavPrefs(discover: v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('显示「书库」', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  value: app.navShowLibrary,
                  activeThumbColor: C.primary,
                  onChanged: (v) => app.setNavPrefs(library: v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('显示「搜索」', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  value: app.navShowSearch,
                  activeThumbColor: C.primary,
                  onChanged: (v) => app.setNavPrefs(search: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('仅显示图标', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: const Text('隐藏按钮下方的文字，只保留图标', style: TextStyle(fontSize: 12, color: C.text2)),
              value: app.navIconsOnly,
              activeThumbColor: C.primary,
              onChanged: (v) => app.setNavPrefs(iconsOnly: v),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('提示：「我的」入口始终显示（用于进入设置）。隐藏当前所在页时会自动切到其它页。',
                style: TextStyle(fontSize: 12, color: C.text2, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
