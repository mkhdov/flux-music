import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A/B test for the client-type switch: resolves the same track fresh with
/// the ANDROID extraction client (the same one Flux uses) for each header
/// variant, then issues HEAD and GET requests the way the native player
/// would, so a googlevideo 403 reproduces inside this harness.
///
/// Usage: dart run test_client_switch.dart [videoId] [opt:cookieHeader]
Future<void> main(List<String> args) async {
  final videoId = args.isNotEmpty ? args.first : 'dQw4w9WgXcQ';
  final cookie = args.length > 1 ? args[1] : null;

  final oldHeaders = Map<String, String>.of(YoutubeHttpClient.defaultHeaders);
  final newHeaders = Map<String, String>.of(YoutubeHttpClient.defaultHeaders)
    ..['user-agent'] = _androidUserAgent();
  if (cookie != null) {
    oldHeaders['cookie'] = cookie;
    newHeaders['cookie'] = cookie;
  }

  for (final (label, headers) in [
    ('old: Chrome desktop UA (pre-fix playback headers)', oldHeaders),
    ('new: Android UA (post-fix playback headers)', newHeaders),
  ]) {
    final stream = await _resolve(videoId);
    print('=== $label');
    print('  url ip=${stream.url.queryParameters['ip']} '
        'itag=${stream.url.queryParameters['itag']}');
    for (final method in ['HEAD', 'GET']) {
      final status = await _fetch(method, stream.url, headers);
      print('  $method -> $status '
          '(ua=${headers['user-agent'] ?? '-'}'
          '${cookie == null ? '' : ' cookie=<signed-in>'})');
    }
  }
}

/// Mirrors Flux's extraction: androidSdkless (clientName ANDROID), no watch
/// page, top audio-only stream.
Future<AudioOnlyStreamInfo> _resolve(String videoId) async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: const [YoutubeApiClient.androidSdkless],
      requireWatchPage: false,
    );
    if (manifest.audioOnly.isEmpty) {
      throw StateError('no audio-only stream');
    }
    return manifest.audioOnly.withHighestBitrate();
  } finally {
    yt.close();
  }
}

/// The ANDROID client's user agent, exactly as Flux derives it for its
/// playback headers.
String _androidUserAgent() =>
    YoutubeApiClient.androidSdkless.payload['context']!['client']!['userAgent']
        as String;

Future<int> _fetch(String method, Uri url, Map<String, String> headers) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .openUrl(method, url)
        .timeout(const Duration(seconds: 15));
    headers.forEach(request.headers.set);
    final response = await request
        .close()
        .timeout(const Duration(seconds: 15));
    return response.statusCode;
  } on Exception {
    return -1;
  } finally {
    client.close(force: true);
  }
}