import 'dart:async';

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
    _completedSubscription = player.trackCompleted.listen((_) => _onTrackCompleted());
  }

  final StorageService storage;
  final YoutubeService youtube;
  final AudioCacheService audioCache;
  final DownloadService downloads;
  final PlayerService player;
  late final StreamSubscription<void> _playerSubscription;
  late final StreamSubscription<void> _completedSubscription;
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

  bool get isNavigating => loadingTrackId != null;

  bool get isPlayButtonLoading =>
      loadingTrackId != null &&
      (player.loadedTrackId != loadingTrackId || player.isBuffering);

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
    if (track.isUnavailable) return false;
    final sw = Stopwatch()..start();
    final generation = ++_switchGeneration;

    loadingTrackId = track.id;
    actionError = null;
    notifyListeners();
    try {
      final merged = storage.downloaded(track.id) ?? track;
      if (queue != null) {
        final index = queue.indexWhere((t) => t.id == track.id);
        await player.setQueue(queue, index == -1 ? 0 : index);
      } else {
        await player.setQueue([merged], 0);
      }

      final uri = await _playbackUri(merged, sw: sw);
      if (generation != _switchGeneration) return false;

      await player.playStream(merged, uri);
      if (generation != _switchGeneration) return false;

      await storage.addRecent(merged);
      _prefetchAdjacent();
      notifyListeners();
      return true;
    } on YoutubeAudioException catch (error) {
      if (generation != _switchGeneration) return false;
      if (error.message.startsWith('Unavailable:')) {
        player.markTrackUnavailable(track.id);
      }
      actionError = error.message;
    } catch (_) {
      if (generation != _switchGeneration) return false;
      actionError =
          'Flux could not start this audio-only stream. Please retry.';
    } finally {
      if (generation == _switchGeneration &&
          loadingTrackId == track.id &&
          player.loadedTrackId != track.id) {
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
    if (player.queue.isEmpty || isNavigating) return;

    final currentId = player.current?.id;
    final currentIndex = currentId == null
        ? -1
        : player.queue.indexWhere((t) => t.id == currentId);
    int nextIndex = currentIndex + 1;

    while (nextIndex < player.queue.length &&
        player.queue[nextIndex].isUnavailable) {
      nextIndex++;
    }

    if (nextIndex >= player.queue.length) {
      if (player.loopMode == LoopMode.all) {
        nextIndex = 0;
        while (nextIndex < player.queue.length &&
            player.queue[nextIndex].isUnavailable) {
          nextIndex++;
        }
        if (nextIndex >= player.queue.length) return;
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
    if (player.queue.isEmpty || isNavigating) return;
    if (player.position > const Duration(seconds: 4)) {
      await player.seek(Duration.zero);
      return;
    }

    final currentId = player.current?.id;
    final currentIndex = currentId == null
        ? -1
        : player.queue.indexWhere((t) => t.id == currentId);
    int prevIndex = currentIndex - 1;

    while (prevIndex >= 0 && player.queue[prevIndex].isUnavailable) {
      prevIndex--;
    }

    if (prevIndex < 0) {
      if (player.loopMode == LoopMode.all) {
        prevIndex = player.queue.length - 1;
        while (prevIndex >= 0 && player.queue[prevIndex].isUnavailable) {
          prevIndex--;
        }
        if (prevIndex < 0) return;
      } else {
        prevIndex = 0;
        if (player.queue.isNotEmpty && player.queue[0].isUnavailable) return;
      }
    }

    await _switchToQueueIndex(prevIndex);
  }

  Future<void> _switchToQueueIndex(int index) async {
    if (index < 0 || index >= player.queue.length) return;
    final track = player.queue[index];
    if (track.isUnavailable) return;

    final generation = ++_switchGeneration;
    loadingTrackId = track.id;
    actionError = null;
    notifyListeners();

    try {
      final merged = storage.downloaded(track.id) ?? track;
      final uri = await _playbackUri(merged);
      if (generation != _switchGeneration) return;

      player.updateIndex(index);
      await player.playStream(merged, uri);
      if (generation != _switchGeneration) return;

      await storage.addRecent(merged);
      _prefetchAdjacent();
      notifyListeners();
    } on YoutubeAudioException catch (error) {
      if (generation != _switchGeneration) return;
      if (error.message.startsWith('Unavailable:')) {
        player.markTrackUnavailable(track.id);
        loadingTrackId = null;
        notifyListeners();
        WidgetsBinding.instance.addPostFrameCallback((_) => next());
      } else {
        actionError = error.message;
      }
    } catch (_) {
      if (generation != _switchGeneration) return;
      actionError = 'Could not play this track. Please retry.';
    } finally {
      if (generation == _switchGeneration &&
          loadingTrackId == track.id &&
          player.loadedTrackId != track.id) {
        loadingTrackId = null;
        notifyListeners();
      }
    }
  }

  void _prefetchAdjacent() {
    final currentId = player.current?.id;
    final currentIndex = currentId == null
        ? -1
        : player.queue.indexWhere((t) => t.id == currentId);
    if (currentIndex == -1) return;

    final toPrefetch = <Track>[];
    for (final offset in [-2, -1, 1, 2]) {
      final idx = currentIndex + offset;
      if (idx >= 0 && idx < player.queue.length) {
        final t = player.queue[idx];
        if (!t.isUnavailable && storage.downloaded(t.id) == null) {
          toPrefetch.add(t);
        }
      }
    }
    audioCache.prefetchTracks(toPrefetch);
  }

  Future<Uri> _playbackUri(Track track, {Stopwatch? sw}) async {
    if (track.isDownloaded) return Uri.file(track.localPath!);
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
            if (!player.queue.any((q) => q.id == t.id)) {
              await player.appendTrack(t.copyWith(isSuggested: true));
            }
          }
          _prefetchAdjacent();
        }
      }
    } finally {
      _isFilling = false;
    }
  }

  Future<void> skipTo(int index) async {
    if (index < 0 || index >= player.queue.length || isNavigating) return;
    if (index == player.queue.indexWhere((t) => t.id == player.current?.id)) {
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
      if (error.message.startsWith('Unavailable:')) {
        player.markTrackUnavailable(track.id);
      }
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
      _prefetchAdjacent();
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
    await player.dispose();
    youtube.dispose();
    super.dispose();
  }
}
