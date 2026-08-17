import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/flux_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    return SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text(
              'Settings',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                _ThemeOption(
                  mode: 'system',
                  selected: flux.storage.themeMode,
                  onTap: flux.setTheme,
                  title: const Text('System setting'),
                  icon: Icons.brightness_auto_rounded,
                ),
                _ThemeOption(
                  mode: 'light',
                  selected: flux.storage.themeMode,
                  onTap: flux.setTheme,
                  title: const Text('Light'),
                  icon: Icons.light_mode_rounded,
                ),
                _ThemeOption(
                  mode: 'dark',
                  selected: flux.storage.themeMode,
                  onTap: flux.setTheme,
                  title: const Text('Dark'),
                  icon: Icons.dark_mode_rounded,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 6),
            child: Text(
              'ABOUT FLUX',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.headphones_rounded),
                  title: Text('Audio-only playback'),
                  subtitle: Text('Flux never renders YouTube video.'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.phone_android_rounded),
                  title: Text('On-device library'),
                  subtitle: Text(
                    'Favorites, playlists, history, and downloads stay on this device.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.icon,
  });
  final String mode;
  final String selected;
  final ValueChanged<String> onTap;
  final Widget title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: title,
    trailing: selected == mode
        ? Icon(
            Icons.check_rounded,
            color: Theme.of(context).colorScheme.primary,
          )
        : null,
    onTap: () => onTap(mode),
  );
}
