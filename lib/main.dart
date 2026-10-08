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

class HavenApp extends StatefulWidget {
  const HavenApp({super.key, required this.app});
  final AppState app;
  @override
  State<HavenApp> createState() => _HavenAppState();
}

class _HavenAppState extends State<HavenApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      widget.app.engine.syncNow();
    }
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
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.graphic_eq, size: 42, color: C.primary),
          SizedBox(height: 14),
          Text('Haven', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}
