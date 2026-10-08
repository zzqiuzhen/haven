import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'audio_handler.dart';
import 'cache_manager.dart';
import 'consts.dart';
import 'pages/login_page.dart';
import 'pages/player_page.dart';
import 'pages/shell.dart';
import 'player_engine.dart';
import 'settings.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sp = await SharedPreferences.getInstance();
  final settings = Settings(sp);
  final api = Api(settings.serverUrl ?? kPresetServers.first.url)..token = settings.token;
  final cache = CacheManager(api);
  await cache.init();
  final engine = PlayerEngine(api: api, cache: cache, settings: settings);

  HavenAudioHandler? handler;
  if (!kIsWeb) {
    try {
      handler = await AudioService.init(
        builder: () => HavenAudioHandler(engine),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'cn.hdhaven.haven.channel.audio',
          androidNotificationChannelName: 'Haven 播放',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('audio service init failed: $e');
    }
  }
  engine.handler = handler;

  final app = AppState(api: api, settings: settings, cache: cache, engine: engine);
  runApp(HavenApp(app: app));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class HavenApp extends StatefulWidget {
  const HavenApp({super.key, required this.app});
  final AppState app;
  @override
  State<HavenApp> createState() => _HavenAppState();
}

class _HavenAppState extends State<HavenApp> with WidgetsBindingObserver {
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // 记录首次离开前台的时间（不覆盖）
      _hiddenAt ??= DateTime.now();
      widget.app.engine.syncNow();
    } else if (state == AppLifecycleState.resumed) {
      final since = _hiddenAt;
      _hiddenAt = null;
      final awaySec = since == null ? 0 : DateTime.now().difference(since).inSeconds;
      // 从锁屏/后台回来且有正在播放的书 → 直达播放页
      // （锁屏“正在播放”卡片点开会唤起 App；awaySec 可能很短，播放中即触发；带多次重试）
      if (widget.app.engine.hasBook &&
          widget.app.loggedIn &&
          !playerPageOpen &&
          (widget.app.engine.playing || awaySec >= 2)) {
        _openPlayerSoon();
      }
    }
  }

  DateTime _lastOpenPushAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 回到前台后直达播放页（多次重试：引擎/导航就绪时间不确定）
  void _openPlayerSoon({int attempt = 0}) {
    if (attempt == 0) {
      final now = DateTime.now();
      if (now.difference(_lastOpenPushAt).inSeconds < 3) return; // 防抖
      _lastOpenPushAt = now;
    }
    Future.delayed(Duration(milliseconds: attempt == 0 ? 400 : 700), () {
      if (!mounted || playerPageOpen) return;
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 4) _openPlayerSoon(attempt: attempt + 1);
        return;
      }
      nav.push(PlayerPage.route());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: app.engine),
        ChangeNotifierProvider.value(value: app.cache),
      ],
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => MaterialApp(
          title: kAppName,
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: HavenTheme.of(Brightness.light),
          darkTheme: HavenTheme.of(Brightness.dark),
          themeMode: app.settings.themeMode,
          home: !app.booted
              ? const _Splash()
              : (app.loggedIn ? const ShellPage() : const LoginPage()),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/appicon/master.png', width: 64, height: 64),
          ),
          const SizedBox(height: 14),
          const Text('Haven', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
