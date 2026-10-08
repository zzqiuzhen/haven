#!/usr/bin/env python3
"""一次性补丁：注册 AppIconPlugin + 备用图标 + 设置页入口 + 锁屏直达加固 + 冷启动恢复提前。
用法: python tools/apply_patches_v110.py"""
import io
import os
import plistlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def edit(path, reps):
    src = io.open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    for i, (o, n) in enumerate(reps, 1):
        o2 = o.replace('\n', nl)
        n2 = n.replace('\n', nl)
        c = src.count(o2)
        assert c == 1, f"{path} anchor#{i} count={c}"
        src = src.replace(o2, n2)
    io.open(path, 'w', encoding='utf-8', newline='').write(src)
    print(f"patched {os.path.basename(path)} ({len(reps)} edits)")


# ---------- 1. project.pbxproj：注册 AppIconPlugin.swift ----------
BF = 'AB12CD34EF5600000000A001'
FR = 'AB12CD34EF5600000000A002'
A1 = "74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 74858FAE1ED2DC5600515810 /* AppDelegate.swift */; };"
A2 = '74858FAE1ED2DC5600515810 /* AppDelegate.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };'
A3 = "\t\t\t\t74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n\t\t\t\t7884E8672EC3CC0400C636F2 /* SceneDelegate.swift */,"
A4 = "\t\t\t\t74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,\n\t\t\t\t1498D2341E8E89220040F4C2 /* GeneratedPluginRegistrant.m in Sources */,"
edit(os.path.join(ROOT, 'ios', 'Runner.xcodeproj', 'project.pbxproj'), [
    (A1, A1 + f"\n\t\t{BF} /* AppIconPlugin.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FR} /* AppIconPlugin.swift */; }};"),
    (A2, A2 + f"\n\t\t{FR} /* AppIconPlugin.swift */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = AppIconPlugin.swift; sourceTree = \"<group>\"; }};"),
    (A3, "\t\t\t\t74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n\t\t\t\t" + FR + " /* AppIconPlugin.swift */,\n\t\t\t\t7884E8672EC3CC0400C636F2 /* SceneDelegate.swift */,"),
    (A4, "\t\t\t\t74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,\n\t\t\t\t" + BF + " /* AppIconPlugin.swift in Sources */,\n\t\t\t\t1498D2341E8E89220040F4C2 /* GeneratedPluginRegistrant.m in Sources */,"),
])

# ---------- 2. AppDelegate.swift：注册插件 ----------
edit(os.path.join(ROOT, 'ios', 'Runner', 'AppDelegate.swift'), [
    ("    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)\n",
     "    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)\n    AppIconPlugin.register(with: engineBridge.pluginRegistry)\n"),
])

# ---------- 3. Info.plist：CFBundleAlternateIcons ----------
p = os.path.join(ROOT, 'ios', 'Runner', 'Info.plist')
with open(p, 'rb') as f:
    pl = plistlib.load(f)
alts = ["AppIconDefaultDark", "AppIconFresh", "AppIconFreshDark", "AppIconBlue",
        "AppIconBlueDark", "AppIconBright", "AppIconBrightDark", "AppIconDark", "AppIconDarkDark"]
pl['CFBundleIcons'] = {
    'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['AppIcon60x60'], 'CFBundleIconName': 'AppIcon'},
    'CFBundleAlternateIcons': {n: {'CFBundleIconFiles': [n], 'CFBundleIconName': n} for n in alts},
}
with open(p, 'wb') as f:
    plistlib.dump(pl, f)
print('Info.plist patched (CFBundleAlternateIcons x9)')

# ---------- 4. me_page.dart：图标入口 ----------
edit(os.path.join(ROOT, 'lib', 'pages', 'me_page.dart'), [
    ("import 'downloads_page.dart';",
     "import '../app_icon.dart';\nimport 'app_icon_page.dart';\nimport 'downloads_page.dart';"),
    ("            _MenuItem(Icons.info_outline, C.text2, '关于 Haven',",
     "            if (supportsAppIconSwitch)\n              _MenuItem(Icons.phone_iphone, C.teal, 'App 图标', '更换桌面图标样式', () {\n                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppIconPage()));\n              }),\n            _MenuItem(Icons.info_outline, C.text2, '关于 Haven',"),
])

# ---------- 5. pubspec.yaml：预览图资产 + 版本 ----------
edit(os.path.join(ROOT, 'pubspec.yaml'), [
    ("  assets:\n    - assets/appicon/master.png\n",
     "  assets:\n    - assets/appicon/master.png\n    - assets/appicon/alt_previews/\n"),
    ("version: 1.0.9+10", "version: 1.1.0+11"),
])

# ---------- 6. consts.dart：版本号 ----------
edit(os.path.join(ROOT, 'lib', 'consts.dart'), [
    ("const kAppVersion = '1.0.9';", "const kAppVersion = '1.1.0';"),
])

# ---------- 7. main.dart：锁屏直达加固 ----------
edit(os.path.join(ROOT, 'lib', 'main.dart'), [
    ("""      // 从锁屏/后台回来（离开超过 2 秒）且有正在播放的书、且不在播放页 → 直达播放器
      if (awaySec >= 2 && widget.app.engine.hasBook && !playerPageOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (navigatorKey.currentState != null && !playerPageOpen) {
              navigatorKey.currentState!.push(PlayerPage.route());
            }
          });
        });
      }
    }
  }""",
     """      // 从锁屏/后台回来（离开超过 2 秒）且有正在播放的书、且不在播放页 → 直达播放器
      // （锁屏点“正在播放”卡片会唤起 App，此处保证直接落到播放页；带重试以适配导航就绪时机）
      if (awaySec >= 2 && widget.app.engine.hasBook && widget.app.loggedIn && !playerPageOpen) {
        _openPlayerSoon();
      }
    }
  }

  /// 回到前台后直达播放页（重试 2 次：引擎/导航就绪时间不确定）
  void _openPlayerSoon({int attempt = 0}) {
    Future.delayed(Duration(milliseconds: 450 + attempt * 700), () {
      if (!mounted || playerPageOpen) return;
      final nav = navigatorKey.currentState;
      if (nav == null) {
        if (attempt < 2) _openPlayerSoon(attempt: attempt + 1);
        return;
      }
      nav.push(PlayerPage.route());
    });
  }"""),
])

# ---------- 8. state.dart：restoreLast 提前（迷你播放器更早出现） ----------
edit(os.path.join(ROOT, 'lib', 'state.dart'), [
    ("      final m = await api.me();\n      me = m;\n",
     "      final m = await api.me();\n      me = m;\n      // 冷启动自动恢复上次播放（优先本机位置；不自动播放，仅加载到引擎 → 迷你播放器立即出现）\n      unawaited(engine.restoreLast());\n"),
    ("    loadingHome = false;\n    notifyListeners();\n    // 冷启动自动恢复上次播放（不自动播放，仅加载到引擎 → 迷你播放器出现）\n    unawaited(engine.restoreLast());\n  }",
     "    loadingHome = false;\n    notifyListeners();\n  }"),
])

print('ALL PATCHES APPLIED')
