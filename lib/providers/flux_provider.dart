import 'dart:async';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';

class FluxProvider extends ChangeNotifier {
  FluxProvider(this.storage, this.youtube, this.downloads, this.player) {
    _playerSubscription = player.changes.listen((_) => notifyListeners());
  }

  final StorageService storage;
  final YoutubeService youtube;
  final DownloadService downloads;
  final PlayerService player;
  late final StreamSubscription<void> _playerSubscription;
  List<Track> results = [];
  bool searching = false;
  String? searchError;
  String? downloadingId;
  String? actionError;
  DateTime? _sleepEndsAt;
  Timer? _sleepTimer;
  Timer? _sleepTicker;

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
    actionError = null;
    notifyListeners();
    try {
      final merged = storage.downloaded(track.id) ?? track;
      final uri = merged.isDownloaded
          ? Uri.file(merged.localPath!)
          : await youtube.audioUri(merged);
      await player.playResolved(merged, uri);
      await storage.addRecent(merged);
      notifyListeners();
      return true;
    } on YoutubeAudioException catch (error) {
      actionError = error.message;
    } catch (_) {
      actionError =
          'Flux could not start this audio-only stream. Please retry.';
    }
    notifyListeners();
    return false;
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
      final uri = merged.isDownloaded
          ? Uri.file(merged.localPath!)
          : await youtube.audioUri(merged);
      await player.appendResolved(merged, uri);
    } on YoutubeAudioException catch (error) {
      actionError = error.message;
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
    await _playerSubscription.cancel();
    await player.dispose();
    youtube.dispose();
    super.dispose();
  }
}
