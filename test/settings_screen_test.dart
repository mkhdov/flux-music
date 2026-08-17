import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flux/providers/flux_provider.dart';
import 'package:flux/screens/settings_screen.dart';
import 'package:flux/services/audio_cache_service.dart';
import 'package:flux/services/download_service.dart';
import 'package:flux/services/player_service.dart';
import 'package:flux/services/storage_service.dart';
import 'package:flux/services/youtube_service.dart';

/// In-memory [StorageService] so the widget test performs no real I/O.
///
/// Real Hive file access cannot complete inside `testWidgets`'s fake-async
/// zone, so everything the settings screen touches is stubbed.
class FakeStorage extends StorageService {
  String theme = 'system';
  String? cookie;

  @override
  String get themeMode => theme;

  @override
  String? get audioSessionCookie => cookie;

  @override
  Future<void> setThemeMode(String value) async {
    theme = value;
  }

  @override
  Future<void> setAudioSessionCookie(String? value) async {
    cookie = value?.trim().isEmpty ?? true ? null : value!.trim();
  }
}

FluxProvider provider() => FluxProvider(
  FakeStorage(),
  YoutubeService(),
  AudioCacheService(YoutubeService()),
  DownloadService(YoutubeService()),
  PlayerService(YoutubeService()),
);

void main() {
  Widget app(FluxProvider flux) => ChangeNotifierProvider<FluxProvider>.value(
    value: flux,
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );

  testWidgets('settings screen renders without asserted exceptions',
      (tester) async {
    final flux = provider();

    await tester.pumpWidget(app(flux));
    expect(tester.takeException(), isNull);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Session cookie'), findsOneWidget);
    expect(find.text('Anonymous YouTube session'), findsOneWidget);
  });

  testWidgets('pasting a session cookie does not throw and activates session',
      (tester) async {
    final flux = provider();
    await tester.pumpWidget(app(flux));

    // Regression test: obscureText combined with multiline input throws
    // "Obscured fields cannot be multiline"; the field is single-line now.
    await tester.enterText(
      find.byType(TextField),
      'CONSENT=YES+cb; SID=abc-123; SAPISID=xyz-456',
    );
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(flux.isSignedIn, isTrue);
    expect(flux.sessionCookie, contains('SAPISID=xyz-456'));
    expect(find.text('Signed-in YouTube session'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(flux.isSignedIn, isFalse);
  });
}