import 'dart:convert';
import 'dart:io';

import '../models/track.dart';

/// Last-resort audio URL extractor using the locally installed `yt-dlp` binary.
///
/// `yt-dlp` uses the ANDROID_VR client (and other clients) with sophisticated
/// bypass logic and stays up-to-date with YouTube's anti-bot changes.
/// It works even when all API-level approaches are rate-limited.
class YtDlpService {
  /// Known locations for the yt-dlp binary, tried in order.
  static const _candidates = [
    'yt-dlp',                              // if it's on PATH
    '/home/maxvpire/.local/bin/yt-dlp',   // pip user install
    '/usr/local/bin/yt-dlp',              // system pip install
    '/usr/bin/yt-dlp',                    // distro package
  ];

  /// Returns an audio-only [Uri] for the given [track], or `null` if yt-dlp
  /// is not installed or extraction fails.
  Future<Uri?> audioUri(Track track) async {
    final binary = await _findBinary();
    if (binary == null) return null;

    try {
      final result = await Process.run(
        binary,
        [
          '--no-warnings',
          '--quiet',
          '--no-playlist',
          '--get-url',
          '--format', 'bestaudio[ext=m4a]/bestaudio',
          'https://www.youtube.com/watch?v=${track.id}',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        throw Exception('yt-dlp exited with code ${result.exitCode}:\n${result.stderr}');
      }

      final url = (result.stdout as String).trim().split('\n').first.trim();
      if (url.isEmpty || !url.startsWith('http')) {
        throw Exception('yt-dlp returned invalid url: $url');
      }

      return Uri.tryParse(url);
    } catch (e) {
      if (e is Exception && e.toString().contains('yt-dlp')) rethrow;
      throw Exception('yt-dlp execution failed: $e');
    }
  }

  Future<String?> _findBinary() async {
    for (final path in _candidates) {
      try {
        final result = await Process.run(path, ['--version']).timeout(
          const Duration(seconds: 3),
        );
        if (result.exitCode == 0) return path;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
