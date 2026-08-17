import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/flux_provider.dart';
import '../widgets/track_tile.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    return SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text(
              'Library',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ),
          _LibraryCard(
            icon: Icons.history_rounded,
            title: 'Recently Played',
            caption: '${flux.recent.length} tracks',
            onTap: () => _openTracks(context, 'Recently Played', flux.recent),
          ),
          _LibraryCard(
            icon: Icons.favorite_rounded,
            title: 'Favorites',
            caption: '${flux.favorites.length} loved tracks',
            onTap: () => _openTracks(context, 'Favorites', flux.favorites),
          ),
          _LibraryCard(
            icon: Icons.download_done_rounded,
            title: 'Downloads',
            caption: '${flux.downloadsList.length} available offline',
            onTap: () => _openDownloads(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
            child: Row(
              children: [
                Text(
                  'Playlists',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _playlistDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          ...flux.playlists.map(
            (playlist) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                playlist.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${playlist.trackIds.length} songs'),
              onTap: () => _openPlaylist(context, playlist),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') {
                    _playlistDialog(context, playlist: playlist);
                  } else {
                    flux.deletePlaylist(playlist);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
          if (flux.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text('Your playlists will appear here.'),
            ),
        ],
      ),
    );
  }

  void _openTracks(BuildContext context, String title, List<Track> tracks) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackCollectionScreen(title: title, tracks: tracks),
        ),
      );
  void _openDownloads(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
  );
  void _openPlaylist(BuildContext context, Playlist playlist) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)),
  );

  Future<void> _playlistDialog(
    BuildContext context, {
    Playlist? playlist,
  }) async {
    final controller = TextEditingController(text: playlist?.name);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(playlist == null ? 'New Playlist' : 'Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (playlist == null) {
                await context.read<FluxProvider>().createPlaylist(
                  controller.text,
                );
              } else {
                await context.read<FluxProvider>().renamePlaylist(
                  playlist,
                  controller.text,
                );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(caption),
      onTap: onTap,
    ),
  );
}

class TrackCollectionScreen extends StatelessWidget {
  const TrackCollectionScreen({
    super.key,
    required this.title,
    required this.tracks,
  });
  final String title;
  final List<Track> tracks;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 22))),
    body: tracks.isEmpty
        ? const Center(child: Text('Nothing here yet.'))
        : ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) => TrackTile(track: tracks[i], queue: tracks),
          ),
  );
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tracks = context.watch<FluxProvider>().downloadsList;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads', style: TextStyle(fontSize: 22)),
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('Download a track to keep it offline.'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(tracks[i].id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) =>
                    context.read<FluxProvider>().deleteDownload(tracks[i]),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 28),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: TrackTile(track: tracks[i], queue: tracks),
              ),
            ),
    );
  }
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.playlist});
  final Playlist playlist;
  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    final tracks = flux.storage.tracksById(playlist.trackIds);
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name, style: const TextStyle(fontSize: 22)),
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('Add songs from search to this playlist.'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(tracks[i].id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) =>
                    flux.removeFromPlaylist(playlist, tracks[i].id),
                background: Container(color: Colors.red),
                child: TrackTile(track: tracks[i], queue: tracks),
              ),
            ),
    );
  }
}
