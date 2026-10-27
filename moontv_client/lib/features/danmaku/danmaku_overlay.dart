import 'package:flutter/material.dart';

import '../../core/config/app_settings.dart';
import '../../domain/models/danmaku.dart';
import 'danmaku_controller.dart';

class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    required this.controller,
    required this.settings,
    this.showStatus = true,
    super.key,
  });

  final DanmakuController controller;
  final AppSettings settings;

  /// 与控制栏同步隐藏：沉浸态下不保留任何 UI 元素。
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final status = controller.loading && controller.status.isEmpty
              ? '弹幕加载中…'
              : controller.status;
          final visible = showStatus && status.isNotEmpty;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (settings.danmakuEnabled && controller.enabled)
                CustomPaint(
                  painter: DanmakuPainter(
                    comments: controller.comments,
                    position: controller.position,
                    settings: settings,
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 46,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DanmakuPainter extends CustomPainter {
  DanmakuPainter({
    required this.comments,
    required this.position,
    required this.settings,
  });

  final List<DanmakuComment> comments;
  final double position;
  final AppSettings settings;
  final _painters = <String, TextPainter>{};
  final _trackMemory = <String, int>{};

  @override
  void paint(Canvas canvas, Size size) {
    if (comments.isEmpty || size.isEmpty) return;
    final fontSize = settings.danmakuFontSize;
    final rowHeight = fontSize * 1.6;
    final maxArea = settings.danmakuArea.clamp(0.25, 1.0);
    final usableHeight = size.height * (0.85 * maxArea - 0.15).clamp(0.15, 0.70);
    final rows = (usableHeight / rowHeight).floor().clamp(1, 24);
    final topRows = (size.height * 0.15 / rowHeight).floor().clamp(1, 4);
    final bottomRows = (size.height * 0.20 / rowHeight).floor().clamp(1, 5);
    final maxWindow = _windowFor(DanmakuMode.scroll, size, fontSize);
    final startIndex = _lowerBound(comments, position - maxWindow);
    final active = <DanmakuComment>[];
    for (var i = startIndex; i < comments.length; i++) {
      final comment = comments[i];
      if (comment.time > position + 0.5) break;
      final age = position - comment.time;
      if (age < 0 || age > _windowFor(comment.mode, size, fontSize)) continue;
      if (active.length >= 80) break;
      active.add(comment);
    }

    for (var index = 0; index < active.length; index++) {
      final comment = active[index];
      if (_isBlocked(comment.text)) continue;
      final painter = _painterFor(comment, fontSize);
      switch (comment.mode) {
        case DanmakuMode.scroll:
          final row = _rememberedRow(comment.userHash, index, rows);
          final window = _windowFor(comment.mode, size, fontSize);
          final progress = ((position - comment.time) / window).clamp(0.0, 1.0);
          final x = size.width - progress * (size.width + painter.width);
          final y = size.height * 0.15 + row * rowHeight;
          _paintText(canvas, painter, Offset(x, y), comment);
        case DanmakuMode.top:
          final row = index % topRows;
          final x = (size.width - painter.width) / 2;
          _paintText(canvas, painter, Offset(x, row * rowHeight + 8), comment);
        case DanmakuMode.bottom:
          final row = index % bottomRows;
          final x = (size.width - painter.width) / 2;
          _paintText(canvas, painter, Offset(x, size.height - (row + 1) * rowHeight - 8), comment);
      }
    }
  }

  static int _lowerBound(List<DanmakuComment> items, double minTime) {
    var low = 0;
    var high = items.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (items[mid].time < minTime) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  bool _isBlocked(String text) {
    final blocked = settings.blockedWords.trim();
    if (blocked.isEmpty) return false;
    for (final word in blocked.split(RegExp(r'[,，\n]'))) {
      final item = word.trim();
      if (item.isNotEmpty && text.contains(item)) return true;
    }
    return false;
  }

  double _windowFor(DanmakuMode mode, Size size, double fontSize) {
    if (mode == DanmakuMode.scroll) {
      return (size.width / 220 / settings.danmakuSpeed).clamp(5.0, 14.0).toDouble();
    }
    return 4.5 / settings.danmakuSpeed;
  }

  int _rememberedRow(String key, int fallback, int rows) {
    if (key.isEmpty) return fallback % rows;
    return _trackMemory.putIfAbsent(key, () => fallback % rows);
  }

  TextPainter _painterFor(DanmakuComment comment, double fontSize) {
    final key = '${comment.source}:${comment.id}:${comment.text}:$fontSize';
    return _painters.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: comment.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Color(comment.color).withValues(alpha: settings.danmakuOpacity),
            shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 1600),
    );
  }

  void _paintText(Canvas canvas, TextPainter painter, Offset offset, DanmakuComment comment) {
    if (offset.dy < 0 || offset.dy > 10000) return;
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.comments != comments ||
        oldDelegate.settings != settings;
  }
}
