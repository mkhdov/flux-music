import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/flux_provider.dart';
import '../screens/now_playing_screen.dart';
import 'artwork.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, this.queue});
  final Track track;
  final List<Track>? queue;

  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    final favorite = flux.storage.isFavorite(track.id);
    final downloaded = flux.storage.downloaded(track.id) != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      leading: Artwork(url: track.thumbnailUrl, size: 58, borderRadius: 10),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text(' · '),
          Text(track.durationLabel),
          if (downloaded) ...[
            const SizedBox(width: 6),
            const Icon(Icons.download_done_rounded, size: 15),
          ],
        ],
      ),
      onTap: () => _playAndOpen(context, flux),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (value) => _action(context, flux, value),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
          PopupMenuItem(
            value: 'favorite',
            child: Text(favorite ? 'Remove from favorites' : 'Favorite'),
          ),
          PopupMenuItem(
            value: 'download',
            child: Text(downloaded ? 'Downloaded' : 'Download'),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: Text('Add to playlist'),
          ),
        ],
      ),
    );
  }

  Future<void> _action(
    BuildContext context,
    FluxProvider flux,
    String value,
  ) async {
    switch (value) {
      case 'queue':
        flux.addToQueue(track);
      case 'favorite':
        await flux.toggleFavorite(track);
      case 'download':
        await flux.download(track);
      case 'playlist':
        if (context.mounted) _choosePlaylist(context, flux);
    }
  }

  Future<void> _playAndOpen(BuildContext context, FluxProvider flux) async {
    final didStart = await flux.play(track, queue: queue);
    if (didStart && context.mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
    }
  }

  void _choosePlaylist(BuildContext context, FluxProvider flux) =>
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Add to playlist',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...flux.playlists.map(
              (playlist) => ListTile(
                title: Text(playlist.name),
                onTap: () {
                  flux.addToPlaylist(playlist, track);
                  Navigator.pop(context);
                },
              ),
            ),
            if (flux.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Create a playlist in Library first.'),
              ),
          ],
        ),
      );
}
