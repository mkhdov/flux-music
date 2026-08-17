import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/flux_provider.dart';
import '../widgets/artwork.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final player = context.watch<FluxProvider>().player;
    final tracks = player.queue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Up Next', style: TextStyle(fontSize: 22)),
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('Your queue is empty.'))
          : ReorderableListView.builder(
              itemCount: tracks.length,
              onReorder: player.moveQueueItem,
              itemBuilder: (_, index) {
                final track = tracks[index];
                return ListTile(
                  key: ValueKey(track.id),
                  leading: Artwork(
                    url: track.thumbnailUrl,
                    size: 52,
                    borderRadius: 9,
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => player.removeQueueItem(index),
                  ),
                  onTap: () => player.skipTo(index),
                );
              },
            ),
    );
  }
}
