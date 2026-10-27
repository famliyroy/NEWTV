import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/models/media_item.dart';
import 'skeleton_box.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    required this.item,
    this.width,
    this.onTap,
    super.key,
  });

  final MediaItem item;

  /// 卡片宽度；为空时自适应父级约束（适用于 GridView 等场景）。
  final double? width;
  final VoidCallback? onTap;

  /// 海报区宽高比（2:3）。
  static const double aspectRatio = 2 / 3;

  /// 标题与副标题之间的间距。
  static const double titleGap = 8;

  /// 文本统一行高倍数，便于与 [estimatedHeight] 对齐。
  static const double lineHeight = 1.3;

  /// 估算整张卡片（海报 + 标题 + 副标题）所需高度。
  ///
  /// 横向列表必须给定固定高度，若硬编码很容易在不同字号下溢出，
  /// 因此统一由这里根据当前字体缩放推算。
  static double estimatedHeight(
    BuildContext context, {
    double width = 132,
    bool hasSubtitle = true,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final theme = Theme.of(context).textTheme;
    final titleSize = theme.bodyMedium?.fontSize ?? 14;
    final subtitleSize = theme.bodySmall?.fontSize ?? 12;
    final posterHeight = width / aspectRatio;
    final titleHeight = scaler.scale(titleSize * lineHeight);
    final subtitleHeight = hasSubtitle ? scaler.scale(subtitleSize * lineHeight) : 0.0;
    // 末尾留 2px 余量，避免浮点误差触发的溢出告警。
    return posterHeight + titleGap + titleHeight + subtitleHeight + 2;
  }

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [widget.item.year, widget.item.remarks]
        .where((e) => e.isNotEmpty)
        .join(' · ');
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
            width: widget.width ?? double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: PosterCard.aspectRatio,
                  child: Hero(
                    tag: 'poster-${widget.item.storageKey}-${widget.item.title}',
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
                              placeholder: (context, url) => SkeletonBox(),
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
                ),
                const SizedBox(height: PosterCard.titleGap),
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: PosterCard.lineHeight,
                      ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: PosterCard.lineHeight,
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
