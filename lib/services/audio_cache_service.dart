import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'youtube_service.dart';

class AudioCacheService {
  AudioCacheService(this._youtube);

  static const _boxName = 'audio_cache';
  static const _cacheDirName = 'flux-audio-cache';
  static const _maxCacheBytes = 500 * 1024 * 1024;

  final YoutubeService _youtube;
  final Map<String, Future<void>> _activeDownloads = {};
  Box? _index;

  Future<void> init() async {
    _index = await Hive.openBox(_boxName);
    await _evictIfNeeded();
  }

  Future<String?> cachedPath(String trackId) async {
    final entry = _index?.get(trackId);
    if (entry is! Map) return null;
    final path = entry['path'] as String?;
    if (path == null || !await File(path).exists()) {
      await _index?.delete(trackId);
      return null;
    }
    return path;
  }

  Future<void> touch(String trackId) async {
    final entry = _index?.get(trackId);
    if (entry is! Map) return;
    await _index?.put(trackId, {
      ...Map<String, dynamic>.from(entry),
      'lastAccessed': DateTime.now().toIso8601String(),
    });
  }

  Future<Uri> playbackUri(Track track, {Stopwatch? sw}) async {
    final cached = await cachedPath(track.id);
    if (cached != null) {
      await touch(track.id);
      return Uri.file(cached);
    }

    final uri = await _youtube.audioUri(track, sw: sw);
    _cacheInBackground(track, uri);
    return uri;
  }

  Future<void> prefetch(Track track) async {
    if (await cachedPath(track.id) != null) return;
    if (_activeDownloads.containsKey(track.id)) {
      await _activeDownloads[track.id];
      return;
    }

    final download = _downloadTrack(track);
    _activeDownloads[track.id] = download;
    try {
      await download;
    } catch (_) {
      // Prefetch failures are non-fatal.
    } finally {
      _activeDownloads.remove(track.id);
    }
  }

  void prefetchTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      unawaited(prefetch(track));
    }
  }

  void _cacheInBackground(Track track, Uri uri) {
    if (_activeDownloads.containsKey(track.id)) return;
    final download = _downloadTrack(track, uri: uri);
    _activeDownloads[track.id] = download;
    download.whenComplete(() => _activeDownloads.remove(track.id));
  }

  Future<void> _downloadTrack(Track track, {Uri? uri}) async {
    if (await cachedPath(track.id) != null) return;

    final streamUri = uri ?? await _youtube.audioUri(track);
    final directory = await _cacheDirectory();
    final destination = File('${directory.path}/${track.id}.m4a');
    final temp = File('${destination.path}.part');

    try {
      await Dio().downloadUri(
        streamUri,
        temp.path,
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      if (await destination.exists()) await destination.delete();
      await temp.rename(destination.path);

      final sizeBytes = await destination.length();
      await _index?.put(track.id, {
        'path': destination.path,
        'sizeBytes': sizeBytes,
        'cachedAt': DateTime.now().toIso8601String(),
        'lastAccessed': DateTime.now().toIso8601String(),
      });
      await _evictIfNeeded();
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<Directory> _cacheDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/$_cacheDirName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _evictIfNeeded() async {
    final entries = _index?.keys
            .map((key) {
              final value = _index?.get(key);
              if (value is! Map) return null;
              return MapEntry(
                key as String,
                Map<String, dynamic>.from(value),
              );
            })
            .whereType<MapEntry<String, Map<String, dynamic>>>()
            .toList() ??
        [];

    entries.sort((a, b) {
      final aTime = DateTime.tryParse(a.value['lastAccessed'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b.value['lastAccessed'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });

    var totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + (entry.value['sizeBytes'] as int? ?? 0),
    );

    for (final entry in entries) {
      if (totalBytes <= _maxCacheBytes) break;
      final path = entry.value['path'] as String?;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          totalBytes -= await file.length();
          await file.delete();
        }
      }
      await _index?.delete(entry.key);
    }
  }
}
