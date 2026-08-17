import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.borderRadius = 14,
  });
  final String url;
  final double? size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(
      width: size,
      height: size,
      child: url.isEmpty
          ? _fallback(context)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (context, imageUrl, error) =>
                  url.contains('maxresdefault')
                  ? CachedNetworkImage(
                      imageUrl: url.replaceFirst('maxresdefault', 'hqdefault'),
                      fit: BoxFit.cover,
                      errorWidget: (context, imageUrl, error) =>
                          _fallback(context),
                    )
                  : _fallback(context),
              placeholder: (context, imageUrl) => _fallback(context),
            ),
    ),
  );

  Widget _fallback(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Icon(
      Icons.music_note_rounded,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class BlurredArtworkBackground extends StatelessWidget {
  const BlurredArtworkBackground({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Opacity(
      opacity: .38,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
        child: Transform.scale(
          scale: 1.25,
          child: Artwork(url: url, borderRadius: 0),
        ),
      ),
    ),
  );
}

class CoverGradientBackground extends StatefulWidget {
  const CoverGradientBackground({super.key, required this.url});
  final String url;

  @override
  State<CoverGradientBackground> createState() =>
      _CoverGradientBackgroundState();
}

class _CoverGradientBackgroundState extends State<CoverGradientBackground> {
  List<Color> _gradientColors = const [
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
  ];
  bool _gradientsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requestGradientLoad();
  }

  @override
  void didUpdateWidget(CoverGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _gradientsRequested = false;
      _requestGradientLoad();
    }
  }

  void _requestGradientLoad() {
    if (_gradientsRequested) return;
    _gradientsRequested = true;
    _loadColors();
  }

  Future<void> _loadColors() async {
    if (widget.url.isEmpty) return;
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(widget.url),
        brightness: Theme.of(context).brightness,
      );
      if (!mounted) return;
      setState(() {
        _gradientColors = [
          scheme.primary.withValues(alpha: 0.85),
          scheme.secondary.withValues(alpha: 0.75),
          scheme.tertiary.withValues(alpha: 0.65),
        ];
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = Theme.of(context).colorScheme;
      setState(() {
        _gradientColors = [
          fallback.primaryContainer.withValues(alpha: 0.9),
          fallback.secondaryContainer.withValues(alpha: 0.8),
          fallback.surface.withValues(alpha: 0.95),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: _gradientColors,
        ),
      ),
    ),
  );
}
