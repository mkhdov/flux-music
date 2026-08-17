import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';

/// A resolved stream URL together with the HTTP headers required to fetch it
/// and the moment the URL was produced.
///
/// The three travel as one unit because googlevideo rejects the URL when it is
/// fetched without the headers youtube_explode_dart used during extraction,
/// and because the URL is cryptographically bound to the extraction moment,
/// the extracting client, and the extracting IP.
typedef ResolvedAudioStream = ({
  Uri url,
  Map<String, String> headers,
  DateTime resolvedAt,
});

/// The user agent of the ANDROID extraction client. Stream URLs are minted
/// under this identity, so the playback request must present the same one.
final String _extractionUserAgent =
    YoutubeApiClient.androidSdkless.payload['context']!['client']!['userAgent']
        as String;

/// Whether two resolved stream URLs point at the same bound stream.
///
/// Full URL equality is useless here: every extraction appends fresh volatile
/// query parameters (the throttling `n` nonce, `sig`, `fexp`, `expire`...), so
/// two extractions of the same stream are never byte-identical. googlevideo
/// instead binds a stream to its CDN host, its integer tag (`itag`), and the
/// embedding IP (`ip`. When all three agree, a fresh request reproduces the
/// previous outcome — including a 403 — so replaying the URL on a new player
/// instance can be skipped.
bool sameBoundStream(Uri a, Uri b) =>
    a.host == b.host &&
    a.queryParameters['itag'] == b.queryParameters['itag'] &&
    a.queryParameters['ip'] == b.queryParameters['ip'];

/// Formats a header map for diagnostics so ExoPlayer's request headers can be
/// compared directly against the ones the extraction client used.
String formatHeaders(Map<String, String>? headers) => headers == null
    ? '<none>'
    : headers.entries.map((e) => '${e.key}=${e.value}').join(' ');

class YoutubeService {
  YoutubeService({String? sessionCookie})
    : _sessionCookie = _normalizeSessionCookie(sessionCookie),
      _yt = YoutubeExplode(
        httpClient: _normalizeSessionCookie(sessionCookie) == null
            ? null
            : _AuthenticatedYoutubeHttpClient(
                _normalizeSessionCookie(sessionCookie)!,
              ),
      );

  static String? _normalizeSessionCookie(String? cookie) {
    if (cookie == null) return null;
    final trimmed = cookie.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _sessionCookie;
  YoutubeExplode _yt;

  /// Extraction runs under the ANDROID innertube client (`clientName:
  /// 'ANDROID'` in the player context), which returns pre-signed stream URLs
  /// that need no JS challenge solving. `androidSdkless` is the package's
  /// ANDROID client without the `androidSdkVersion` field, so it needs no PO
  /// token: the `android` variant (with `androidSdkVersion`) and the IOS/WEB
  /// clients are deliberately avoided — YouTube now rejects those without a
  /// PO token, and their URLs fail at playback time.
  static const _extractionClients = [YoutubeApiClient.androidSdkless];

  /// Fallback client for videos the ANDROID client reports as unplayable
  /// (age-restricted, region-limited).
  static const _tvFallbackClients = [YoutubeApiClient.tv];

  /// A manifest request can include a watch-page request and signature work, so
  /// a short timeout is prone to fail on mobile connections.
  static const extractionTimeout = Duration(seconds: 30);

  /// Headers that must accompany every request to a resolved stream URL.
  ///
  /// The package does not expose per-stream headers on its stream info objects
  /// (AudioOnlyStreamInfo has no httpHeaders property in 3.1.0); instead its
  /// YoutubeHttpClient injects [YoutubeHttpClient.defaultHeaders] into every
  /// outgoing request, including the head request it makes against the stream
  /// URL. googlevideo can reject a URL resolved by this package when a
  /// different HTTP client (ExoPlayer or Dio) fetches it without these
  /// headers, so every consumer of a resolved URL is given the same headers.
  ///
  /// The user agent is the one exception to mirroring the package defaults:
  /// [YoutubeHttpClient.defaultHeaders] carries a desktop Chrome identity,
  /// but the URL was minted by the ANDROID extraction client above. A stream
  /// requested under a client identity different from the one that minted it
  /// is exactly what YouTube bot detection blocks with a playback 403 while
  /// the extraction-era head request succeeds, so the playback request
  /// presents the extraction client's Android user agent instead. When a
  /// signed-in session cookie is configured it is appended the same way, so
  /// authentication flows into playback identically to the manifest request
  /// that minted the URL.
  Map<String, String> get playbackHeaders {
    final cookie = _sessionCookie;
    return <String, String>{
      ...YoutubeHttpClient.defaultHeaders,
      'user-agent': _extractionUserAgent,
      'cookie': ?cookie,
    };
  }

  /// Replaces the YouTube session used for extraction and playback.
  ///
  /// [cookie] is the raw cookie header value of a logged-in YouTube tab (it
  /// must contain at least `SID`/`SAPISID`). It is sent with the manifest
  /// request so YouTube mints URLs under the signed-in session, and with
  /// playback so the stream request carries the same identity. Passing null
  /// reverts to the anonymous session. Cached URLs and in-flight extractions
  /// from the previous session are dropped, since they were minted under a
  /// different identity.
  void setSessionCookie(String? cookie) {
    final normalized = _normalizeSessionCookie(cookie);
    if (normalized == _sessionCookie) return;
    _yt.close();
    _yt = YoutubeExplode(
      httpClient: normalized == null
          ? null
          : _AuthenticatedYoutubeHttpClient(normalized),
    );
    _sessionCookie = normalized;
    _audioCache.clear();
    _activeExtractions.clear();
  }

  bool get isSignedIn => _sessionCookie != null;

  static const _maxConcurrentExtractions = 2;
  static const _maxCachedStreams = 50;
  static const _cachedStreamTtl = Duration(minutes: 20);
  static const _defaultRetries = 1;
  static const _maximumRetries = 2;

  final Map<String, _CachedAudioStream> _audioCache = {};
  final Map<String, Future<ResolvedAudioStream>> _activeExtractions = {};
  final _ExtractionLimiter _extractionLimiter = _ExtractionLimiter(
    _maxConcurrentExtractions,
  );

  DateTime? _rateLimitCooldownUntil;
  int _consecutiveRateLimits = 0;

  static bool isUnavailableError(Object error) {
    if (error is YoutubeAudioException) return error.isUnavailable;

    return error is VideoUnplayableException ||
        error is VideoUnavailableException ||
        error is VideoRequiresPurchaseException;
  }

  Future<List<Track>> search(String query) async {
    final results = await _yt.search.search(query);

    return results
        .where((video) => !video.isLive && video.duration != null)
        .map(
          (video) => Track(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            thumbnailUrl: video.thumbnails.maxResUrl,
            webUrl: video.url,
            durationSeconds: video.duration!.inSeconds,
          ),
        )
        .toList();
  }

  /// Resolves an audio stream without downloading its media bytes.
  ///
  /// The optional arguments are retained for existing callers. Retries are
  /// capped to keep a faulty network or a rate-limited IP from creating an
  /// unbounded request load.
  Future<ResolvedAudioStream> audioUri(
    Track track, {
    Stopwatch? sw,
    int maxRetries = _defaultRetries,
    Duration clientTimeout = extractionTimeout,
  }) async {
    final stopwatch = sw ?? (Stopwatch()..start());

    final stream = await _bestAudioStream(
      track,
      stopwatch: stopwatch,
      maxRetries: maxRetries.clamp(0, _maximumRetries),
      clientTimeout: clientTimeout,
    );

    _diagnostic(
      videoId: track.id,
      attempt: 0,
      stopwatch: stopwatch,
      event: 'stream URL resolved',
      rateLimited: false,
    );

    developer.log(
      'resolved url=${stream.url} '
      'headers=${formatHeaders(stream.headers)} '
      'resolvedAt=${stream.resolvedAt.toIso8601String()} '
      'urlIp=${stream.url.queryParameters['ip']}',
      name: 'Flux.YouTubeExtraction',
    );

    // Prime the public-IP probe now so a later playback error has an
    // extraction-era reading to compare its own reading against.
    unawaited(publicIp());

    return stream;
  }

  Future<ResolvedAudioStream> _bestAudioStream(
    Track track, {
    required Stopwatch stopwatch,
    required int maxRetries,
    required Duration clientTimeout,
  }) async {
    final cached = _readCachedStream(track.id);

    if (cached != null) {
      _diagnostic(
        videoId: track.id,
        attempt: 0,
        stopwatch: stopwatch,
        event: 'cache hit',
        rateLimited: false,
      );

      return cached.stream;
    }

    final activeExtraction = _activeExtractions[track.id];

    if (activeExtraction != null) {
      _diagnostic(
        videoId: track.id,
        attempt: 0,
        stopwatch: stopwatch,
        event: 'joined in-flight extraction',
        rateLimited: false,
      );

      return activeExtraction;
    }

    final extractionFuture =
        _resolveAudioStream(
          track,
          stopwatch: stopwatch,
          maxRetries: maxRetries,
          clientTimeout: clientTimeout,
        ).then(
          (stream) => (
            url: stream.url,
            headers: playbackHeaders,
            resolvedAt: DateTime.now(),
          ),
        );

    _activeExtractions[track.id] = extractionFuture;

    try {
      final stream = await extractionFuture;

      _writeCachedStream(track.id, stream);

      return stream;
    } finally {
      if (identical(_activeExtractions[track.id], extractionFuture)) {
        _activeExtractions.remove(track.id);
      }
    }
  }

  Future<AudioOnlyStreamInfo> _resolveAudioStream(
    Track track, {
    required Stopwatch stopwatch,
    required int maxRetries,
    required Duration clientTimeout,
  }) async {
    final attemptCount = maxRetries + 1;

    for (var attempt = 1; attempt <= attemptCount; attempt++) {
      await _waitForRateLimitCooldown(track.id, attempt, stopwatch);

      try {
        final manifest = await _requestManifest(
          track,
          clients: _extractionClients,
          stopwatch: stopwatch,
          attempt: attempt,
          clientTimeout: clientTimeout,
        );

        final stream = await _selectAudioStream(manifest);

        _consecutiveRateLimits = 0;

        return stream;
      } on VideoUnplayableException {
        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event:
              'androidSdkless reports the video unplayable; trying the tv client',
          rateLimited: false,
        );

        // The tv client serves some videos (age-restricted, region-limited)
        // that the androidSdkless client reports as unplayable. Retry once
        // with it before giving up. Rate limits and timeouts must propagate
        // to the outer handlers, so only playability errors are swallowed.
        try {
          final manifest = await _requestManifest(
            track,
            clients: _tvFallbackClients,
            stopwatch: stopwatch,
            attempt: attempt,
            clientTimeout: clientTimeout,
          );

          _consecutiveRateLimits = 0;

          return _selectAudioStream(manifest);
        } on VideoUnplayableException {
          // The tv client reports the same problem; fall through below.
        }

        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: 'final failure: video unavailable or unplayable',
          rateLimited: false,
        );

        throw const YoutubeAudioException(
          'Unavailable: This video does not have a playable audio stream.',
          kind: YoutubeAudioFailureKind.unavailable,
        );
      } on RequestLimitExceededException {
        final delay = _registerRateLimit();
        final hasRetry = attempt < attemptCount;

        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: hasRetry
              ? 'rate-limited; retry deferred for ${delay.inSeconds}s'
              : 'final failure: YouTube rate limit',
          rateLimited: true,
        );

        if (!hasRetry) {
          throw const YoutubeAudioException(
            'YouTube is temporarily limiting audio requests. Please wait a '
            'few minutes before trying again.',
            kind: YoutubeAudioFailureKind.rateLimited,
          );
        }
      } on TimeoutException {
        final hasRetry = attempt < attemptCount;

        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: hasRetry
              ? 'request timed out; retry deferred'
              : 'final failure: extraction timeout',
          rateLimited: false,
        );

        if (!hasRetry) {
          throw const YoutubeAudioException(
            'Timed out while resolving this YouTube audio stream. Please '
            'check the connection and try again.',
            kind: YoutubeAudioFailureKind.timeout,
          );
        }

        await _waitBeforeTransientRetry(attempt, track.id, stopwatch);
      } on TransientFailureException {
        final hasRetry = attempt < attemptCount;

        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: hasRetry
              ? 'transient YouTube failure; retry deferred'
              : 'final failure: transient YouTube failure',
          rateLimited: false,
        );

        if (!hasRetry) {
          throw const YoutubeAudioException(
            'YouTube is temporarily unavailable. Please try again later.',
            kind: YoutubeAudioFailureKind.transientFailure,
          );
        }

        await _waitBeforeTransientRetry(attempt, track.id, stopwatch);
      } on YoutubeAudioException {
        // Preserve track-specific messages (e.g. "no audio-only stream")
        // instead of collapsing them into a generic extraction error.
        rethrow;
      } on YoutubeExplodeException {
        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: 'final failure: YouTube extraction error',
          rateLimited: false,
        );

        throw const YoutubeAudioException(
          'Could not resolve this YouTube audio stream. Please try again later.',
          kind: YoutubeAudioFailureKind.extractionFailure,
        );
      } catch (_) {
        _diagnostic(
          videoId: track.id,
          attempt: attempt,
          stopwatch: stopwatch,
          event: 'final failure: unexpected extraction error',
          rateLimited: false,
        );

        throw const YoutubeAudioException(
          'Could not resolve this YouTube audio stream. Please try again later.',
          kind: YoutubeAudioFailureKind.extractionFailure,
        );
      }
    }

    // The loop always either returns or throws. This satisfies flow analysis.
    throw StateError('Audio extraction ended without a result.');
  }

  /// Issues a single manifest request through the shared extraction limiter.
  ///
  /// The watch page is skipped to avoid its endpoint, which YouTube rate
  /// limits aggressively for bot-like traffic; the player API response alone
  /// carries the same stream data. androidSdkless supplies pre-signed stream
  /// URLs, so no JS challenge solving is required.
  Future<StreamManifest> _requestManifest(
    Track track, {
    required List<YoutubeApiClient> clients,
    required Stopwatch stopwatch,
    required int attempt,
    required Duration clientTimeout,
  }) {
    return _extractionLimiter.run(() async {
      final clientNames = clients
          .map(
            (c) =>
                (((c.payload['context'] as Map)['client'] as Map)['clientName'])
                    as String?,
          )
          .join('+');

      _diagnostic(
        videoId: track.id,
        attempt: attempt,
        stopwatch: stopwatch,
        event: 'manifest request started (client $clientNames)',
        rateLimited: false,
      );

      final result = await _yt.videos.streamsClient
          .getManifest(track.id, ytClients: clients, requireWatchPage: false)
          .timeout(clientTimeout);

      _diagnostic(
        videoId: track.id,
        attempt: attempt,
        stopwatch: stopwatch,
        event: 'manifest request succeeded',
        rateLimited: false,
      );

      return result;
    });
  }

  Future<AudioOnlyStreamInfo> _selectAudioStream(
    StreamManifest manifest,
  ) async {
    if (manifest.audioOnly.isEmpty) {
      throw const YoutubeAudioException(
        'Unavailable: No audio-only stream is available for this track.',
        kind: YoutubeAudioFailureKind.unavailable,
      );
    }

    final connectivity = await Connectivity().checkConnectivity();

    final isWeakConnection =
        connectivity.contains(ConnectivityResult.mobile) ||
        connectivity.contains(ConnectivityResult.bluetooth);

    if (isWeakConnection) {
      return manifest.audioOnly.sortByBitrate().first;
    }

    for (final preferredTag in [140, 251]) {
      for (final stream in manifest.audioOnly) {
        if (stream.tag == preferredTag) {
          return stream;
        }
      }
    }

    return manifest.audioOnly.withHighestBitrate();
  }

  _CachedAudioStream? _readCachedStream(String videoId) {
    final cached = _audioCache.remove(videoId);

    if (cached == null) {
      return null;
    }

    if (DateTime.now().difference(cached.resolvedAt) >= _cachedStreamTtl) {
      return null;
    }

    // Re-insertion makes the map a small LRU cache.
    _audioCache[videoId] = cached;

    return cached;
  }

  void _writeCachedStream(String videoId, ResolvedAudioStream stream) {
    _audioCache.remove(videoId);

    _audioCache[videoId] = _CachedAudioStream(stream, DateTime.now());

    while (_audioCache.length > _maxCachedStreams) {
      _audioCache.remove(_audioCache.keys.first);
    }
  }

  /// Drops the cached stream URL for a video, forcing the next resolution to
  /// re-extract. Used when playback fails with a source error: YouTube stream
  /// URLs are bound to the IP they were resolved from, so a stale cached URL
  /// must not be reused.
  void invalidateStream(String videoId) {
    _audioCache.remove(videoId);
  }

  static const _publicIpTtl = Duration(minutes: 2);
  String? _publicIp;
  DateTime? _publicIpCheckedAt;

  /// The device's public IP as seen by an outbound endpoint.
  ///
  /// Cached for [_publicIpTtl] to avoid hammering the probe. Compare the
  /// result against the `ip` query parameter of a resolved googlevideo URL to
  /// determine whether a 403 came from the URL being bound to a different IP
  /// than the one requesting it (IP binding) or from the streaming layer
  /// itself (bot detection).
  Future<String?> publicIp() async {
    final now = DateTime.now();
    final lastChecked = _publicIpCheckedAt;
    if (lastChecked != null && now.difference(lastChecked) < _publicIpTtl) {
      return _publicIp;
    }
    _publicIpCheckedAt = now;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client
            .getUrl(Uri.parse('https://api.ipify.org'))
            .timeout(const Duration(seconds: 5));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        _publicIp = body.trim();

        developer.log(
          'public IP probe ip=${_publicIp ?? 'failed'}',
          name: 'Flux.YouTubeExtraction',
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      _publicIp = null;
    }
    return _publicIp;
  }

  Duration _registerRateLimit() {
    _consecutiveRateLimits = (_consecutiveRateLimits + 1).clamp(1, 4);

    final seconds = 4 * (1 << (_consecutiveRateLimits - 1));

    final delay = Duration(seconds: seconds.clamp(4, 30));

    final proposedUntil = DateTime.now().add(delay);

    if (_rateLimitCooldownUntil == null ||
        proposedUntil.isAfter(_rateLimitCooldownUntil!)) {
      _rateLimitCooldownUntil = proposedUntil;
    }

    return delay;
  }

  Future<void> _waitForRateLimitCooldown(
    String videoId,
    int attempt,
    Stopwatch stopwatch,
  ) async {
    final cooldownUntil = _rateLimitCooldownUntil;

    if (cooldownUntil == null) {
      return;
    }

    final delay = cooldownUntil.difference(DateTime.now());

    if (delay <= Duration.zero) {
      return;
    }

    _diagnostic(
      videoId: videoId,
      attempt: attempt,
      stopwatch: stopwatch,
      event: 'waiting ${delay.inSeconds}s for shared rate-limit cooldown',
      rateLimited: true,
    );

    await Future<void>.delayed(delay);
  }

  Future<void> _waitBeforeTransientRetry(
    int attempt,
    String videoId,
    Stopwatch stopwatch,
  ) async {
    final delay = Duration(seconds: 1 << attempt);

    _diagnostic(
      videoId: videoId,
      attempt: attempt,
      stopwatch: stopwatch,
      event: 'waiting ${delay.inSeconds}s before transient retry',
      rateLimited: false,
    );

    await Future<void>.delayed(delay);
  }

  void _diagnostic({
    required String videoId,
    required int attempt,
    required Stopwatch stopwatch,
    required String event,
    required bool rateLimited,
  }) {
    // Keep diagnostics intentionally metadata-only. In particular, do not log
    // exception text because package errors can include a request description.
    developer.log(
      'videoId=$videoId '
      'requestStart=${DateTime.now().toIso8601String()} '
      'attempt=$attempt '
      'elapsedMs=${stopwatch.elapsedMilliseconds} '
      'rateLimited=$rateLimited '
      'event=$event',
      name: 'Flux.YouTubeExtraction',
    );
  }

  Future<void> prefetch(Track track) async {
    try {
      await audioUri(track, maxRetries: 0);
    } catch (_) {
      // Prefetching must not surface failures or add retries to user actions.
    }
  }

  void prefetchTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      unawaited(prefetch(track));
    }
  }

  Future<List<Track>> getRelatedTracks(String videoId) async {
    try {
      final video = await _yt.videos.get(VideoId(videoId));

      final related = await _yt.videos.getRelatedVideos(video);

      if (related == null) {
        return [];
      }

      return related
          .where((v) => !v.isLive && v.duration != null)
          .map(
            (v) => Track(
              id: v.id.value,
              title: v.title,
              artist: v.author,
              thumbnailUrl: v.thumbnails.maxResUrl,
              webUrl: v.url,
              durationSeconds: v.duration!.inSeconds,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _yt.close();
  }
}

class _CachedAudioStream {
  const _CachedAudioStream(this.stream, this.resolvedAt);

  /// The resolved URL plus the headers required to fetch it. Headers are
  /// cached alongside the URL because the URL is unusable without them.
  final ResolvedAudioStream stream;
  final DateTime resolvedAt;
}

/// A [YoutubeHttpClient] that replaces the package's placeholder cookie with
/// the cookie header of a signed-in YouTube session and its desktop user
/// agent with the ANDROID extraction client's.
///
/// The header map returned here is injected into every request the extraction
/// client sends, including the head request it makes against the stream URL,
/// so the same cookie and client identity also flow into
/// [YoutubeService.playbackHeaders] and are honored by the native player's
/// stream request.
class _AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  _AuthenticatedYoutubeHttpClient(this._cookie);

  final String _cookie;

  @override
  Map<String, String> get headers => <String, String>{
    ...YoutubeHttpClient.defaultHeaders,
    'user-agent': _extractionUserAgent,
    'cookie': _cookie,
  };
}

/// Limits actual manifest requests. Queued work does not send an HTTP request
/// until a slot is free.
class _ExtractionLimiter {
  _ExtractionLimiter(this._limit);

  final int _limit;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  var _inUse = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();

    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_inUse < _limit) {
      _inUse++;

      return Future<void>.value();
    }

    final completer = Completer<void>();

    _waiters.add(completer);

    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }

    _inUse--;
  }
}

enum YoutubeAudioFailureKind {
  rateLimited,
  timeout,
  transientFailure,
  unavailable,
  extractionFailure,
}

class YoutubeAudioException implements Exception {
  const YoutubeAudioException(
    this.message, {
    this.kind = YoutubeAudioFailureKind.extractionFailure,
  });

  final String message;
  final YoutubeAudioFailureKind kind;

  bool get isUnavailable => kind == YoutubeAudioFailureKind.unavailable;

  bool get isRateLimited => kind == YoutubeAudioFailureKind.rateLimited;

  @override
  String toString() => message;
}
