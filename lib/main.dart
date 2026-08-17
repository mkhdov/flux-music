import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'providers/flux_provider.dart';
import 'screens/home_shell.dart';
import 'services/download_service.dart';
import 'services/player_service.dart';
import 'services/storage_service.dart';
import 'services/youtube_service.dart';
import 'theme/flux_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'flux.playback',
    androidNotificationChannelName: 'Flux playback',
    androidNotificationOngoing: true,
  );
  final storage = StorageService();
  await storage.init();
  final youtube = YoutubeService();
  runApp(
    ChangeNotifierProvider(
      create: (_) => FluxProvider(
        storage,
        youtube,
        DownloadService(youtube),
        PlayerService(),
      ),
      child: const FluxApp(),
    ),
  );
}

class FluxApp extends StatelessWidget {
  const FluxApp({super.key});
  @override
  Widget build(BuildContext context) => Consumer<FluxProvider>(
    builder: (context, flux, child) => MaterialApp(
      title: 'Flux',
      debugShowCheckedModeBanner: false,
      theme: FluxTheme.light(),
      darkTheme: FluxTheme.dark(),
      themeMode: flux.themeMode,
      home: const HomeShell(),
    ),
  );
}
