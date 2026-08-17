import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'youtube_service.dart';

class PlayerService {
  PlayerService(this._youtube) {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        final trackId = _loadedTrackId;
        if (trackId != null && _completedTrackId != trackId) {
          _completedTrackId = trackId;
          _trackCompleted.add(null);
        }
      } else {
        _completedTrackId = null;
      }
      _emit();
    });
    _player.positionStream.listen((_) => _emit());
    _player.durationStream.listen((_) => _emit());
    _player.errorStream.listen((error) {
      _logPlaybackRequestFailure();
      _playbackErrors.add(error);
      _emit();
    });
  }

  final YoutubeService _youtube;
  final AudioPlayer _player = AudioPlayer();
  final _changes = StreamController<void>.broadcast();
  final _trackCompleted = StreamController<void>.broadcast();
  final _playbackErrors = StreamController<PlayerException>.broadcast();
  List<Track> _queue = [];
  int _index = 0;
  String? _loadedTrackId;
  String? _completedTrackId;
  Uri? _lastStreamUri;
  Map<String, String>? _lastStreamHeaders;
  DateTime? _streamResolvedAt;

  void _logPlaybackRequestFailure() {
    final uri = _lastStreamUri;
    final resolvedAt = _streamResolvedAt;
    if (uri == null) return;
    final now = DateTime.now();
    final expiryEpoch = int.tryParse(uri.queryParameters['expire'] ?? '');
    final expiresAt = expiryEpoch == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiryEpoch * 1000);

    developer.log(
      'stream request failed '
      'urlIp=${uri.queryParameters['ip']} '
      'itag=${uri.queryParameters['itag']} '
      'resolvedAt=${resolvedAt?.toIso8601String() ?? '-'} '
      'failedAt=${now.toIso8601String()} '
      'resolveToFailureMs=${resolvedAt == null ? -1 : now.difference(resolvedAt).inMilliseconds} '
      'expiresAt=${expiresAt?.toIso8601String() ?? '-'} '
      'expiryRemainingMs=${expiresAt == null ? -1 : expiresAt.difference(now).inMilliseconds} '
      'expiredBeforeRequest=${expiresAt != null && expiresAt.isBefore(now)}',
      name: 'Flux.Playback',
    );
  }

  Stream<void> get changes => _changes.stream;
  Stream<void> get trackCompleted => _trackCompleted.stream;
  Stream<PlayerException> get playbackErrors => _playbackErrors.stream;
  List<Track> get queue => List.unmodifiable(_queue);
  Track? get current =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];
  String? get loadedTrackId => _loadedTrackId;

  /// The stream URI of the most recent source handed to the native player.
  ///
  /// Kept so a playback error retry can detect that a re-extracted URL is
  /// byte-identical to the one that just failed and avoid replaying the same
  /// failing request against a fresh ExoPlayer instance.
  Uri? get lastStreamUri => _lastStreamUri;

  /// The headers sent with [lastStreamUri].
  Map<String, String>? get lastStreamHeaders => _lastStreamHeaders;

  /// The moment the URL in [lastStreamUri] was resolved by
  /// [YoutubeService.audioUri]. The gap between this and a playback failure
  /// decides whether the URL could have expired between resolving and playing.
  DateTime? get lastResolvedAt => _streamResolvedAt;
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

  /// Starts playback of a resolved stream URL.
  ///
  /// [headers] must carry the headers that were used when the URL was
  /// resolved: googlevideo rejects the stream when it is fetched by the
  /// native player without them. When omitted, today's [YoutubeService]
  /// [YoutubeService.playbackHeaders] are used.
  ///
  /// [resolvedAt] is the moment [streamUri] was resolved; it enables
  /// diagnosing whether the URL expired in the gap between resolving and the
  /// native player's first request for it.
  Future<void> playStream(
    Track track,
    Uri streamUri, {
    Map<String, String>? headers,
    int? queueIndex,
    DateTime? resolvedAt,
  }) async {
    final isRemote = streamUri.scheme == 'http' || streamUri.scheme == 'https';
    final effectiveHeaders = isRemote
        ? (headers ?? _youtube.playbackHeaders)
        : null;

    developer.log(
      'ExoPlayer request uri=$streamUri '
      'headers=${formatHeaders(effectiveHeaders)}',
      name: 'Flux.Playback',
    );

    _lastStreamUri = streamUri;
    _lastStreamHeaders = effectiveHeaders;
    _streamResolvedAt = resolvedAt;

    await _player.setAudioSource(
      AudioSource.uri(
        streamUri,
        headers: effectiveHeaders,
        tag: _mediaItem(track),
      ),
      initialPosition: Duration.zero,
    );
    _loadedTrackId = track.id;
    _completedTrackId = null;
    if (queueIndex != null) {
      _index = queueIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    }
    _emit();
    await _player.play();
    final resolvedAtForLog = _streamResolvedAt;
    if (resolvedAtForLog != null) {
      developer.log(
        'playback request began '
        'ageMs=${DateTime.now().difference(resolvedAtForLog).inMilliseconds}',
        name: 'Flux.Playback',
      );
    }
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
    await _trackCompleted.close();
    await _playbackErrors.close();
    await _player.dispose();
  }
}
