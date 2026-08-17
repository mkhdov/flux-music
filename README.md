# Flux

Flux is an on-device Flutter music player for personal/sideloaded use. It searches YouTube through `youtube_explode_dart`, resolves **audio-only** streams, and never creates a video player or renders video.

## Included

- Apple Music-inspired light, dark, and system themes using Inter typography
- YouTube search with video artwork, artist/channel, and duration
- Audio-only playback with background media session, notification controls, lock-screen artwork, headset/Bluetooth media controls, and audio focus via `just_audio_background`
- Persistent mini player with Hero artwork transition and swipe-down full player
- Seek, previous/next, shuffle, repeat off/all/one, volume, speed, sleep timer, queue reordering, favorites, share, and download controls
- Local Hive data for favorites, recently played, playlists, theme preference, and downloaded-track metadata
- Offline M4A audio downloads stored inside the app's documents directory

## Run locally

1. Install Flutter stable, an Android SDK/device, and Java 17–21 (Java 25 is not yet compatible with this project's default Gradle setup).
2. In this folder run:

   ```bash
   flutter pub get
   flutter run
   ```

3. Search for a track, tap it to start an audio-only stream, and use the overflow menu to add other tracks to Up Next.

YouTube periodically changes stream formats. Flux shows an error state when extraction fails; retrying later may resolve it.

## Build and sideload Android APK

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

For Android 13+, allow notification permission on first launch so the MediaStyle playback notification can be displayed. The app is designed for personal/sideloaded use; make sure your use complies with YouTube's terms and applicable rights.

## Project structure

```text
lib/
  models/       Track and playlist data
  providers/    App state, local library, sleep timer
  screens/      Search, library, settings, queue, full player
  services/     YouTube, player/media session, downloads, Hive storage
  theme/        Light and dark Flux ThemeData
  widgets/      Artwork, mini player, reusable track rows
```
