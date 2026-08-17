import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_cache_service.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';

class FluxProvider extends ChangeNotifier {
  FluxProvider(
    this.storage,
    this.youtube,
    this.audioCache,
    this.downloads,
    this.player,
  ) {
    _playerSubscription = player.changes.listen((_) => _onPlayerChanged());
    _completedSubscription = player.trackCompleted.listen(
      (_) => _onTrackCompleted(),
    );
    _playbackErrorSubscription = player.playbackErrors.listen(_onPlaybackError);
  }

  final StorageService storage;
  final YoutubeService youtube;
  final AudioCacheService audioCache;
  final DownloadService downloads;
  final PlayerService player;
  late final StreamSubscription<void> _playerSubscription;
  late final StreamSubscription<void> _completedSubscription;
  late final StreamSubscription<PlayerException> _playbackErrorSubscription;
  List<Track> results = [];
  bool searching = false;
  String? searchError;
  String? downloadingId;
  String? loadingTrackId;
  String? actionError;
  DateTime? _sleepEndsAt;
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  int _switchGeneration = 0;
  String? _prefetchedQueueForTrackId;
  int? _pendingQueueIndex;
  String? _lastRetriedTrackId;
  bool _retryingPlayback = false;

  bool get isPlayButtonLoading =>
      loadingTrackId != null && player.loadedTrackId != loadingTrackId;

  ThemeMode get themeMode => switch (storage.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  List<Track> get favorites => storage.favorites;
  List<Track> get downloadsList => storage.downloads;
  List<Track> get recent => storage.recent;
  List<Playlist> get playlists => storage.playlists;
  Duration? get sleepRemaining => _sleepEndsAt == null
      ? null
      : _sleepEndsAt!.difference(DateTime.now()).isNegative
      ? Duration.zero
      : _sleepEndsAt!.difference(DateTime.now());

  void _onPlayerChanged() {
    final loading = loadingTrackId;
    if (loading != null &&
        player.loadedTrackId == loading &&
        !player.isBuffering) {
      loadingTrackId = null;
    }
    final current = player.current;
    if (current != null &&
        player.playing &&
        !player.isBuffering &&
        player.loadedTrackId == current.id &&
        _prefetchedQueueForTrackId != current.id) {
      _prefetchedQueueForTrackId = current.id;
      _prefetchQueueAfterPlaybackStarts();
    }
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    searching = true;
    searchError = null;
    notifyListeners();
    try {
      results = await youtube.search(query.trim());
      await storage.cacheTracks(results);
    } catch (error) {
      searchError =
          'YouTube search could not be completed. Check your connection and try again.';
    } finally {
      searching = false;
      notifyListeners();
    }
  }

  Future<bool> play(Track track, {List<Track>? queue}) async {
    final sw = Stopwatch()..start();
    final generation = ++_switchGeneration;
    _lastRetriedTrackId = null;

    loadingTrackId = track.id;
    actionError = null;
    notifyListeners();
    var started = false;
    try {
      final merged = storage.downloaded(track.id) ?? track;
      if (queue != null) {
        final index = queue.indexWhere((t) => t.id == track.id);
        await player.setQueue(queue, index == -1 ? 0 : index);
      } else {
        await player.setQueue([merged], 0);
      }

      final stream = await _playbackUri(merged, sw: sw);
      if (generation != _switchGeneration) return false;

      await player.playStream(
        merged,
        stream.url,
        headers: stream.headers,
        resolvedAt: stream.resolvedAt,
        queueIndex: player.queue.indexWhere((t) => t.id == track.id),
      );
      if (generation != _switchGeneration) return false;
      started = true;

      await storage.addRecent(merged);
      notifyListeners();
      return true;
    } on YoutubeAudioException catch (error) {
      if (generation != _switchGeneration) return false;
      actionError = error.message;
    } on PlayerException catch (error) {
      // ExoPlayer reports a rejected stream (e.g. HttpDataSource 403) through
      // the player error stream during playback, but a failure during the
      // initial load surfaces here, synchronously from setAudioSource. Route
      // both through the same fresh re-extraction fallback.
      if (generation != _switchGeneration) return false;
      started = true;
      await _onPlaybackError(error);
      return false;
    } catch (error) {
      if (generation != _switchGeneration) return false;
      actionError =
          'Flux could not start this audio-only stream. Please retry.';
    } finally {
      if (generation == _switchGeneration &&
          loadingTrackId == track.id &&
          !started) {
        loadingTrackId = null;
        notifyListeners();
      }
    }
    return false;
  }

  Future<void> _onTrackCompleted() async {
    if (player.loopMode == LoopMode.one) {
      await player.seek(Duration.zero);
      await player.toggle();
      return;
    }
    await next();
  }

  Future<void> next() async {
    if (player.queue.isEmpty) return;

    final currentId = player.current?.id;
    final currentIndex =
        _pendingQueueIndex ??
        (currentId == null
            ? -1
            : player.queue.indexWhere((t) => t.id == currentId));
    int nextIndex = currentIndex + 1;

    if (nextIndex >= player.queue.length) {
      if (player.loopMode == LoopMode.all) {
        nextIndex = 0;
      } else {
        return;
      }
    }

    if (nextIndex == player.queue.length - 1) {
      _autoFillQueue();
    }

    await _switchToQueueIndex(nextIndex);
  }

  Future<void> previous() async {
    if (player.queue.isEmpty) return;
    if (_pendingQueueIndex == null &&
        player.position > const Duration(seconds: 4)) {
      await player.seek(Duration.zero);
      return;
    }

    final currentId = player.current?.id;
    final currentIndex =
        _pendingQueueIndex ??
        (currentId == null
            ? -1
            : player.queue.indexWhere((t) => t.id == currentId));
    int prevIndex = currentIndex - 1;

    if (prevIndex < 0) {
      if (player.loopMode == LoopMode.all) {
        prevIndex = player.queue.length - 1;
      } else {
        prevIndex = 0;
      }
    }

    await _switchToQueueIndex(prevIndex);
  }

  Future<void> _switchToQueueIndex(int index) async {
    if (index < 0 || index >= player.queue.length) return;
    final track = player.queue[index];

    final generation = ++_switchGeneration;
    _lastRetriedTrackId = null;
    _pendingQueueIndex = index;
    loadingTrackId = track.id;
    actionError = null;
    notifyListeners();

    var started = false;
    try {
      final merged = storage.downloaded(track.id) ?? track;
      final stream = await _playbackUri(merged);
      if (generation != _switchGeneration) return;

      await player.playStream(
        merged,
        stream.url,
        headers: stream.headers,
        resolvedAt: stream.resolvedAt,
        queueIndex: index,
      );
      if (generation != _switchGeneration) return;
      started = true;
      _pendingQueueIndex = null;

      await storage.addRecent(merged);
      notifyListeners();
    } on YoutubeAudioException catch (error) {
      if (generation != _switchGeneration) return;
      actionError = error.message;
    } on PlayerException catch (error) {
      if (generation != _switchGeneration) return;
      started = true;
      await _onPlaybackError(error);
    } catch (error) {
      if (generation != _switchGeneration) return;
      actionError = 'Could not play this track. Please retry.';
    } finally {
      if (generation == _switchGeneration &&
          loadingTrackId == track.id &&
          !started) {
        loadingTrackId = null;
        if (_pendingQueueIndex == index) _pendingQueueIndex = null;
        notifyListeners();
      }
    }
  }

  /// Handles a playback failure reported by the native player.
  ///
  /// YouTube stream URLs are only valid for the client, IP, and moment they
  /// were resolved for, so a source error (typically a 403
  /// HttpDataSource$InvalidResponseCodeException) can mean the URL was fetched
  /// without the right headers, the resolving IP no longer matches, or the
  /// streaming layer blocked the request (bot detection).
  ///
  /// The failure is retried at most once, and only if the retry would issue a
  /// request that actually differs from the one that failed: the stream is
  /// re-extracted (the cached URL is dropped first) and the resulting URL is
  /// compared against the failed one by bound-stream identity — CDN host,
  /// itag, and the embedding IP recorded by googlevideo.
  Future<void> _onPlaybackError(PlayerException error) async {
    if (_retryingPlayback) return;
    await _logPlaybackFailureDiagnostics();
    _retryingPlayback = true;
    try {
      await _retryPlaybackAfterError();
    } finally {
      _retryingPlayback = false;
    }
  }

  /// Records the evidence needed to tell the three 403 causes apart: URL
  /// expiry, IP binding, and streaming-layer bot detection.
  Future<void> _logPlaybackFailureDiagnostics() async {
    final uri = player.lastStreamUri;
    final resolvedAt = player.lastResolvedAt;
    if (uri == null) return;

    final now = DateTime.now();
    final parameters = uri.queryParameters;
    final expiryEpoch = int.tryParse(parameters['expire'] ?? '');
    final expiresAt = expiryEpoch == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiryEpoch * 1000);
    final urlIp = parameters['ip'];
    final probeIp = await youtube.publicIp();

    developer.log(
      'playback error diagnostics '
      'uri=$uri '
      'urlIp=$urlIp probeIp=$probeIp '
      'ipBindingExonerated=${urlIp != null && urlIp == probeIp} '
      'itag=${parameters['itag']} '
      'connectivity=${(await Connectivity().checkConnectivity()).join(',')} '
      'resolvedAt=${resolvedAt?.toIso8601String() ?? '-'} '
      'errorAt=${now.toIso8601String()} '
      'resolveToErrorMs=${resolvedAt == null ? -1 : now.difference(resolvedAt).inMilliseconds} '
      'expiresAt=${expiresAt?.toIso8601String() ?? '-'} '
      'expiryRemainingMs=${expiresAt == null ? -1 : expiresAt.difference(now).inMilliseconds} '
      'expiredBeforeRequest=${expiresAt != null && expiresAt.isBefore(now)}',
      name: 'Flux.PlaybackRetry',
    );
  }

  Future<void> _retryPlaybackAfterError() async {
    final track = player.current;
    if (track == null) return;

    if (track.isDownloaded) {
      actionError = 'Could not play this track. Please retry.';
      loadingTrackId = null;
      notifyListeners();
      return;
    }

    if (_lastRetriedTrackId == track.id) {
      _lastRetriedTrackId = null;
      actionError =
          'This stream is unavailable right now. Please try again later.';
      loadingTrackId = null;
      notifyListeners();
      return;
    }

    // The request that just failed, before the cache is invalidated. Used to
    // verify that the retry transmits a different request rather than
    // recreating the failing one on a fresh ExoPlayer instance.
    final failedUri = player.lastStreamUri;
    final failedHeaders = player.lastStreamHeaders;

    _lastRetriedTrackId = track.id;
    loadingTrackId = track.id;
    notifyListeners();

    final generation = _switchGeneration;
    try {
      youtube.invalidateStream(track.id);
      final stream = await _playbackUri(track);
      if (generation != _switchGeneration) return;

      // Byte-comparing URLs here would defeat the guard: every extraction
      // mints fresh volatile query parameters, so two URLs for the same bound
      // stream never compare equal. Compare the bound-stream identity
      // instead: same CDN host + same itag + same embedding IP is the same
      // deterministic request, and replaying it would reproduce the 403.
      final urlChanged =
          failedUri == null || !sameBoundStream(failedUri, stream.url);
      final headersChanged = !mapEquals(failedHeaders, stream.headers);

      developer.log(
        'retry decision urlChanged=$urlChanged '
        'headersChanged=$headersChanged '
        'sameBoundStream=${!urlChanged} '
        'previousHost=${failedUri?.host ?? '-'} newHost=${stream.url.host} '
        'previousItag=${failedUri?.queryParameters['itag'] ?? '-'} '
        'newItag=${stream.url.queryParameters['itag']} '
        'previousIp=${failedUri?.queryParameters['ip'] ?? '-'} '
        'newIp=${stream.url.queryParameters['ip']} '
        'previousExpire=${failedUri?.queryParameters['expire'] ?? '-'} '
        'newExpire=${stream.url.queryParameters['expire']}',
        name: 'Flux.PlaybackRetry',
      );

      if (!urlChanged && !headersChanged) {
        // Re-extraction returned the identical bound stream: same CDN host,
        // same itag, same embedding IP. Replaying it against a new ExoPlayer
        // instance would reproduce the same 403, so surface the failure
        // instead of retrying.
        _lastRetriedTrackId = null;
        actionError =
            'This stream is unavailable right now. Please try again later.';
        loadingTrackId = null;
        notifyListeners();
        return;
      }

      final index = player.queue.indexWhere((item) => item.id == track.id);
      await player.playStream(
        track,
        stream.url,
        headers: stream.headers,
        resolvedAt: stream.resolvedAt,
        queueIndex: index == -1 ? null : index,
      );
      _lastRetriedTrackId = null;
      notifyListeners();
    } on YoutubeAudioException catch (e) {
      actionError = e.message;
      loadingTrackId = null;
      notifyListeners();
    } catch (_) {
      actionError = 'Could not play this track. Please retry.';
      loadingTrackId = null;
      notifyListeners();
    }
  }

  void _prefetchQueueAfterPlaybackStarts() {
    final currentId = player.current?.id;
    final currentIndex = currentId == null
        ? -1
        : player.queue.indexWhere((t) => t.id == currentId);
    if (currentIndex == -1) return;

    // Resolve every queued stream URL in parallel only after the current song
    // has started. This caches lightweight extraction metadata, not full audio.
    audioCache.prefetchTracks(
      player.queue.where(
        (track) =>
            track.id != currentId && storage.downloaded(track.id) == null,
      ),
    );
  }

  Future<ResolvedAudioStream> _playbackUri(Track track, {Stopwatch? sw}) async {
    if (track.isDownloaded) {
      return (
        url: Uri.file(track.localPath!),
        headers: const <String, String>{},
        resolvedAt: DateTime.now(),
      );
    }
    return audioCache.playbackUri(track, sw: sw);
  }

  bool _isFilling = false;
  Future<void> _autoFillQueue() async {
    if (_isFilling) return;
    _isFilling = true;
    try {
      final current = player.current;
      if (current != null) {
        final related = await youtube.getRelatedTracks(current.id);
        if (related.isNotEmpty) {
          for (final t in related.take(5)) {
            await storage.cacheTrack(t);
            if (!player.queue.any((q) => q.id == t.id)) {
              await player.appendTrack(t.copyWith(isSuggested: true));
            }
          }
          _prefetchedQueueForTrackId = null;
          _onPlayerChanged();
        }
      }
    } finally {
      _isFilling = false;
    }
  }

  Future<void> skipTo(int index) async {
    if (index < 0 || index >= player.queue.length) return;
    if (index ==
        (_pendingQueueIndex ??
            player.queue.indexWhere((t) => t.id == player.current?.id))) {
      return;
    }
    await _switchToQueueIndex(index);
  }

  Future<void> toggleFavorite(Track track) async {
    await storage.toggleFavorite(track);
    notifyListeners();
  }

  Future<void> download(Track track) async {
    if (storage.downloaded(track.id) != null) return;
    downloadingId = track.id;
    actionError = null;
    notifyListeners();
    try {
      final saved = await downloads.download(track);
      await storage.saveDownload(saved);
    } on YoutubeAudioException catch (error) {
      actionError = error.message;
    } catch (_) {
      actionError =
          'Flux could not download this audio-only stream. Please retry.';
    } finally {
      downloadingId = null;
      notifyListeners();
    }
  }

  Future<void> deleteDownload(Track track) async {
    await downloads.delete(track);
    await storage.removeDownload(track.id);
    notifyListeners();
  }

  Future<void> setTheme(String mode) async {
    await storage.setThemeMode(mode);
    notifyListeners();
  }

  String? get sessionCookie => storage.audioSessionCookie;
  bool get isSignedIn =>
      youtube.isSignedIn && (sessionCookie?.isNotEmpty ?? false);

  /// Registers a signed-in YouTube session cookie with the extraction and
  /// playback clients. See [YoutubeService.setSessionCookie].
  Future<void> setSessionCookie(String value) async {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    await storage.setAudioSessionCookie(normalized);
    youtube.setSessionCookie(normalized.isEmpty ? null : normalized);
    notifyListeners();
  }

  Future<void> clearSessionCookie() async {
    await storage.setAudioSessionCookie(null);
    youtube.setSessionCookie(null);
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    await storage.createPlaylist(name.trim());
    notifyListeners();
  }

  Future<void> renamePlaylist(Playlist playlist, String name) async {
    if (name.trim().isEmpty) return;
    await storage.renamePlaylist(playlist, name.trim());
    notifyListeners();
  }

  Future<void> deletePlaylist(Playlist playlist) async {
    await storage.deletePlaylist(playlist.id);
    notifyListeners();
  }

  Future<void> addToPlaylist(Playlist playlist, Track track) async {
    await storage.addTrackToPlaylist(playlist, track);
    notifyListeners();
  }

  Future<void> removeFromPlaylist(Playlist playlist, String trackId) async {
    await storage.removeTrackFromPlaylist(playlist, trackId);
    notifyListeners();
  }

  Future<void> addToQueue(Track track) async {
    actionError = null;
    notifyListeners();
    try {
      final merged = storage.downloaded(track.id) ?? track;
      await player.appendTrack(merged);
      if (player.playing && !player.isBuffering) {
        _prefetchedQueueForTrackId = null;
        _onPlayerChanged();
      }
    } catch (_) {
      actionError = 'This track could not be added to the queue. Please retry.';
    }
    notifyListeners();
  }

  void startSleepTimer(Duration duration) {
    cancelSleepTimer(silent: true);
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
    _sleepTimer = Timer(duration, _fadeAndPause);
    notifyListeners();
  }

  Future<void> _fadeAndPause() async {
    final original = player.volume;
    for (var i = 9; i >= 0; i--) {
      await player.setVolume(original * i / 10);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    await player.toggle();
    await player.setVolume(original);
    cancelSleepTimer(silent: true);
    notifyListeners();
  }

  void cancelSleepTimer({bool silent = false}) {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepEndsAt = null;
    if (!silent) notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    await _completedSubscription.cancel();
    await _playerSubscription.cancel();
    await _playbackErrorSubscription.cancel();
    await player.dispose();
    youtube.dispose();
    super.dispose();
  }
}
