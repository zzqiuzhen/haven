/// 数据模型（对 Audiobookshelf API 的宽容解析）
library;

import 'util.dart';

String _s(dynamic v) => v == null ? '' : v.toString();

class AbsUser {
  final String id;
  final String username;
  final String type;
  final String? token;
  final List<MediaProgress> mediaProgress;
  AbsUser({
    required this.id,
    required this.username,
    required this.type,
    this.token,
    this.mediaProgress = const [],
  });
  bool get isAdmin => type == 'root' || type == 'admin';

  factory AbsUser.fromJson(Map j) => AbsUser(
        id: _s(j['id']),
        username: _s(j['username']),
        type: _s(j['type']),
        token: j['token']?.toString(),
        mediaProgress: ((j['mediaProgress'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MediaProgress.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class Library {
  final String id;
  final String name;
  final String mediaType;
  final int? numItems;
  Library({required this.id, required this.name, required this.mediaType, this.numItems});
  factory Library.fromJson(Map j) => Library(
        id: _s(j['id']),
        name: _s(j['name']),
        mediaType: _s(j['mediaType']),
        numItems: j['numItems'] == null ? null : toI(j['numItems']),
      );
}

class BookMeta {
  final String title;
  final String subtitle;
  final List<String> authors;
  final List<String> narrators;
  final List<String> series; // ["书名 #序号"]
  final String publishedYear;
  final String publisher;
  final String description;
  final List<String> genres;
  final String language;
  BookMeta({
    this.title = '',
    this.subtitle = '',
    this.authors = const [],
    this.narrators = const [],
    this.series = const [],
    this.publishedYear = '',
    this.publisher = '',
    this.description = '',
    this.genres = const [],
    this.language = '',
  });
  String get authorText => authors.isEmpty ? '未知作者' : authors.join(' / ');
  String get narratorText => narrators.join(' / ');
  String get seriesText => series.join(' · ');

  static List<String> _names(dynamic v) => ((v as List?) ?? const [])
      .map((e) => e is Map ? _s(e['name']) : _s(e))
      .where((e) => e.isNotEmpty)
      .toList();

  factory BookMeta.fromJson(Map j) {
    final seriesRaw = ((j['series'] as List?) ?? const [])
        .map((e) => e is Map ? '${_s(e['name'])}${e['sequence'] != null ? ' #${e['sequence']}' : ''}' : _s(e))
        .where((e) => e.isNotEmpty)
        .toList();
    return BookMeta(
      title: _s(j['title']),
      subtitle: _s(j['subtitle']),
      authors: _names(j['authors'] ?? j['authorName']),
      narrators: _names(j['narrators'] ?? j['narratorName']),
      series: seriesRaw,
      publishedYear: _s(j['publishedYear']),
      publisher: _s(j['publisher']),
      description: _s(j['description']),
      genres: _names(j['genres']),
      language: _s(j['language']),
    );
  }
}

/// 列表条目（minified）
class LibItem {
  final String id;
  final String ino;
  final String libraryId;
  final String mediaType;
  final double addedAt;
  final BookMeta meta;
  final double duration;
  final int numTracks;
  final double size;
  final bool isMissing;
  LibItem({
    required this.id,
    required this.ino,
    required this.libraryId,
    required this.mediaType,
    required this.addedAt,
    required this.meta,
    required this.duration,
    required this.numTracks,
    required this.size,
    required this.isMissing,
  });
  factory LibItem.fromJson(Map j) {
    final media = (j['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mj = (media['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LibItem(
      id: _s(j['id']),
      ino: _s(j['ino']),
      libraryId: _s(j['libraryId']),
      mediaType: _s(j['mediaType']),
      addedAt: toD(j['addedAt']),
      meta: BookMeta.fromJson(mj),
      duration: toD(media['duration']),
      numTracks: toI(media['numTracks'] ?? media['numAudioFiles']),
      size: toD(media['size']),
      isMissing: j['isMissing'] == true,
    );
  }
}

class Track {
  final int index;
  final String ino;
  final String title;
  final double duration;
  double startOffset;
  final String codec;
  final String mimeType;
  final String path; // strm 目标（MP 直链）或本地路径
  final String ext;
  String? contentUrl; // 会话返回

  Track({
    required this.index,
    this.ino = '',
    required this.title,
    required this.duration,
    this.startOffset = 0,
    this.codec = '',
    this.mimeType = '',
    this.path = '',
    this.ext = '',
    this.contentUrl,
  });

  double get end => startOffset + duration;

  factory Track.fromJson(Map j, {double? startOffset}) {
    final md = (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Track(
      index: toI(j['index']),
      ino: _s(j['ino']),
      title: prettyTrackTitle(_s(j['title'] ?? md['filename'] ?? '第${j['index']}章')),
      duration: toD(j['duration']),
      startOffset: startOffset ?? toD(j['startOffset']),
      codec: _s(j['codec']),
      mimeType: _s(j['mimeType']),
      path: _s(md['path']),
      ext: _s(md['ext']),
      contentUrl: j['contentUrl']?.toString(),
    );
  }
}

class Chapter {
  final int id;
  final double start;
  final double end;
  final String title;
  Chapter({required this.id, required this.start, required this.end, required this.title});
  factory Chapter.fromJson(Map j) => Chapter(id: toI(j['id']), start: toD(j['start']), end: toD(j['end']), title: _s(j['title']));
}

class BookDetail {
  final String id;
  final String libraryId;
  final BookMeta meta;
  final double duration;
  final double size;
  final List<Track> tracks;
  final List<Chapter> chapters;
  final String ebookFormat;
  BookDetail({
    required this.id,
    required this.libraryId,
    required this.meta,
    required this.duration,
    required this.size,
    required this.tracks,
    required this.chapters,
    this.ebookFormat = '',
  });
  factory BookDetail.fromJson(Map j) {
    final media = (j['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mj = (media['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawTracks = ((media['tracks'] as List?) ?? (media['audioFiles'] as List?) ?? const []);
    final tracks = <Track>[];
    double off = 0;
    for (final t in rawTracks) {
      if (t is! Map) continue;
      final tr = Track.fromJson(t.cast<String, dynamic>(), startOffset: off);
      off += tr.duration;
      tracks.add(tr);
    }
    return BookDetail(
      id: _s(j['id']),
      libraryId: _s(j['libraryId']),
      meta: BookMeta.fromJson(mj),
      duration: toD(media['duration']),
      size: toD(media['size']),
      tracks: tracks,
      chapters: ((media['chapters'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Chapter.fromJson(e.cast<String, dynamic>()))
          .toList(),
      ebookFormat: _s(mj['ebookFormat'] ?? media['ebookFormat']),
    );
  }
}

class PlaySession {
  final String id;
  final String libraryItemId;
  final String bookId;
  final String displayTitle;
  final String displayAuthor;
  final double duration;
  final int playMethod; // 0 direct, 1 transcode
  final List<Track> tracks;
  PlaySession({
    required this.id,
    required this.libraryItemId,
    required this.bookId,
    required this.displayTitle,
    required this.displayAuthor,
    required this.duration,
    required this.playMethod,
    required this.tracks,
  });
  bool get isTranscode => playMethod == 1;

  factory PlaySession.fromJson(Map j) {
    final rawTracks = ((j['audioTracks'] as List?) ?? const []);
    final tracks = <Track>[];
    double acc = 0;
    for (final t in rawTracks) {
      if (t is! Map) continue;
      final tr = Track.fromJson(t.cast<String, dynamic>(), startOffset: acc);
      acc += tr.duration;
      tracks.add(tr);
    }
    return PlaySession(
      id: _s(j['id']),
      libraryItemId: _s(j['libraryItemId']),
      bookId: _s(j['bookId']),
      displayTitle: _s(j['displayTitle']),
      displayAuthor: _s(j['displayAuthor']),
      duration: toD(j['duration']),
      playMethod: toI(j['playMethod']),
      tracks: tracks,
    );
  }
}

class MediaProgress {
  final String? libraryItemId;
  final String? mediaItemId;
  final double currentTime;
  final double duration;
  final double progress;
  final bool isFinished;
  final DateTime? updatedAt;
  final bool hideFromContinue;
  MediaProgress({
    this.libraryItemId,
    this.mediaItemId,
    this.currentTime = 0,
    this.duration = 0,
    this.progress = 0,
    this.isFinished = false,
    this.updatedAt,
    this.hideFromContinue = false,
  });
  factory MediaProgress.fromJson(Map j) => MediaProgress(
        libraryItemId: j['libraryItemId']?.toString(),
        mediaItemId: j['mediaItemId']?.toString(),
        currentTime: toD(j['currentTime']),
        duration: toD(j['duration']),
        progress: toD(j['progress']),
        isFinished: j['isFinished'] == true,
        updatedAt: DateTime.tryParse(_s(j['updatedAt'])),
        hideFromContinue: j['hideFromContinueListening'] == true,
      );
}

class ListeningStats {
  final double totalTime;
  final double today;
  final Map<String, double> days;
  ListeningStats({this.totalTime = 0, this.today = 0, this.days = const {}});
  double get last7 {
    final now = DateTime.now();
    double sum = 0;
    for (int i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      sum += days[key] ?? 0;
    }
    return sum;
  }
  int get streak {
    final now = DateTime.now();
    int n = 0;
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if ((days[key] ?? 0) > 60) {
        n++;
      } else if (i > 0) {
        break;
      }
    }
    return n;
  }
  factory ListeningStats.fromJson(Map j) {
    final days = <String, double>{};
    ((j['days'] as Map?) ?? const {}).forEach((k, v) => days[k.toString()] = toD(v));
    return ListeningStats(totalTime: toD(j['totalTime']), today: toD(j['today']), days: days);
  }
}

class Bookmark {
  final double time;
  final String title;
  final DateTime? createdAt;
  Bookmark({required this.time, this.title = '', this.createdAt});
  factory Bookmark.fromJson(Map j) => Bookmark(
        time: toD(j['time']),
        title: _s(j['title']),
        createdAt: DateTime.tryParse(_s(j['createdAt'])),
      );
}

class ServerStatus {
  final String serverVersion;
  final bool isInit;
  ServerStatus({this.serverVersion = '', this.isInit = false});
  factory ServerStatus.fromJson(Map j) => ServerStatus(
        serverVersion: _s(j['serverVersion']),
        isInit: j['isInit'] == true,
      );
}
