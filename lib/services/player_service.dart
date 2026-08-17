import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

class PlayerService {
  PlayerService() {
    _player.playerStateStream.listen((_) => _emit());
    _player.positionStream.listen((_) => _emit());
    _player.durationStream.listen((_) => _emit());
    _player.currentIndexStream.listen((index) {
      if (index != null && index < _queue.length) _index = index;
      _emit();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final _changes = StreamController<void>.broadcast();
  List<Track> _queue = [];
  int _index = 0;

  Stream<void> get changes => _changes.stream;
  List<Track> get queue => List.unmodifiable(_queue);
  Track? get current =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration get duration =>
      _player.duration ?? Duration(seconds: current?.durationSeconds ?? 0);
  double get volume => _player.volume;
  double get speed => _player.speed;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  MediaItem _mediaItem(Track track) => MediaItem(
    id: track.webUrl,
    title: track.title,
    artist: track.artist,
    duration: Duration(seconds: track.durationSeconds),
    artUri: track.thumbnailUrl.isEmpty
        ? null
        : Uri.tryParse(track.thumbnailUrl),
  );

  Future<void> playResolved(Track track, Uri streamUri) async {
    _queue = [track];
    _index = 0;
    await _player.setAudioSources(
      [AudioSource.uri(streamUri, tag: _mediaItem(track))],
      initialIndex: 0,
      initialPosition: Duration.zero,
    );
    await _player.play();
    _emit();
  }

  Future<void> appendResolved(Track track, Uri streamUri) async {
    if (_queue.any((item) => item.id == track.id)) return;
    _queue.add(track);
    await _player.addAudioSource(
      AudioSource.uri(streamUri, tag: _mediaItem(track)),
    );
    _emit();
  }

  Future<void> toggle() => playing ? _player.pause() : _player.play();
  Future<void> next() => _player.seekToNext();
  Future<void> previous() async {
    if (position > const Duration(seconds: 4)) {
      await seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(Duration value) => _player.seek(value);
  Future<void> skipTo(int index) => _player.seek(Duration.zero, index: index);
  Future<void> setVolume(double value) => _player.setVolume(value.clamp(0, 1));
  Future<void> setSpeed(double value) => _player.setSpeed(value);
  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!shuffleEnabled);
    if (!shuffleEnabled) await _player.shuffle();
    _emit();
  }

  Future<void> cycleRepeat() async {
    final next = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
    _emit();
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);
    await _player.moveAudioSource(oldIndex, newIndex);
    _emit();
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await _player.removeAudioSourceAt(index);
    if (_index >= _queue.length) {
      _index = (_queue.length - 1).clamp(0, _queue.length);
    }
    _emit();
  }

  Future<void> dispose() async {
    await _changes.close();
    await _player.dispose();
  }
}
