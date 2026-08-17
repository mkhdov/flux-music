import 'package:flutter_test/flutter_test.dart';
import 'package:flux/services/youtube_service.dart';

/// Replicates the retry decision made in
/// FluxProvider._retryPlaybackAfterError so the guard logic is verified
/// without a live device.
bool retryAllowed(Uri? failedUri, Uri newUri) =>
    failedUri == null || !sameBoundStream(failedUri, newUri);

void main() {
  Uri url({
    String host = 'rr2---sn-abc123.googlevideo.com',
    String? itag = '140',
    String? ip = '203.0.113.7',
    String n = 'nonce-a',
    String sig = 'old-signature',
  }) =>
      Uri.parse(
        'https://$host/videoplayback'
        '?expire=1893456000&itag=$itag&ip=$ip&n=$n&sig=$sig'
        '&fexp=23949&ei=stable-ei',
      );

  group('sameBoundStream', () {
    test('byte-identical URLs describe the same bound stream', () {
      final a = url();
      expect(sameBoundStream(a, a), isTrue);
    });

    test('volatile params changing does not change the bound stream', () {
      // Two extractions of the same stream always mint fresh nonce/signature
      // params; these must NOT make the guard treat the retry as meaningful.
      final first = url(n: 'nonce-a', sig: 'sig-a');
      final second = url(n: 'nonce-b', sig: 'sig-b');
      expect(sameBoundStream(first, second), isTrue);
      expect(retryAllowed(first, second), isFalse);
    });

    test('different CDN host is a different bound stream', () {
      final first = url();
      final second = url(host: 'rr4---sn-xyz789.googlevideo.com');
      expect(sameBoundStream(first, second), isFalse);
      expect(retryAllowed(first, second), isTrue);
    });

    test('different itag is a different bound stream', () {
      final first = url(itag: '140');
      final second = url(itag: '251');
      expect(sameBoundStream(first, second), isFalse);
      expect(retryAllowed(first, second), isTrue);
    });

    test('different embedding IP is a different bound stream', () {
      final first = url(ip: '203.0.113.7');
      final second = url(ip: '198.51.100.9');
      expect(sameBoundStream(first, second), isFalse);
      expect(retryAllowed(first, second), isTrue);
    });

    test('a missing failed URL always allows the retry', () {
      expect(retryAllowed(null, url()), isTrue);
    });

    test('URLs without ip params compare on host and itag only', () {
      final first = url(ip: null);
      final second = url(ip: null, n: 'nonce-c');
      expect(sameBoundStream(first, second), isTrue);
      expect(retryAllowed(first, second), isFalse);
    });
  });
}