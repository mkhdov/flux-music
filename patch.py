import os

# 1. track.dart
f = 'lib/models/track.dart'
with open(f, 'r') as file:
    content = file.read()

content = content.replace(
    'this.isSuggested = false,',
    'this.isSuggested = false,\n    this.isUnavailable = false,'
)
content = content.replace(
    'final bool isSuggested;',
    'final bool isSuggested;\n  final bool isUnavailable;'
)
content = content.replace(
    'bool? isSuggested}) => Track(',
    'bool? isSuggested, bool? isUnavailable}) => Track('
)
content = content.replace(
    'isSuggested: isSuggested ?? this.isSuggested,',
    'isSuggested: isSuggested ?? this.isSuggested,\n    isUnavailable: isUnavailable ?? this.isUnavailable,'
)
content = content.replace(
    "'isSuggested': isSuggested,",
    "'isSuggested': isSuggested,\n    'isUnavailable': isUnavailable,"
)
content = content.replace(
    "isSuggested: map['isSuggested'] as bool? ?? false,",
    "isSuggested: map['isSuggested'] as bool? ?? false,\n    isUnavailable: map['isUnavailable'] as bool? ?? false,"
)
with open(f, 'w') as file:
    file.write(content)

# 2. youtube_service.dart
f = 'lib/services/youtube_service.dart'
with open(f, 'r') as file:
    content = file.read()

content = content.replace(
    "if (e.message.toLowerCase().contains('bot') || e.message.toLowerCase().contains('sign in to confirm')) {",
    "if (e.message.toLowerCase().contains('bot') || e.message.toLowerCase().contains('sign in to confirm') || e.message.toLowerCase().contains('videounavailableexception') || e.message.contains('Unavailable:')) {"
)

content = content.replace(
    "if (e.toString().toLowerCase().contains('bot') || e.toString().toLowerCase().contains('sign in to confirm')) {",
    "if (e.toString().toLowerCase().contains('bot') || e.toString().toLowerCase().contains('sign in to confirm') || e.toString().toLowerCase().contains('videounavailableexception') || e.toString().contains('VideoUnavailableException')) {"
)

content = content.replace(
    "completer.completeError(YoutubeAudioException('Sign in to confirm you\\'re not a bot'));",
    "completer.completeError(YoutubeAudioException('Unavailable: Video is unavailable or sign in to confirm you\\'re not a bot'));"
)
content = content.replace(
    "throw YoutubeAudioException('Unavailable: YouTube blocked this track (Bot detection). Sign-in may be required.');",
    "throw YoutubeAudioException('Unavailable: Video is unavailable or YouTube blocked this track (Bot detection). Sign-in may be required.');"
)

with open(f, 'w') as file:
    file.write(content)

# 3. flux_provider.dart
f = 'lib/providers/flux_provider.dart'
with open(f, 'r') as file:
    content = file.read()

content = content.replace(
    "Future<bool> play(Track track, {List<Track>? queue}) async {",
    "Future<bool> play(Track track, {List<Track>? queue}) async {\n    if (track.isUnavailable) return false;"
)
content = content.replace(
    "} on YoutubeAudioException catch (error) {\n      actionError = error.message;\n    } catch (_) {",
    "} on YoutubeAudioException catch (error) {\n      if (error.message.startsWith('Unavailable:')) {\n        player.markTrackUnavailable(track.id);\n      }\n      actionError = error.message;\n    } catch (_) {"
)

content = content.replace(
    "int nextIndex = currentIndex + 1;\n    \n    if (nextIndex >= player.queue.length) {",
    "int nextIndex = currentIndex + 1;\n    \n    while (nextIndex < player.queue.length && player.queue[nextIndex].isUnavailable) {\n      nextIndex++;\n    }\n\n    if (nextIndex >= player.queue.length) {"
)

content = content.replace(
    "if (player.loopMode == LoopMode.all) {\n        nextIndex = 0;\n      } else {\n        return;\n      }",
    "if (player.loopMode == LoopMode.all) {\n        nextIndex = 0;\n        while (nextIndex < player.queue.length && player.queue[nextIndex].isUnavailable) {\n          nextIndex++;\n        }\n        if (nextIndex >= player.queue.length) return;\n      } else {\n        return;\n      }"
)

content = content.replace(
    "int prevIndex = currentIndex - 1;\n    \n    if (prevIndex < 0) {",
    "int prevIndex = currentIndex - 1;\n    \n    while (prevIndex >= 0 && player.queue[prevIndex].isUnavailable) {\n      prevIndex--;\n    }\n\n    if (prevIndex < 0) {"
)

content = content.replace(
    "if (player.loopMode == LoopMode.all) {\n        prevIndex = player.queue.length - 1;\n      } else {\n        prevIndex = 0;\n      }",
    "if (player.loopMode == LoopMode.all) {\n        prevIndex = player.queue.length - 1;\n        while (prevIndex >= 0 && player.queue[prevIndex].isUnavailable) {\n          prevIndex--;\n        }\n        if (prevIndex < 0) return;\n      } else {\n        prevIndex = 0;\n        if (player.queue.isNotEmpty && player.queue[0].isUnavailable) return;\n      }"
)

content = content.replace(
    "await player.playStream(merged, uri);\n      await storage.addRecent(merged);\n      _prefetchNext();\n    } on YoutubeAudioException catch (error) {\n      actionError = error.message;\n    } catch (e) {",
    "await player.playStream(merged, uri);\n      await storage.addRecent(merged);\n      _prefetchNext();\n    } on YoutubeAudioException catch (error) {\n      if (error.message.startsWith('Unavailable:')) {\n        player.markTrackUnavailable(track.id);\n        WidgetsBinding.instance.addPostFrameCallback((_) => next());\n      }\n      actionError = error.message;\n    } catch (e) {"
)

content = content.replace(
    "if (currentIndex != -1 && currentIndex + 1 < player.queue.length) {\n      final nextTrack = player.queue[currentIndex + 1];\n      if (storage.downloaded(nextTrack.id) == null) {\n        youtube.prefetch(nextTrack);\n      }\n    }",
    "if (currentIndex != -1) {\n      int nIdx = currentIndex + 1;\n      while (nIdx < player.queue.length && player.queue[nIdx].isUnavailable) {\n        nIdx++;\n      }\n      if (nIdx < player.queue.length) {\n        final nextTrack = player.queue[nIdx];\n        if (storage.downloaded(nextTrack.id) == null) {\n          youtube.prefetch(nextTrack);\n        }\n      }\n    }"
)

with open(f, 'w') as file:
    file.write(content)

# 4. track_tile.dart
f = 'lib/widgets/track_tile.dart'
with open(f, 'r') as file:
    content = file.read()

content = content.replace(
    "return ListTile(\n      contentPadding",
    "return ListTile(\n      enabled: !track.isUnavailable,\n      contentPadding"
)
content = content.replace(
    "style: const TextStyle(fontWeight: FontWeight.w600),",
    "style: TextStyle(fontWeight: FontWeight.w600, color: track.isUnavailable ? Colors.grey : null),"
)
content = content.replace(
    "onTap: () => _playAndOpen(context, flux),",
    "onTap: track.isUnavailable ? null : () => _playAndOpen(context, flux),"
)
content = content.replace(
    "trailing: PopupMenuButton<String>(",
    "trailing: track.isUnavailable ? const Icon(Icons.error_outline, color: Colors.grey) : PopupMenuButton<String>("
)

with open(f, 'w') as file:
    file.write(content)

