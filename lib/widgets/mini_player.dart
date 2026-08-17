import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/flux_provider.dart';
import '../screens/now_playing_screen.dart';
import 'artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    final player = flux.player;
    final track = player.current;
    if (track == null) return const SizedBox.shrink();
    final showPlayLoading = flux.isPlayButtonLoading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withValues(alpha: .88),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const NowPlayingScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          FadeTransition(opacity: animation, child: child),
                ),
              ),
              child: SizedBox(
                height: 66,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Hero(
                      tag: 'flux-art-${track.id}',
                      child: Artwork(
                        url: track.thumbnailUrl,
                        size: 50,
                        borderRadius: 9,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: showPlayLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Icon(
                              player.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                            ),
                      onPressed: showPlayLoading ? null : player.toggle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
