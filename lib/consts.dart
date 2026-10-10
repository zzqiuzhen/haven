/// 全局常量与默认配置
library;

/// App 显示名
const kAppName = 'EchoShelf';
const kAppVersion = '1.6.0';
const kUserAgent = 'EchoShelf/1.6.0 (iOS; Audiobookshelf Client)';

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
  final m = (mime ?? '').toLowerCase();
  if (c.isNotEmpty) {
    if (kTranscodeCodecs.contains(c)) return true;
    if (kDirectPlayCodecs.contains(c)) return false;
  }
  if (m.isNotEmpty) {
    if (m.contains('wma') || m.contains('x-ms-wma') || m.contains('ogg') || m.contains('opus')) return true;
    if (m.contains('mpeg') || m.contains('mp3') || m.contains('aac') || m.contains('m4a') ||
        m.contains('flac') || m.contains('wav') || m.contains('mp4') || m.contains('aiff')) {
      return false;
    }
    return true; // 其它 mime 未知 → 转码兜底
  }
  // codec 与 mime 都未知（如 .strm 无元数据，实际多为 WMA）→ 保守走转码（AAC 可播、可缓存秒播）
  return true;
}
