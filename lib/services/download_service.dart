import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'youtube_service.dart';

class DownloadService {
  DownloadService(this._youtube);
  final YoutubeService _youtube;

  Future<Track> download(
    Track track, {
    void Function(double progress)? onProgress,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/flux-downloads');
    if (!await directory.exists()) await directory.create(recursive: true);
    final destination = File('${directory.path}/${track.id}.m4a');
    try {
      final uri = await _youtube.audioUri(track);
      await Dio().downloadUri(
        uri,
        destination.path,
        onReceiveProgress: (received, total) {
          onProgress?.call(total > 0 ? received / total : 0);
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      return track.copyWith(
        localPath: destination.path,
        addedAt: DateTime.now(),
      );
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<void> delete(Track track) async {
    final path = track.localPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
