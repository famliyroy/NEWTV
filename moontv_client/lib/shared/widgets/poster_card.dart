import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/models/media_item.dart';
import 'skeleton_box.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    required this.item,
    this.width = 132,
    this.onTap,
    super.key,
  });

  final MediaItem item;
  final double width;
  final VoidCallback? onTap;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.item.poster.isEmpty)
                          Container(color: scheme.surfaceContainerHighest)
                        else
                          CachedNetworkImage(
                            imageUrl: widget.item.poster,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const SkeletonBox(height: 198),
                            errorWidget: (context, url, error) => Container(
                              color: scheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        AnimatedOpacity(
                          opacity: _hovered ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              border: Border.all(color: scheme.primary.withValues(alpha: 0.72), width: 2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 42),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (widget.item.remarks.isNotEmpty || widget.item.year.isNotEmpty)
                  Text(
                    [widget.item.year, widget.item.remarks].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
