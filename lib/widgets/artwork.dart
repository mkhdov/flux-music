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
