import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';

class YoutubeService {
  YoutubeService() : _yt = YoutubeExplode();
  static const extractionTimeout = Duration(seconds: 30);
  final YoutubeExplode _yt;
  final Map<String, _CachedAudioStream> _audioCache = {};
  final Map<String, Future<AudioOnlyStreamInfo>> _activeExtractions = {};

  static bool isUnavailableError(Object error) {
    if (error is YoutubeAudioException && error.isUnavailable) return true;
    final message = error.toString().toLowerCase();
    return message.contains('videounavailableexception') ||
        message.contains('video is unavailable') ||
        message.contains('sign in to confirm') ||
        message.contains('sign in to prove') ||
        message.contains('not a bot') ||
        message.contains('bot detection') ||
        message.contains('403') ||
        message.contains('429');
  }

  Future<List<Track>> search(String query) async {
    final results = await _yt.search.search(query);
    return results
        .where((video) => !video.isLive && video.duration != null)
        .map(
          (video) => Track(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnailUrl: video.thumbnails.maxResUrl,
            webUrl: video.url,
            durationSeconds: video.duration!.inSeconds,
          ),
        )
        .toList();
  }

  Future<Uri> audioUri(
    Track track, {
    Stopwatch? sw,
    int maxRetries = 0,
    Duration clientTimeout = extractionTimeout,
  }) async {
    sw ??= Stopwatch()..start();
    // Do not immediately repeat a request when YouTube is rate limiting it.
    final fallbackErrors = <String>[];

    for (int i = 0; i <= maxRetries; i++) {
      fallbackErrors.clear();
      try {
        final stream = await _bestAudioStream(
          track,
          sw: sw,
          clientTimeout: clientTimeout,
        );
        print(
          'Diagnostic: [4] n-parameter decipher starts (if needed) at ${sw.elapsedMilliseconds}ms',
        );
        final url = stream.url;
        print(
          'Diagnostic: [5] Final stream URL obtained at ${sw.elapsedMilliseconds}ms',
        );
        return url;
      } on YoutubeAudioException catch (e) {
        if (isUnavailableError(e)) {
          print(
            'Diagnostic: Bot detection triggered for ${track.title}, aborting retries.',
          );
          throw YoutubeAudioException(
            'Unavailable: Video is unavailable or YouTube blocked this track (Bot detection). Sign-in may be required.',
          );
        }
        fallbackErrors.add(
          'Attempt ${i + 1} - YouTube Explode:\n  ${e.message.replaceAll('\n', '\n  ')}',
        );
      } catch (e) {
        if (isUnavailableError(e)) {
          print(
            'Diagnostic: Bot detection triggered for ${track.title}, aborting retries.',
          );
          throw YoutubeAudioException(
            'Unavailable: Video is unavailable or YouTube blocked this track (Bot detection). Sign-in may be required.',
          );
        }
        fallbackErrors.add('Attempt ${i + 1} - YouTube Explode: $e');
      }

      if (i < maxRetries) {
        final backoffDelay = const Duration(seconds: 2);
        print(
          'Diagnostic: [Fallback] Retry ${i + 1} failed. Waiting ${backoffDelay.inSeconds}s before next attempt...',
        );
        await Future.delayed(backoffDelay);
      }
    }

    final errorMessage =
        'YouTube is temporarily limiting audio requests or blocked the request. (403/429)\n\nDiagnostic Info:\n- ${fallbackErrors.join('\n- ')}';
    throw YoutubeAudioException(errorMessage);
  }

  Future<AudioOnlyStreamInfo> _bestAudioStream(
    Track track, {
    Stopwatch? sw,
    Duration clientTimeout = extractionTimeout,
  }) async {
    sw ??= Stopwatch()..start();
    final cached = _audioCache[track.id];
    if (cached != null &&
        DateTime.now().difference(cached.resolvedAt) <
            const Duration(hours: 2)) {
      return cached.stream;
    }

    if (_activeExtractions.containsKey(track.id)) {
      print('Diagnostic: Joining existing extraction for ${track.title}');
      return await _activeExtractions[track.id]!;
    }

    final extractionFuture = _performParallelExtraction(
      track,
      sw,
      clientTimeout: clientTimeout,
    );
    _activeExtractions[track.id] = extractionFuture;

    try {
      final stream = await extractionFuture;
      _audioCache[track.id] = _CachedAudioStream(stream, DateTime.now());
      return stream;
    } finally {
      _activeExtractions.remove(track.id);
    }
  }

  Future<AudioOnlyStreamInfo> _performParallelExtraction(
    Track track,
    Stopwatch sw, {
    required Duration clientTimeout,
  }) async {
    // The extraction future remains synchronized per track, but clients are
    // attempted in sequence. The earlier parallel fan-out sent three requests
    // per queue item at once, which amplified bot-detection/rate-limit events.
    final clients = [
      [YoutubeApiClient.ios],
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.androidSdkless],
    ];
    final errors = <String>[];
    StreamManifest? manifest;

    for (final ytClients in clients) {
      final clientName = ytClients.first.toString();
      print(
        'Diagnostic: [2] Extraction request sent for ${track.title} using $clientName at ${sw.elapsedMilliseconds}ms',
      );
      try {
        manifest = await _yt.videos.streamsClient
            .getManifest(track.id, ytClients: ytClients)
            .timeout(clientTimeout);
        print(
          'Diagnostic: [3] Player response received for ${track.title} via $clientName at ${sw.elapsedMilliseconds}ms',
        );
        break;
      } catch (error) {
        if (isUnavailableError(error)) {
          print(
            'Diagnostic: Bot detection explicitly hit on client $clientName for ${track.id} (${track.title})',
          );
          throw const YoutubeAudioException(
            'Unavailable: Video is unavailable or sign in to confirm you\'re not a bot',
          );
        }
        print(
          'Diagnostic: [2] Extraction failed for $clientName with Error: $error',
        );
        errors.add('$clientName: $error');
      }
    }

    if (manifest == null) {
      throw YoutubeAudioException(
        'All YouTube clients failed:\n${errors.join('\n')}',
      );
    }

    if (manifest.audioOnly.isEmpty) {
      throw const YoutubeAudioException(
        'Unavailable: No audio-only stream is available for this track.',
      );
    }

    AudioOnlyStreamInfo? stream;
    final connectivity = await Connectivity().checkConnectivity();
    final isWeakConnection =
        connectivity.contains(ConnectivityResult.mobile) ||
        connectivity.contains(ConnectivityResult.bluetooth);

    if (isWeakConnection) {
      final sorted = manifest.audioOnly.sortByBitrate();
      stream = sorted.first;
    } else {
      try {
        stream = manifest.audioOnly.firstWhere((s) => s.tag == 140);
      } catch (_) {}
      if (stream == null) {
        try {
          stream = manifest.audioOnly.firstWhere((s) => s.tag == 251);
        } catch (_) {}
      }
      stream ??= manifest.audioOnly.withHighestBitrate();
    }

    return stream;
  }

  Future<void> prefetch(Track track) async {
    try {
      await audioUri(track);
    } catch (_) {
      // Ignore errors for prefetching
    }
  }

  void prefetchTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      prefetch(track);
    }
  }

  Future<List<Track>> getRelatedTracks(String videoId) async {
    try {
      final video = await _yt.videos.get(VideoId(videoId));
      final related = await _yt.videos.getRelatedVideos(video);
      if (related == null) return [];
      return related
          .where((v) => !v.isLive && v.duration != null)
          .map(
            (v) => Track(
              id: v.id.value,
              title: v.title,
              artist: v.author,
              thumbnailUrl: v.thumbnails.maxResUrl,
              webUrl: v.url,
              durationSeconds: v.duration!.inSeconds,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _yt.close();
  }
}

class _CachedAudioStream {
  const _CachedAudioStream(this.stream, this.resolvedAt);
  final AudioOnlyStreamInfo stream;
  final DateTime resolvedAt;
}

class YoutubeAudioException implements Exception {
  const YoutubeAudioException(this.message);
  final String message;
  bool get isUnavailable => message.startsWith('Unavailable:');
  @override
  String toString() => message;
}
