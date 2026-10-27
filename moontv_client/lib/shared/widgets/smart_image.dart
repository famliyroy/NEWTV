import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/image_url.dart';
import 'skeleton_box.dart';

/// 海报图片：优先走服务端图片代理（应对豆瓣/TMDB 防盗链），
/// 代理不可用时自动回退直连原图，两者都失败才显示占位。
class SmartImage extends StatefulWidget {
  const SmartImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorBuilder,
    super.key,
  });

  final String url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final WidgetBuilder? errorBuilder;

  @override
  State<SmartImage> createState() => _SmartImageState();
}

class _SmartImageState extends State<SmartImage> {
  var _useDirect = false;

  @override
  void didUpdateWidget(SmartImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _useDirect = false;
  }

  void _fallbackToDirect() {
    if (_useDirect) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _useDirect = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final proxied = resolveImage(widget.url);
    final target = _useDirect ? directImage(widget.url) : proxied;
    final canFallback = proxied.url != directImage(widget.url).url;

    Widget image;
    if (target.isEmpty) {
      image = Container(color: scheme.surfaceContainerHighest);
    } else {
      image = CachedNetworkImage(
        imageUrl: target.url,
        httpHeaders: target.headers.isEmpty ? null : target.headers,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, url) =>
            widget.placeholder ?? const SkeletonBox(),
        errorWidget: (context, url, error) {
          if (!_useDirect && canFallback) _fallbackToDirect();
          return widget.errorBuilder?.call(context) ??
              Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.outline,
                ),
              );
        },
      );
    }

    final radius = widget.borderRadius;
    return radius == null
        ? image
        : ClipRRect(borderRadius: radius, child: image);
  }
}
