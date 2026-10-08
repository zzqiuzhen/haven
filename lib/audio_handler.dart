/// audio_service 音频后台服务适配（锁屏 / 通知 / 后台播放）
library;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'models.dart';
import 'player_engine.dart';

class HavenAudioHandler extends BaseAudioHandler with SeekHandler {
  HavenAudioHandler(this.engine) {
    engine.player.playbackEventStream.map(_transform).pipe(playbackState);
  }

  final PlayerEngine engine;

  PlaybackState _transform(PlaybackEvent e) {
    final playing = engine.player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (e.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: e.updatePosition,
      bufferedPosition: e.bufferedPosition,
      speed: engine.player.speed,
    );
  }

  /// 会话开始时更新整队章节（锁屏上一章/下一章）
  void reportQueue(List<Track> tracks, LibItem item, {Uri? artUri}) {
    final items = <MediaItem>[];
    for (final t in tracks) {
      items.add(MediaItem(
        id: '${item.id}:${t.index}',
        title: t.title,
        album: item.meta.title,
        artist: item.meta.authorText,
        duration: Duration(milliseconds: (t.duration * 1000).round()),
        artUri: artUri,
      ));
    }
    queue.add(items);
    if (tracks.isNotEmpty) updateIndex(engine.index, item, artUri: artUri);
  }

  void updateIndex(int index, LibItem item, {Uri? artUri}) {
    final tracks = engine.tracks;
    if (index < 0 || index >= tracks.length) return;
    final t = tracks[index];
    mediaItem.add(MediaItem(
      id: '${item.id}:${t.index}',
      title: t.title,
      album: item.meta.title,
      artist: item.meta.authorText,
      duration: Duration(milliseconds: (t.duration * 1000).round()),
      artUri: artUri,
    ));
  }

  @override
  Future<void> play() => engine.player.play();

  @override
  Future<void> pause() => engine.player.pause();

  @override
  Future<void> seek(Duration position) => engine.seekAbsolute(position.inMilliseconds / 1000.0);

  @override
  Future<void> skipToNext() => engine.nextTrack(userInitiated: true);

  @override
  Future<void> skipToPrevious() => engine.prevTrack();

  @override
  Future<void> skipToQueueItem(int index) => engine.playAt(index);

  @override
  Future<void> setSpeed(double speed) => engine.setSpeed(speed, persist: false);

  @override
  Future<void> stop() async {
    await engine.stopAndClose();
    await super.stop();
  }
}
