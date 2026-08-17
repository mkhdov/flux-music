import 'package:dio/dio.dart';

import '../models/track.dart';

/// Directly calls YouTube's Innertube API using the ANDROID_VR client.
///
/// The ANDROID_VR client (Quest 3) does NOT require:
///   - PoToken / visitor_data
///   - Signature deciphering (streams have plain direct URLs)
///
/// This works even when youtube_explode_dart's wrapper adds headers that
/// trigger YouTube's bot-detection and the library-level clients all fail.
class DirectInnertubeService {
  DirectInnertubeService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'com.google.android.apps.youtube.vr.oculus/1.56.21 '
                '(Linux; U; Android 12; Quest 3 Build/SQ3A.220705.003.A1) '
                'gzip',
            'X-YouTube-Client-Name': '28',
            'X-YouTube-Client-Version': '1.56.21',
          },
        ),
      );

  final Dio _dio;

  static const _playerUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

  static const _payload = {
    'context': {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.56.21',
        'deviceModel': 'Quest 3',
        'osVersion': '12',
        'osName': 'Android',
        'androidSdkVersion': '32',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
    // Tell YouTube this is OK to play
    'contentCheckOk': true,
    'racyCheckOk': true,
  };

  Future<Uri?> audioUri(Track track) async {
    try {
      final body = Map<String, dynamic>.from(_payload)
        ..['videoId'] = track.id;

      final response = await _dio.post<Map<String, dynamic>>(
        _playerUrl,
        data: body,
      );

      final data = response.data;
      if (data == null) return null;

      final playability = data['playabilityStatus'] as Map?;
      final status = playability?['status'] as String?;
      if (status != 'OK') {
        throw Exception('DirectInnertube playability status: $status (Reason: ${playability?['reason']} / ${playability?['errorScreen']?['playerErrorMessageRenderer']?['reason']?['simpleText']})');
      }

      final streamingData = data['streamingData'] as Map?;
      if (streamingData == null) {
        throw Exception('DirectInnertube missing streamingData');
      }

      final adaptiveFormats =
          streamingData['adaptiveFormats'] as List? ?? [];

      // Collect audio-only streams with direct URLs
      final audioStreams =
          adaptiveFormats
              .whereType<Map>()
              .where(
                (f) =>
                    (f['mimeType'] as String? ?? '').startsWith('audio') &&
                    f['url'] is String,
              )
              .map((f) => Map<String, dynamic>.from(f))
              .toList()
            ..sort((a, b) {
              // Prefer m4a (mp4a codec) over webm for broader player support
              final aIsM4a =
                  '${a['mimeType']}'.toLowerCase().contains('mp4a');
              final bIsM4a =
                  '${b['mimeType']}'.toLowerCase().contains('mp4a');
              if (aIsM4a != bIsM4a) return aIsM4a ? -1 : 1;
              return ((b['bitrate'] as num?) ?? 0).compareTo(
                (a['bitrate'] as num?) ?? 0,
              );
            });

      if (audioStreams.isEmpty) return null;

      return Uri.tryParse(audioStreams.first['url'] as String);
    } on DioException catch (e) {
      throw Exception('DirectInnertube HTTP ${e.response?.statusCode} - ${e.message}');
    } catch (e) {
      throw Exception('DirectInnertube Error - $e');
    }
  }

  void dispose() => _dio.close(force: true);
}
