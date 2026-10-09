import 'dart:async';

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
  final api = Api(settings.serverUrl ?? '')..token = settings.token;
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
  bool _wasPlayerOpenWhenAway = false; // 离开前台时是否正处于播放页
  bool _coldStartChecked = false; // 冷启动直达检查只做一次

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.boot();
    // 冷启动场景（进程被杀后由锁屏卡片等唤起）：App 就绪后检查是否应直达播放页
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!_coldStartChecked && _hiddenAt == null) _checkColdStartDirect();
    });
  }

  /// 生命周期黑匣子状态串（写入服务器日志排查用）
  String _lifeStamp() {
    final app = widget.app;
    return 'pgo=$playerPageOpen|hasBook=${app.engine.hasBook}|logged=${app.loggedIn}|playing=${app.engine.playing}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = widget.app;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // 记录首次离开前台的时间（不覆盖）与离开时的页面/播放状态
      _hiddenAt ??= DateTime.now();
      _wasPlayerOpenWhenAway = playerPageOpen;
      unawaited(app.settings.saveBgState(DateTime.now().millisecondsSinceEpoch, app.engine.playing));
      app.engine.diag('life|$state|${_lifeStamp()}');
      app.engine.syncNow();
    } else if (state == AppLifecycleState.resumed) {
      final wasPlayerOpen = _wasPlayerOpenWhenAway;
      _wasPlayerOpenWhenAway = false;
      final since = _hiddenAt;
      _hiddenAt = null;
      int awaySec = 0;
      if (since != null) {
        awaySec = DateTime.now().difference(since).inSeconds;
      } else if (!_coldStartChecked) {
        // 冷启动（本进程没记过后台时间）：走持久化离开时间判定
        _coldStartChecked = true;
        _checkColdStartDirect();
      }
      // 回前台直达播放页的两种场景：
      // 1) 离开时正处于播放页（保持原行为）
      // 2) 锁屏/后台停留较久（≥10 秒）且有书加载 —— 覆盖"锁屏播放器卡片点开、解锁后直达播放页"
      //    （几秒钟的短暂切出——通知中心/控制中心等——仍然不跳，保留 v1.3.9 的防误触）
      final fire = (wasPlayerOpen || awaySec >= 10) &&
          app.engine.hasBook &&
          app.loggedIn &&
          !playerPageOpen &&
          (app.engine.playing || awaySec >= 2);
      app.engine.diag('life|resumed|away=$awaySec|wasOpen=$wasPlayerOpen|fire=$fire|${_lifeStamp()}');
      if (fire) _openPlayerSoon();
    }
  }

  /// 冷启动直达：进程可能被杀过（锁屏卡片唤起=冷启动），用持久化的"离开时间+离开时是否在播+最后播放时间"判定；
  /// 三个条件都满足才尝试：离开 10 秒~12 小时、离开时在播、最后播放记录在 12 小时内
  void _checkColdStartDirect() {
    final app = widget.app;
    final now = DateTime.now().millisecondsSinceEpoch;
    final bgMs = app.settings.bgAtMs;
    final away = bgMs == null ? -1 : ((now - bgMs) / 1000).round();
    final bgPlaying = app.settings.bgPlaying;
    final lp = app.settings.lastPos;
    final lpAge = lp == null ? -1 : ((now - lp.$3) / 1000).round();
    final eligible = away >= 10 && away <= 43200 && bgPlaying && lpAge >= 0 && lpAge <= 43200;
    app.engine.diag('life|cold|away=$away|bgPlaying=$bgPlaying|lpAge=$lpAge|eligible=$eligible');
    if (!eligible) return;
    // 等书加载完成（最多约 9 秒）后直达播放页
    var tries = 0;
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 600));
      tries++;
      final ok = widget.app.loggedIn && widget.app.engine.hasBook && !playerPageOpen;
      final give = tries >= 15;
      widget.app.engine.diag('life|coldtry|$tries|ok=$ok|give=$give|${_lifeStamp()}');
      if (ok) {
        _openPlayerSoon();
        return false;
      }
      return !give;
    }());
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
      if (!mounted || playerPageOpen) {
        widget.app.engine.diag('life|pushskip|mounted=$mounted|${_lifeStamp()}');
        return;
      }
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 4) _openPlayerSoon(attempt: attempt + 1);
        return;
      }
      widget.app.engine.diag('life|push|ok|${_lifeStamp()}');
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
