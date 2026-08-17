import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';
import 'direct_innertube_service.dart';
import 'piped_fallback_service.dart';
import 'ytdlp_service.dart';

class YoutubeService {
  YoutubeService()
    : _yt = YoutubeExplode(),
      _directInnertube = DirectInnertubeService(),
      _piped = PipedFallbackService(),
      _ytdlp = YtDlpService();
  final YoutubeExplode _yt;
  final DirectInnertubeService _directInnertube;
  final PipedFallbackService _piped;
  final YtDlpService _ytdlp;
  final Map<String, _CachedAudioStream> _audioCache = {};

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

  Future<Uri> audioUri(Track track) async {
    const maxRetries = 2; // 3 attempts total
    final fallbackErrors = <String>[];

    for (int i = 0; i <= maxRetries; i++) {
      fallbackErrors.clear();
      try {
        return (await _bestAudioStream(track)).url;
      } on YoutubeAudioException catch (e) {
        fallbackErrors.add('YouTube Explode:\n  ${e.message.replaceAll('\n', '\n  ')}');
      } catch (e) {
        fallbackErrors.add('YouTube Explode: $e');
      }

      // Tier 2: direct ANDROID_VR innertube call (bypasses library wrapper)
      try {
        final directUri = await _directInnertube.audioUri(track);
        if (directUri != null) return directUri;
        fallbackErrors.add('Direct Innertube: Returned null');
      } catch (e) {
        fallbackErrors.add('Direct Innertube: $e');
      }

      // Tier 3: Piped public API instances
      try {
        final pipedUri = await _piped.audioUri(track);
        if (pipedUri != null) return pipedUri;
        fallbackErrors.add('Piped: Returned null');
      } catch (e) {
        fallbackErrors.add('Piped: $e');
      }

      // Tier 4: yt-dlp subprocess (Linux/macOS/Windows desktop only)
      try {
        final ytdlpUri = await _ytdlp.audioUri(track);
        if (ytdlpUri != null) return ytdlpUri;
        fallbackErrors.add('yt-dlp: Not installed or returned null');
      } catch (e) {
        fallbackErrors.add('yt-dlp: $e');
      }

      if (i < maxRetries) {
        // Exponential backoff
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }

    final errorMessage = 'YouTube is temporarily limiting audio requests or blocked the request.\n\nDiagnostic Info:\n- ${fallbackErrors.join('\n- ')}';
    throw YoutubeAudioException(errorMessage);
  }

  Future<AudioOnlyStreamInfo> _bestAudioStream(Track track) async {
    final cached = _audioCache[track.id];
    if (cached != null &&
        DateTime.now().difference(cached.resolvedAt) <
            const Duration(minutes: 10)) {
      return cached.stream;
    }
    // Try multiple API clients in order of preference.
    // - androidVr: ANDROID_VR client — same as yt-dlp uses, no PO token needed
    // - androidSdkless: Android without sdk version, avoids PO token requirement
    // - ios: no signature deciphering needed
    // - tv / safari / mweb: additional fallbacks with different signatures
    // - default (empty): library default as last resort
    final clients = [
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.androidSdkless],
      [YoutubeApiClient.ios],
      [YoutubeApiClient.tv],
      [YoutubeApiClient.safari],
      [YoutubeApiClient.mweb],
      <YoutubeApiClient>[],  // library default
    ];

    final errors = <String>[];

    for (final ytClients in clients) {
      final clientName = ytClients.isEmpty ? 'default' : ytClients.first.toString();
      try {
        final manifest = ytClients.isEmpty
            ? await _yt.videos.streamsClient.getManifest(track.id)
            : await _yt.videos.streamsClient.getManifest(
                track.id,
                ytClients: ytClients,
              );
        if (manifest.audioOnly.isEmpty) {
          throw const YoutubeAudioException(
            'No audio-only stream is available for this track.',
          );
        }
        final stream = manifest.audioOnly.withHighestBitrate();
        _audioCache[track.id] = _CachedAudioStream(stream, DateTime.now());
        return stream;
      } on YoutubeAudioException catch (e) {
        errors.add('$clientName: ${e.message}');
      } on RequestLimitExceededException {
        errors.add('$clientName: Rate Limited (429)');
      } catch (e) {
        errors.add('$clientName: $e');
      }
    }

    throw YoutubeAudioException(
      'All YouTube clients failed:\n${errors.join('\n')}',
    );
  }

  void dispose() {
    _yt.close();
    _directInnertube.dispose();
    _piped.dispose();
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
  @override
  String toString() => message;
}
