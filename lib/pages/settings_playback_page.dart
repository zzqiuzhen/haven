/// 播放设置
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../cache_manager.dart';
import '../state.dart';
import '../theme.dart';

class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});
  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cache = context.watch<CacheManager>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('播放设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _card([
            _rowTitle('默认倍速', '${s.speed}x'),
            Slider(
              value: s.speed.clamp(0.5, 3.0),
              min: 0.5,
              max: 3.0,
              divisions: 25,
              label: '${s.speed}x',
              onChanged: (v) => setState(() => s.speed = v),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            _rowTitle('快退步长', '${s.rewindStep} 秒'),
            _chips([10, 15, 30, 60], s.rewindStep, (v) => setState(() => s.rewindStep = v), '%ds'),
            const SizedBox(height: 10),
            _rowTitle('快进步长', '${s.forwardStep} 秒'),
            _chips([10, 15, 30, 60], s.forwardStep, (v) => setState(() => s.forwardStep = v), '%ds'),
          ]),
          const SizedBox(height: 12),
          _card([
            _rowTitle('跳过片头', s.skipIntro == 0 ? '关闭' : '${s.skipIntro} 秒'),
            _chips([0, 5, 10, 15, 20, 30, 60], s.skipIntro, (v) => setState(() => s.skipIntro = v), '%ds'),
            const SizedBox(height: 10),
            _rowTitle('跳过片尾', s.skipOutro == 0 ? '关闭' : '${s.skipOutro} 秒'),
            _chips([0, 5, 10, 15, 20, 30, 60], s.skipOutro, (v) => setState(() => s.skipOutro = v), '%ds'),
          ]),
          const SizedBox(height: 12),
          _card([
            _rowTitle('进度同步间隔', '${s.syncInterval} 秒'),
            _chips([15, 30, 60, 120], s.syncInterval, (v) => setState(() => s.syncInterval = v), '%ds'),
            const SizedBox(height: 10),
            _rowTitle('自动缓存后续章节', s.autoCacheNext == 0 ? '关闭' : '${s.autoCacheNext} 章'),
            _chips([0, 1, 2, 3, 5], s.autoCacheNext, (v) => setState(() => s.autoCacheNext = v), '%d'),
          ]),
          const SizedBox(height: 12),
          _card([
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('极速直连模式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: const Text('播放时直接跟随 MoviePilot 302 到 115 CDN（失败自动回退服务端代理）', style: TextStyle(fontSize: 12, color: C.text2)),
              value: s.directMode,
              activeColor: C.primary,
              onChanged: (v) => setState(() => s.directMode = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('耳机断开自动暂停', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              value: s.pauseOnHeadsetDisconnect,
              activeColor: C.primary,
              onChanged: (v) => setState(() => s.pauseOnHeadsetDisconnect = v),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cleaning_services_outlined, color: C.orange),
              title: const Text('清理音频缓存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: const Text('删除所有已下载的章节，释放存储空间', style: TextStyle(fontSize: 12, color: C.text2)),
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清理全部缓存？'),
                  content: const Text('将删除所有已下载的章节音频。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.red),
                      onPressed: () {
                        Navigator.pop(ctx);
                        cache.clearAll();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清理')));
                      },
                      child: const Text('清理'),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const Center(child: Text('设置即时生效，无需重启应用', style: TS.mini)),
        ],
      ),
    );
  }

  Widget _rowTitle(String t, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(v, style: const TextStyle(fontSize: 13, color: C.text2)),
        ],
      ),
    );
  }

  Widget _chips(List<int> values, int cur, ValueChanged<int> onPick, String fmt) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(v == 0 ? '关闭' : fmt.replaceAll('%d', '$v').replaceAll('%s', '$v')),
            selected: cur == v,
            onSelected: (_) => onPick(v),
          ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: dark ? C.dCard : Colors.white, borderRadius: R.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
