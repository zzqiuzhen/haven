#!/usr/bin/env python3
"""一次性调整 iOS 工程配置：
- iOS 最低版本 16.0（Podfile / pbxproj / AppFrameworkInfo.plist）
- 后台音频播放（UIBackgroundModes audio）
- 允许 http（Tailscale / 局域网直连服务器）+ 本地网络权限说明
- 显示名 Haven、默认中文
用法: python tools/patch_ios.py
"""
import os
import plistlib
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, 'ios')


def patch_info_plist():
    p = os.path.join(IOS, 'Runner', 'Info.plist')
    with open(p, 'rb') as f:
        pl = plistlib.load(f)
    pl['UIBackgroundModes'] = ['audio']
    pl['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True, 'NSAllowsLocalNetworking': True}
    pl['CFBundleDisplayName'] = 'Haven'
    pl['CFBundleDevelopmentRegion'] = 'zh_CN'
    pl['CFBundleLocalizations'] = ['zh_CN']
    pl['NSLocalNetworkUsageDescription'] = '用于连接局域网或 Tailscale 内的 Audiobookshelf 服务器'
    pl['NSPhotoLibraryUsageDescription'] = '用于从相册选择自定义头像'
    pl['ITSAppUsesNonExemptEncryption'] = False
    pl['CADisableMinimumFrameDurationOnPhone'] = True
    with open(p, 'wb') as f:
        plistlib.dump(pl, f)
    print('Info.plist patched')


def patch_appframework():
    p = os.path.join(IOS, 'Flutter', 'AppFrameworkInfo.plist')
    with open(p, 'rb') as f:
        pl = plistlib.load(f)
    pl['MinimumOSVersion'] = '16.0'
    with open(p, 'wb') as f:
        plistlib.dump(pl, f)
    print('AppFrameworkInfo.plist patched')


def patch_podfile():
    p = os.path.join(IOS, 'Podfile')
    if not os.path.exists(p):
        print('Podfile 不存在（使用 Swift Package Manager 模式），跳过')
        return
    src = open(p, encoding='utf-8').read()
    if re.search(r"#?\s*platform :ios, '[^']+'", src):
        src = re.sub(r"#?\s*platform :ios, '[^']+'", "platform :ios, '16.0'", src)
    else:
        src = "platform :ios, '16.0'\n" + src
    open(p, 'w', encoding='utf-8').write(src)
    print('Podfile patched')


def patch_pbxproj():
    p = os.path.join(IOS, 'Runner.xcodeproj', 'project.pbxproj')
    src = open(p, encoding='utf-8').read()
    src2 = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;', src)
    open(p, 'w', encoding='utf-8').write(src2)
    print('project.pbxproj patched:', src2.count('IPHONEOS_DEPLOYMENT_TARGET = 16.0;'))


if __name__ == '__main__':
    patch_info_plist()
    patch_appframework()
    patch_podfile()
    patch_pbxproj()
    print('done')
