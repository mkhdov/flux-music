import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/flux_provider.dart';
import '../services/player_service.dart';
import '../widgets/artwork.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    final player = flux.player;
    final track = player.current;
    if (track == null) {
      return const Scaffold(body: Center(child: Text('Nothing is playing.')));
    }
    final duration = player.duration;
    final max = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = player.position.inMilliseconds
        .clamp(0, max.toInt())
        .toDouble();
    final remaining = flux.sleepRemaining;
    final showPlayLoading = flux.isPlayButtonLoading;
    final showNavLoading = flux.isNavigating;
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 350) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            CoverGradientBackground(url: track.thumbnailUrl),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .08),
                      Colors.black.withValues(alpha: .42),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 32,
                          ),
                        ),
                        const Expanded(
                          child: Column(
                            children: [
                              Text(
                                'NOW PLAYING',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                'From YouTube · Audio only',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Share.share(track.webUrl),
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Hero(
                      tag: 'flux-art-${track.id}',
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Artwork(
                          url: track.thumbnailUrl,
                          borderRadius: 24,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => flux.toggleFavorite(track),
                              icon: Icon(
                                flux.storage.isFavorite(track.id)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: flux.storage.isFavorite(track.id)
                                    ? const Color(0xFFFF375F)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Slider(
                          value: value,
                          max: max,
                          onChanged: (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_time(player.position)),
                              Text('-${_time(duration - player.position)}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: player.toggleShuffle,
                              icon: Icon(
                                Icons.shuffle_rounded,
                                color: player.shuffleEnabled
                                    ? const Color(0xFFFF375F)
                                    : null,
                              ),
                            ),
                            IconButton(
                              onPressed: showNavLoading ? null : flux.previous,
                              icon: showNavLoading
                                  ? const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.skip_previous_rounded,
                                      size: 40,
                                    ),
                            ),
                            FilledButton(
                              onPressed: showPlayLoading ? null : player.toggle,
                              style: FilledButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(17),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                disabledBackgroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.12),
                              ),
                              child: showPlayLoading
                                  ? const SizedBox(
                                      width: 39,
                                      height: 39,
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    )
                                  : Icon(
                                      player.playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 39,
                                    ),
                            ),
                            IconButton(
                              onPressed: showNavLoading ? null : flux.next,
                              icon: showNavLoading
                                  ? const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.skip_next_rounded,
                                      size: 40,
                                    ),
                            ),
                            IconButton(
                              onPressed: player.cycleRepeat,
                              icon: Icon(
                                player.loopMode == LoopMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                color: player.loopMode == LoopMode.off
                                    ? null
                                    : const Color(0xFFFF375F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Tool(
                              icon: Icons.bedtime_outlined,
                              label: remaining == null
                                  ? 'Sleep'
                                  : _time(remaining),
                              onTap: () => _sleepSheet(context, flux),
                            ),
                            _Tool(
                              icon: flux.storage.downloaded(track.id) != null
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              label: flux.downloadingId == track.id
                                  ? 'Saving…'
                                  : 'Download',
                              onTap: () => flux.download(track),
                            ),
                            _Tool(
                              icon: Icons.speed_rounded,
                              label: '${player.speed}×',
                              onTap: () => _speedSheet(context, player),
                            ),
                            _Tool(
                              icon: Icons.format_list_bulleted_rounded,
                              label: 'Queue',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const QueueScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.volume_down_rounded),
                            Expanded(
                              child: Slider(
                                value: player.volume,
                                onChanged: player.setVolume,
                              ),
                            ),
                            const Icon(Icons.volume_up_rounded),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    return '${safe.inMinutes}:${(safe.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _speedSheet(BuildContext context, PlayerService player) =>
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Playback speed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [.5, .75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (speed) => ChoiceChip(
                      label: Text('$speed×'),
                      selected: player.speed == speed,
                      onSelected: (_) {
                        player.setSpeed(speed);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 28),
          ],
        ),
      );

  void _sleepSheet(BuildContext context, FluxProvider flux) =>
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sleep Timer',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...[5, 15, 30, 45, 60].map(
              (minutes) => ListTile(
                title: Text('$minutes minutes'),
                onTap: () {
                  flux.startSleepTimer(Duration(minutes: minutes));
                  Navigator.pop(context);
                },
              ),
            ),
            if (flux.sleepRemaining != null)
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel active timer'),
                onTap: () {
                  flux.cancelSleepTimer();
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 64,
      child: Column(
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
