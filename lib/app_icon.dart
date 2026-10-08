/// iOS 备用 App 图标切换（设置页使用；非 iOS 平台为无害的空实现）
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppIconChoice {
  /// iOS alternate icon 名（'' = 主图标）
  final String id;

  /// 显示名
  final String label;
  const AppIconChoice(this.id, this.label);
}

/// 5 组 × 2（浅色 / 深色）= 10 个可选图标
const kAppIconGroups = <List<AppIconChoice>>[
  [AppIconChoice('', '默认'), AppIconChoice('AppIconDefaultDark', '默认·橙鸟')],
  [AppIconChoice('AppIconFresh', '清爽'), AppIconChoice('AppIconFreshDark', '清爽·深色')],
  [AppIconChoice('AppIconBlue', '偏蓝'), AppIconChoice('AppIconBlueDark', '偏蓝·深色')],
  [AppIconChoice('AppIconBright', '明亮'), AppIconChoice('AppIconBrightDark', '明亮·深色')],
  [AppIconChoice('AppIconDark', '深灰'), AppIconChoice('AppIconDarkDark', '纯黑')],
];

String _assetNameFor(String id) {
  switch (id) {
    case 'AppIconDefaultDark':
      return 'default_dark';
    case 'AppIconFresh':
      return 'fresh_light';
    case 'AppIconFreshDark':
      return 'fresh_dark';
    case 'AppIconBlue':
      return 'blue_light';
    case 'AppIconBlueDark':
      return 'blue_dark';
    case 'AppIconBright':
      return 'bright_light';
    case 'AppIconBrightDark':
      return 'bright_dark';
    case 'AppIconDark':
      return 'dark_light';
    case 'AppIconDarkDark':
      return 'dark_dark';
  }
  return 'default_light';
}

/// 预览图资源路径
String appIconAsset(String id) =>
    'assets/appicon/alt_previews/${_assetNameFor(id)}.png';

const MethodChannel _ch = MethodChannel('haven/appicon');

bool get supportsAppIconSwitch =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 当前图标 id（'' = 主图标；非 iOS / 失败返回 ''）
Future<String> getCurrentAppIcon() async {
  if (!supportsAppIconSwitch) return '';
  try {
    final s = await _ch.invokeMethod<String>('getIcon');
    return s ?? '';
  } catch (_) {
    return '';
  }
}

/// 切换图标；返回是否成功
Future<bool> setAppIcon(String id) async {
  if (!supportsAppIconSwitch) return false;
  try {
    final ok = await _ch.invokeMethod<bool>('setIcon', id);
    return ok == true;
  } catch (_) {
    return false;
  }
}
