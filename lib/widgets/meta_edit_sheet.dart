/// 编辑书籍元数据（书名/作者）底部弹窗 —— 本机覆盖，锁屏与界面生效
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';

Future<void> showMetaEditSheet(BuildContext context, LibItem item) async {
  final app = context.read<AppState>();
  final titleCtl = TextEditingController(text: app.effTitle(item));
  final authorCtl = TextEditingController(text: app.effAuthor(item));
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('编辑书籍信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('仅保存在本机，覆盖锁屏与界面显示的书名/作者', style: TextStyle(fontSize: 12, color: C.text2)),
              const SizedBox(height: 14),
              TextField(controller: titleCtl, decoration: const InputDecoration(labelText: '书名')),
              const SizedBox(height: 10),
              TextField(controller: authorCtl, decoration: const InputDecoration(labelText: '作者')),
              const SizedBox(height: 16),
              Row(children: [
                TextButton(
                  onPressed: () async {
                    await app.clearMetaOverride(item.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('恢复默认'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await app.setMetaOverride(item.id, title: titleCtl.text.trim(), author: authorCtl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}
