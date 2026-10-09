/// 全局常量与默认配置
library;

/// App 显示名
const kAppName = 'Haven';
const kAppVersion = '1.4.9';
const kUserAgent = 'Haven/1.4.9 (iOS; Audiobookshelf Client)';

/// 播放默认设置
class PlayDefaults {
  static const speed = 1.0;
  static const minSpeed = 0.5;
  static const maxSpeed = 3.0;
  static const speedStep = 0.1;
  static const rewindStep = 15; // 秒
  static const forwardStep = 30;
  static const skipIntro = 0; // 跳过片头秒数
  static const skipOutro = 0; // 跳过片尾秒数
  static const syncInterval = 30; // 进度同步间隔（秒）
  static const autoCacheNext = 5; // 自动缓存后续章节数（流水线补货）
  static const maxCacheGB = 10; // 缓存总大小上限（GB，0=不限）
}

/// iOS 可直连解码的音频编码；其余（如 wma/ogg/opus）需要请求服务端转码
const kDirectPlayCodecs = {
  'aac', 'mp3', 'alac', 'pcm_s16le', 'pcm_s24le', 'pcm_f32le',
  'flac', 'mp4a', 'mp4a.40.2', 'mp4a.40.5', 'aiff', 'm4a', 'ac3', 'eac3',
};

/// 需要转码的编码
const kTranscodeCodecs = {'wmav1', 'wmav2', 'wmapro', 'wma', 'vorbis', 'opus', 'amr_nb'};

bool codecNeedsTranscode(String? codec, String? mime) {
  final c = (codec ?? '').toLowerCase();
  if (c.isNotEmpty) {
    if (kTranscodeCodecs.contains(c)) return true;
    if (kDirectPlayCodecs.contains(c)) return false;
  }
  final m = (mime ?? '').toLowerCase();
  if (m.contains('wma') || m.contains('x-ms-wma') || m.contains('ogg') || m.contains('opus')) return true;
  return false;
}
