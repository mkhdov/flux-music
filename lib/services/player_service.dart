import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

class PlayerService {
  PlayerService() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _trackCompleted.add(null);
      }
      _emit();
    });
    _player.positionStream.listen((_) => _emit());
    _player.durationStream.listen((_) => _emit());
  }

  final AudioPlayer _player = AudioPlayer();
  final _changes = StreamController<void>.broadcast();
  final _trackCompleted = StreamController<void>.broadcast();
  List<Track> _queue = [];
  int _index = 0;
  String? _loadedTrackId;

  Stream<void> get changes => _changes.stream;
  Stream<void> get trackCompleted => _trackCompleted.stream;
  List<Track> get queue => List.unmodifiable(_queue);
  Track? get current =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];
  String? get loadedTrackId => _loadedTrackId;
  bool get playing => _player.playing;
  ProcessingState get processingState => _player.processingState;
  bool get isBuffering =>
      processingState == ProcessingState.loading ||
      processingState == ProcessingState.buffering;
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

  Future<void> setQueue(List<Track> tracks, int initialIndex) async {
    _queue = List.of(tracks);
    _index = initialIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    _emit();
  }

  Future<void> playStream(Track track, Uri streamUri) async {
    await _player.setAudioSource(
      AudioSource.uri(streamUri, tag: _mediaItem(track)),
      initialPosition: Duration.zero,
    );
    _loadedTrackId = track.id;
    await _player.play();
    _emit();
  }

  Future<void> waitUntilReady() async {
    await _player.processingStateStream
        .firstWhere(
          (state) =>
              state == ProcessingState.ready ||
              state == ProcessingState.completed,
        )
        .timeout(const Duration(seconds: 30));
  }

  void updateIndex(int index) {
    _index = index.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    _emit();
  }

  Future<void> playResolved(Track track, Uri streamUri) async {
    _queue = [track];
    _index = 0;
    await playStream(track, streamUri);
  }

  Future<void> appendTrack(Track track) async {
    if (_queue.any((item) => item.id == track.id)) return;
    _queue.add(track);
    _emit();
  }

  void markTrackUnavailable(String trackId) {
    final idx = _queue.indexWhere((t) => t.id == trackId);
    if (idx != -1) {
      _queue[idx] = _queue[idx].copyWith(isUnavailable: true);
      _emit();
    }
  }

  Future<void> toggle() => playing ? _player.pause() : _player.play();

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
    
    if (_index == oldIndex) {
      _index = newIndex;
    } else if (oldIndex < _index && newIndex >= _index) {
      _index--;
    } else if (oldIndex > _index && newIndex <= _index) {
      _index++;
    }
    _emit();
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_index == index) {
      // Current track removed
      if (_queue.isEmpty) {
        await _player.stop();
        _index = 0;
      }
    } else if (index < _index) {
      _index--;
    }
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
