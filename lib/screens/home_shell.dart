import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/flux_provider.dart';
import '../widgets/mini_player.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 1;
  final _pages = const [SearchScreen(), LibraryScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    final error = context.watch<FluxProvider>().actionError;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),
          if (error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 112,
              child: MaterialBanner(
                content: Text(error),
                actions: [
                  TextButton(
                    onPressed: () =>
                        context.read<FluxProvider>().actionError = null,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
