import 'package:dio/dio.dart';

import '../models/track.dart';

/// Keyless public fallback for temporary direct-YouTube rate limits.
///
/// Tries a curated list of known-good Piped API instances in parallel, and
/// also attempts to fetch a fresh instance list from the official Piped
/// registry so the pool stays up-to-date even if individual instances go down.
class PipedFallbackService {
  PipedFallbackService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {'accept': 'application/json'},
        ),
      );

  final Dio _dio;
  String? _preferredEndpoint;
  List<String>? _dynamicEndpoints;

  /// Curated list of official / well-known Piped API instances.
  /// Ordered roughly by reliability / CDN coverage.
  static const _staticEndpoints = [
    'https://pipedapi.kavin.rocks',          // Official, CDN, multi-region
    'https://pipedapi-libre.kavin.rocks',    // Official, no-CDN
    'https://pipedapi.leptons.xyz',          // Austria, CDN
    'https://piped-api.privacy.com.de',      // Germany
    'https://pipedapi.adminforge.de',        // Germany
    'https://api.piped.yt',                  // Germany
    'https://pipedapi.nosebs.ru',            // Finland, CDN
    'https://pipedapi.drgns.space',          // US
    'https://pipedapi.owo.si',               // Germany
    'https://pipedapi.ducks.party',          // Netherlands
    'https://piped-api.codespace.cz',        // Czech Republic
    'https://pipedapi.reallyaweso.me',       // Germany
    'https://api.piped.private.coffee',      // Austria
    'https://pipedapi.darkness.services',    // US
    'https://pipedapi.orangenet.cc',         // Slovenia
  ];

  /// The Piped project publishes a machine-readable instance list at this URL.
  static const _instanceRegistryUrl =
      'https://piped-api.kavin.rocks/instances';

  Future<Uri?> audioUri(Track track) async {
    // Refresh the dynamic endpoint pool at most once per session.
    _dynamicEndpoints ??= await _fetchDynamicEndpoints();

    // Build a deduplicated, preference-ordered endpoint list.
    final seen = <String>{};
    final ordered = <String>[
      ?_preferredEndpoint,
      ..._staticEndpoints,
      ...?_dynamicEndpoints,
    ].where(seen.add).toList();

    final attempts = await Future.wait(
      ordered.map((ep) => _request(ep, track.id)),
    );

    final errors = <String>[];
    for (final attempt in attempts) {
      if (attempt.$2 != null) {
        _preferredEndpoint = attempt.$1;
        return attempt.$2;
      }
      if (attempt.$3 != null) {
        errors.add('${attempt.$1}: ${attempt.$3}');
      }
    }
    
    throw Exception('Piped endpoints failed:\n${errors.join('\n')}');
  }

  Future<List<String>> _fetchDynamicEndpoints() async {
    try {
      final response = await _dio.get<List<dynamic>>(_instanceRegistryUrl);
      final data = response.data;
      if (data == null) return [];
      return data
          .whereType<Map>()
          .map((item) => item['api_url'])
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<(String?, Uri?, String?)> _request(String endpoint, String videoId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$endpoint/streams/$videoId',
      );
      final streams = response.data?['audioStreams'];
      if (streams is! List) return (endpoint, null, 'No audioStreams list found');
      final audio =
          streams
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => item['url'] is String)
              .toList()
            ..sort((a, b) {
              final aIsM4a = '${a['mimeType']} ${a['format']}'
                  .toLowerCase()
                  .contains('mp4');
              final bIsM4a = '${b['mimeType']} ${b['format']}'
                  .toLowerCase()
                  .contains('mp4');
              if (aIsM4a != bIsM4a) return aIsM4a ? -1 : 1;
              return (b['bitrate'] as num? ?? 0).compareTo(
                a['bitrate'] as num? ?? 0,
              );
            });
      final uri = audio.isEmpty
          ? null
          : Uri.tryParse(audio.first['url'] as String);
      return uri == null ? (endpoint, null, 'No valid mp4/m4a stream found') : (endpoint, uri, null);
    } on DioException catch (e) {
      return (endpoint, null, 'HTTP ${e.response?.statusCode} - ${e.message}');
    } catch (e) {
      return (endpoint, null, 'Error - $e');
    }
  }

  void dispose() => _dio.close(force: true);
}
