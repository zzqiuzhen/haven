/// 登录页：服务器选择 + 账号登录
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../consts.dart';
import '../state.dart';
import '../theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _serverCtl = TextEditingController(text: kPresetServers.first.url);
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;
  int _preset = 0;

  @override
  void dispose() {
    _serverCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.login(_serverCtl.text.trim(), _userCtl.text.trim(), _passCtl.text);
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/appicon/master.png', width: 84, height: 84),
                ),
              ),
              const SizedBox(height: 20),
              const Center(child: Text('Haven', style: TS.h1)),
              const SizedBox(height: 6),
              const Center(child: Text('自托管有声书 · 连接你的 Audiobookshelf', style: TS.sub)),
              const SizedBox(height: 36),
              const Text('服务器', style: TS.title),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < kPresetServers.length; i++)
                    ChoiceChip(
                      label: Text(kPresetServers[i].label),
                      selected: _preset == i,
                      onSelected: (_) => setState(() {
                        _preset = i;
                        _serverCtl.text = kPresetServers[i].url;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _serverCtl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: 'http://服务器地址:端口/audiobookshelf'),
              ),
              const SizedBox(height: 22),
              const Text('账号', style: TS.title),
              const SizedBox(height: 10),
              TextField(
                controller: _userCtl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtl,
                obscureText: _obscure,
                onSubmitted: (_) => _doLogin(),
                decoration: InputDecoration(
                  hintText: '密码',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: C.red.withValues(alpha: 0.08),
                    borderRadius: R.card,
                  ),
                  child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: C.navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: _busy ? null : _doLogin,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text('登 录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('登录信息仅保存在本机，直连你自己的服务器', style: TS.mini),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
