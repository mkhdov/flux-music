import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/flux_provider.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Search',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: flux.search,
              decoration: InputDecoration(
                hintText: 'Songs, artists, or videos',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          if (flux.searching)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (flux.searchError != null)
            Expanded(
              child: _SearchMessage(
                icon: Icons.wifi_off_rounded,
                message: flux.searchError!,
              ),
            )
          else if (flux.results.isEmpty)
            Expanded(
              child: flux.recent.isNotEmpty
                  ? ListView.builder(
                      itemCount: flux.recent.length,
                      itemBuilder: (_, index) => TrackTile(
                        track: flux.recent[index],
                        queue: flux.recent,
                      ),
                    )
                  : const _SearchMessage(
                      icon: Icons.graphic_eq_rounded,
                      message: 'Find the music moving through your day.',
                    ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: flux.results.length,
                itemBuilder: (_, index) =>
                    TrackTile(track: flux.results[index], queue: flux.results),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}
