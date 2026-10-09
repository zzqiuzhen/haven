/// 我的：账号 / 内容入口 / 设置
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../consts.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'downloads_page.dart';
import 'recent_page.dart';
import 'settings_home_page.dart';
import 'settings_nav_page.dart';
import 'settings_playback_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.me;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 220),
        children: [
          const Text('我的', style: TS.h1),
          const SizedBox(height: 16),
          Glass(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _AvatarTap(username: me?.username ?? ''),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me?.username ?? '未登录', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(app.api.baseUrl, style: const TextStyle(fontSize: 11.5, color: C.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (me?.isAdmin == true) const Pill('管理员', color: C.orange),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: dark ? C.dLine : C.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () => _confirmLogout(context, app),
                    child: const Text('退出登录', style: TextStyle(fontSize: 14, color: C.text2)),
                  ),
                ),
              ],
            ),
          ),
          _group('我的内容', C.teal),
          _MenuCard(items: [
            _MenuItem(Icons.play_circle_outline, C.primary, '继续收听', '回到发现页', () => app.setTab(0)),
            _MenuItem(Icons.history, C.teal, '阅读记录', '全部收听历史', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecentPage()));
            }),
            _MenuItem(Icons.download_outlined, C.purple, '下载与缓存', '离线缓存管理', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsPage()));
            }),
          ]),
          _group('设置与偏好', C.purple),
          _MenuCard(items: [
            _MenuItem(Icons.tune, C.orange, '播放设置', '倍速 / 跳过 / 同步 / 缓存', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaybackSettingsPage()));
            }),
            _MenuItem(Icons.dashboard_customize_outlined, C.teal, '发现页设置', '模块显示与排序', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeSettingsPage()));
            }),
            _MenuItem(Icons.view_week_outlined, C.primary, '任务栏设置', '底部按钮显隐 / 仅图标', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NavSettingsPage()));
            }),
            _MenuItem(Icons.dns_outlined, C.primary, '服务器', app.api.baseUrl, () => _showServer(context, app)),
            _MenuItem(Icons.palette_outlined, C.purple, '主题模式', switch (app.settings.themeMode) {
              ThemeMode.light => '浅色',
              ThemeMode.dark => '深色',
              _ => '跟随系统',
            }, () => _pickTheme(context, app)),
            _MenuItem(Icons.info_outline, C.text2, '关于 Haven',
                'v$kAppVersion · 服务端 ABS ${app.serverInfo?.serverVersion ?? '-'}', () => _about(context, app)),
          ]),
        ],
      ),
    );
  }

  Widget _group(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('将停止播放并清除本机登录状态（服务器上的收听进度保留）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red),
            onPressed: () {
              Navigator.pop(ctx);
              app.logout();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showServer(BuildContext context, AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('当前服务器'),
        content: SelectableText(app.api.baseUrl, style: const TextStyle(fontSize: 14)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  void _pickTheme(BuildContext context, AppState app) {
    final cur = app.settings.themeMode;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(14), child: Text('主题模式', style: TS.title)),
            for (final e in [
              (ThemeMode.system, '跟随系统', Icons.brightness_auto),
              (ThemeMode.light, '浅色', Icons.light_mode_outlined),
              (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
            ])
              ListTile(
                leading: Icon(e.$3),
                title: Text(e.$2),
                trailing: cur == e.$1 ? const Icon(Icons.check, color: C.primary) : null,
                onTap: () {
                  app.setThemeMode(e.$1 == ThemeMode.light ? 'light' : (e.$1 == ThemeMode.dark ? 'dark' : 'system'));
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _about(BuildContext context, AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于 Haven'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Haven · 自托管有声书客户端\n为你自己的 Audiobookshelf + 115 网盘环境定制，起播做了加热与缓存优化。', style: TextStyle(fontSize: 13.5)),
            const SizedBox(height: 10),
            SelectableText('客户端版本：v$kAppVersion\n服务端：Audiobookshelf ${app.serverInfo?.serverVersion ?? '-'}\n开源仓库：github.com/zzqiuzhen/haven', style: const TextStyle(fontSize: 12.5, color: C.text2)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
  _MenuItem(this.icon, this.color, this.title, this.sub, this.onTap);
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 22,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: items[i].color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(items[i].icon, size: 21, color: items[i].color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(items[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.text2)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20, color: C.text3),
                  ],
                ),
              ),
            ),
            if (i != items.length - 1)
              const Divider(height: 1, indent: 66, endIndent: 14),
          ],
        ],
      ),
    );
  }
}

/// 头像按钮：点击可自定义（相册选择 / 恢复默认）
class _AvatarTap extends StatefulWidget {
  const _AvatarTap({required this.username});
  final String username;
  @override
  State<_AvatarTap> createState() => _AvatarTapState();
}

class _AvatarTapState extends State<_AvatarTap> {
  File? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<File> _avatarFile() async {
    final base = await getApplicationSupportDirectory();
    return File(p.join(base.path, 'avatar.jpg'));
  }

  Future<void> _load() async {
    try {
      final f = await _avatarFile();
      if (f.existsSync() && mounted) setState(() => _file = f);
    } catch (_) {}
  }

  Future<void> _onTap() async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(14), child: Text('头像', style: TS.title)),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: C.primary),
              title: const Text('从相册选择图片'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (_file != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: C.red),
                title: const Text('恢复默认头像'),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'pick') {
      setState(() => _busy = true);
      try {
        final x = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 86,
        );
        if (x != null) {
          final bytes = await x.readAsBytes();
          if (bytes.isNotEmpty) {
            final f = await _avatarFile();
            await f.writeAsBytes(bytes, flush: true);
            if (mounted) setState(() => _file = f);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择头像失败：$e')));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else if (act == 'reset') {
      try {
        final f = await _avatarFile();
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      if (mounted) setState(() => _file = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.username.isNotEmpty ? widget.username.characters.first.toUpperCase() : '?';
    final f = _file;
    return GestureDetector(
      onTap: _busy ? null : _onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox(
              width: 58,
              height: 58,
              child: f != null
                  ? Image.file(f, fit: BoxFit.cover)
                  : Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF5B7CFA), Color(0xFF8B5CF6)]),
                      ),
                      child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
              ),
              child: _busy
                  ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                  : const Icon(Icons.photo_camera, size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
