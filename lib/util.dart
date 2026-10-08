/// 通用工具函数
library;

import 'package:intl/intl.dart';

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
int toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// 时长格式化：>1h 显示 h:mm:ss，否则 mm:ss
String fmtDur(double seconds, {bool hoursAlways = false}) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  if (h > 0 || hoursAlways) {
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// 总时长展示（"3小时25分"）
String fmtTotal(double seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  if (h > 0 && m > 0) return '$h小时$m分';
  if (h > 0) return '$h小时';
  if (m > 0) return '$m分钟';
  return '$s秒';
}

/// 相对时间（"3小时前"/"昨天"）
String fmtAgo(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return DateFormat('yyyy年M月d日').format(t);
}

/// "10月8日 星期三"
String todayLabel() {
  final now = DateTime.now();
  const week = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month}月${now.day}日 星期${week[now.weekday - 1]}';
}

/// 去掉音频文件名后缀等显示噪音（章节标题清洗）
String prettyTrackTitle(String t) {
  var s = t.replaceAll(RegExp(r'\.(strm|mp3|m4a|m4b|wma|aac|flac|ogg|opus|wav|mp4)$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.isEmpty ? t : s;
}

String fmtBytes(double bytes) {
  if (bytes <= 0) return '0B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double v = bytes;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}${units[i]}';
}

/// 清洗 ABS 返回的 HTML 简介
String cleanHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  var t = html
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return t;
}
