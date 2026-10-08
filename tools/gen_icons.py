#!/usr/bin/env python3
"""从 assets/appicon/master.png 生成 iOS AppIcon 全套尺寸。
用法: python tools/gen_icons.py"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(ROOT, 'assets', 'appicon', 'master.png')
APPSET = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
CONTENTS = os.path.join(APPSET, 'Contents.json')


def main():
    if not os.path.exists(MASTER):
        print('缺少 master.png:', MASTER)
        sys.exit(1)
    master = Image.open(MASTER).convert('RGB')
    spec = json.load(open(CONTENTS, encoding='utf-8'))
    made = 0
    for img in spec.get('images', []):
        fn = img.get('filename')
        size = img.get('size')
        scale = img.get('scale')
        if not fn or not size or not scale:
            continue
        w = round(float(size.split('x')[0]) * int(scale.replace('x', '')))
        im = master.resize((w, w), Image.LANCZOS)
        im.save(os.path.join(APPSET, fn))
        made += 1
    print(f'生成 {made} 个图标 -> {APPSET}')


if __name__ == '__main__':
    main()
