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
  final _serverCtl = TextEditingController();
  final _lanCtl = TextEditingController();
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // 带出上次使用的服务器与用户名（登出后再登录时免重新输入）
    try {
      final s = context.read<AppState>().settings;
      _serverCtl.text = s.serverUrl ?? '';
      _lanCtl.text = s.lanServerUrl ?? '';
      _userCtl.text = s.username ?? '';
    } catch (_) {}
  }

  @override
  void dispose() {
    _serverCtl.dispose();
    _lanCtl.dispose();
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
      final lan = _lanCtl.text.trim();
      await app.login(_serverCtl.text.trim(), _userCtl.text.trim(), _passCtl.text, lanServer: lan.isEmpty ? null : lan);
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
              Center(
                child: RichText(
                  text: const TextSpan(children: [
                    TextSpan(text: 'Echo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                    TextSpan(text: 'Shelf', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFC6A15B))),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              const Center(child: Text('自托管有声书 · 连接你的 Audiobookshelf', style: TS.sub)),
              const SizedBox(height: 36),
              const Text('服务器', style: TS.title),
              const SizedBox(height: 10),
              TextField(
                controller: _serverCtl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(hintText: '例如 http://服务器IP或域名:13378/audiobookshelf'),
              ),
              const SizedBox(height: 14),
              const Text('内网地址（可选）', style: TS.sub),
              const SizedBox(height: 8),
              TextField(
                controller: _lanCtl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(hintText: '家里 WiFi 时自动切换，例如 http://192.168.x.x:13378/audiobookshelf'),
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
