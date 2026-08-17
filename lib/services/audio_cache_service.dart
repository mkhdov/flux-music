import 'dart:async';
import 'dart:collection';

import '../models/track.dart';
import 'youtube_service.dart';

/// Resolves queue items ahead of time without downloading their media files.
///
/// The returned YouTube stream URL is consumed progressively by just_audio's
/// native player, which requests byte ranges as playback needs them. Keeping
/// only the manifest/URL in YoutubeService's in-memory cache avoids downloading
/// complete songs simply because they appeared in a queue.
class AudioCacheService {
  AudioCacheService(this._youtube);

  final YoutubeService _youtube;
  static const _maxConcurrentPrefetches = 2;
  final Queue<Track> _pendingPrefetches = Queue<Track>();
  final Set<String> _scheduledTrackIds = <String>{};
  final Set<String> _activeTrackIds = <String>{};

  Future<void> init() async {}

  Future<Uri> playbackUri(Track track, {Stopwatch? sw}) =>
      _youtube.audioUri(track, sw: sw);

  Future<void> prefetch(Track track) => _youtube.audioUri(
    track,
    maxRetries: 0,
    clientTimeout: YoutubeService.extractionTimeout,
  );

  void prefetchTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      if (_scheduledTrackIds.add(track.id)) {
        _pendingPrefetches.add(track);
      }
    }
    _drainPrefetchQueue();
  }

  void _drainPrefetchQueue() {
    while (_activeTrackIds.length < _maxConcurrentPrefetches &&
        _pendingPrefetches.isNotEmpty) {
      final track = _pendingPrefetches.removeFirst();
      _activeTrackIds.add(track.id);
      unawaited(
        prefetch(track).then<void>((_) {}, onError: (_) {}).whenComplete(() {
          _activeTrackIds.remove(track.id);
          _scheduledTrackIds.remove(track.id);
          _drainPrefetchQueue();
        }),
      );
    }
  }
}
