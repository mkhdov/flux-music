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
              'STREAMING',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const _YoutubeSessionCard(),
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

class _YoutubeSessionCard extends StatefulWidget {
  const _YoutubeSessionCard();
  @override
  State<_YoutubeSessionCard> createState() => _YoutubeSessionCardState();
}

class _YoutubeSessionCardState extends State<_YoutubeSessionCard> {
  final _controller = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flux = context.watch<FluxProvider>();
    final active = flux.isSignedIn;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              active
                  ? Icons.verified_user_rounded
                  : Icons.person_outline_rounded,
            ),
            title: Text(
              active
                  ? 'Signed-in YouTube session'
                  : 'Anonymous YouTube session',
            ),
            subtitle: Text(
              active
                  ? 'Streams are resolved under your session, which can bypass '
                        'bot-detection 403s that anonymous extraction hits.'
                  : 'Paste the cookie header of a logged-in YouTube tab in '
                        'your browser to resolve streams under your session.',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _controller,
              obscureText: _obscured,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Session cookie',
                hintText: 'Starts with CONSENT=...; SID=...; SAPISID=...',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => flux.setSessionCookie(_controller.text),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save session'),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: flux.clearSessionCookie,
                      icon: const Icon(Icons.delete_rounded),
                      label: const Text('Clear'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
