/// App 图标选择页（iOS 备用图标，仿 Plappa 图标选择器布局）
library;

import 'package:flutter/material.dart';

import '../app_icon.dart';
import '../theme.dart';

class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key});

  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends State<AppIconPage> {
  String _current = '';
  bool _busy = false;

  static const _groupNames = ['默认', '清爽', '偏蓝', '明亮', '深灰'];

  @override
  void initState() {
    super.initState();
    getCurrentAppIcon().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _pick(AppIconChoice c) async {
    if (_busy || c.id == _current) return;
    if (!supportsAppIconSwitch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更换图标仅支持 iOS 设备')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await setAppIcon(c.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _current = c.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已切换为「${c.label}」' : '切换失败，请重试')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('App 图标'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (var g = 0; g < kAppIconGroups.length; g++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 12),
              child: Text(
                _groupNames[g],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white70 : C.text2,
                ),
              ),
            ),
            Row(
              children: [
                for (final c in kAppIconGroups[g]) ...[
                  Expanded(child: _IconTile(
                    choice: c,
                    selected: c.id == _current,
                    busy: _busy,
                    onTap: () => _pick(c),
                  )),
                  if (c != kAppIconGroups[g].last) const SizedBox(width: 14),
                ],
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            supportsAppIconSwitch
                ? '切换后 iOS 会弹出一个系统提示，属正常现象。图标为本机个性化样式，不影响任何功能。'
                : '更换图标仅支持 iOS 设备（当前平台预览效果，点击无法切换）。',
            style: const TextStyle(fontSize: 12, color: C.text3),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.choice,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final AppIconChoice choice;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: selected
                      ? Border.all(color: C.primary, width: 3)
                      : Border.all(color: Colors.transparent, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: Image.asset(appIconAsset(choice.id), width: 96, height: 96, fit: BoxFit.cover),
                ),
              ),
              if (selected)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 15, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            choice.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? C.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
