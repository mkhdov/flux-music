import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class StorageService {
  static const _favorites = 'favorites';
  static const _downloads = 'downloads';
  static const _recent = 'recent';
  static const _playlists = 'playlists';
  static const _settings = 'settings';
  static const _catalog = 'catalog';

  Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(_favorites),
      Hive.openBox(_downloads),
      Hive.openBox(_recent),
      Hive.openBox(_playlists),
      Hive.openBox(_settings),
      Hive.openBox(_catalog),
    ]);
  }

  Box get _favoriteBox => Hive.box(_favorites);
  Box get _downloadBox => Hive.box(_downloads);
  Box get _recentBox => Hive.box(_recent);
  Box get _playlistBox => Hive.box(_playlists);
  Box get _settingsBox => Hive.box(_settings);
  Box get _catalogBox => Hive.box(_catalog);

  List<Track> _tracks(Box box) =>
      box.values.whereType<Map>().map(Track.fromMap).toList(growable: false);

  List<Track> get favorites => _tracks(_favoriteBox);
  List<Track> get downloads => _tracks(_downloadBox);
  List<Track> get recent => _tracks(_recentBox).reversed.toList();
  List<Playlist> get playlists => _playlistBox.values
      .whereType<Map>()
      .map(Playlist.fromMap)
      .toList(growable: false);
  String get themeMode =>
      _settingsBox.get('themeMode', defaultValue: 'system') as String;

  bool isFavorite(String id) => _favoriteBox.containsKey(id);
  Track? downloaded(String id) {
    final value = _downloadBox.get(id);
    return value is Map ? Track.fromMap(value) : null;
  }

  Track? trackById(String id) {
    final value = _catalogBox.get(id);
    return value is Map ? Track.fromMap(value) : null;
  }

  List<Track> tracksById(Iterable<String> ids) =>
      ids.map(trackById).whereType<Track>().toList(growable: false);

  Future<void> cacheTrack(Track track) =>
      _catalogBox.put(track.id, track.toMap());

  Future<void> cacheTracks(Iterable<Track> tracks) =>
      Future.wait(tracks.map(cacheTrack));

  Future<void> toggleFavorite(Track track) async {
    await cacheTrack(track);
    if (isFavorite(track.id)) {
      await _favoriteBox.delete(track.id);
    } else {
      await _favoriteBox.put(track.id, track.toMap());
    }
  }

  Future<void> saveDownload(Track track) async {
    await cacheTrack(track);
    await _downloadBox.put(track.id, track.toMap());
  }

  Future<void> removeDownload(String id) => _downloadBox.delete(id);

  Future<void> addRecent(Track track) async {
    await cacheTrack(track);
    await _recentBox.put(track.id, track.toMap());
    while (_recentBox.length > 30) {
      await _recentBox.delete(_recentBox.keys.first);
    }
  }

  Future<void> setThemeMode(String value) =>
      _settingsBox.put('themeMode', value);

  String? get audioSessionCookie =>
      _settingsBox.get('audioSessionCookie') as String?;

  Future<void> setAudioSessionCookie(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _settingsBox.delete('audioSessionCookie');
    } else {
      await _settingsBox.put('audioSessionCookie', value.trim());
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlist = Playlist(
      id: const Uuid().v4(),
      name: name,
      trackIds: const [],
    );
    await _playlistBox.put(playlist.id, playlist.toMap());
    return playlist;
  }

  Future<void> renamePlaylist(Playlist playlist, String name) =>
      _playlistBox.put(
        playlist.id,
        Playlist(
          id: playlist.id,
          name: name,
          trackIds: playlist.trackIds,
        ).toMap(),
      );
  Future<void> deletePlaylist(String id) => _playlistBox.delete(id);

  Future<void> addTrackToPlaylist(Playlist playlist, Track track) async {
    if (playlist.trackIds.contains(track.id)) return;
    await cacheTrack(track);
    await _playlistBox.put(
      playlist.id,
      Playlist(
        id: playlist.id,
        name: playlist.name,
        trackIds: [...playlist.trackIds, track.id],
      ).toMap(),
    );
  }

  Future<void> removeTrackFromPlaylist(
    Playlist playlist,
    String trackId,
  ) async {
    await _playlistBox.put(
      playlist.id,
      Playlist(
        id: playlist.id,
        name: playlist.name,
        trackIds: playlist.trackIds.where((id) => id != trackId).toList(),
      ).toMap(),
    );
  }
}
