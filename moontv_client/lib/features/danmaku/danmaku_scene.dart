import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/app_settings.dart';
import '../../domain/danmaku/track_allocator.dart';
import '../../domain/models/danmaku.dart';

/// 弹幕绘制场景。
///
/// 生命周期与画布一致（由 Overlay 的 State 持有），**不在每帧重建**：
/// - TextPainter 按「文本 + 字号 + 颜色 + 透明度」缓存，绘制阶段零 layout；
/// - 轨道由 [DanmakuTrackAllocator] 在弹幕进场时一次性分配，飞行中不换行；
/// - 位置更新只改 [_position] 并触发重绘，不触发 widget 重建。
class DanmakuScene {
  /// 同屏绘制上限：超过轨道容量两倍没有意义，只会互相压字。
  static const maxPaintPerFrame = 40;

  List<DanmakuComment> _comments = const [];
  AppSettings? _settings;
  double _position = 0;
  double _lastPosition = 0;

  /// 由 Overlay 根据「全局开关 + 播放页开关」设置。
  var visible = true;

  final _allocator = DanmakuTrackAllocator();
  final _strokePainters = <String, TextPainter>{};
  final _fillPainters = <String, TextPainter>{};

  List<DanmakuComment> get comments => _comments;

  /// 弹幕列表或渲染设置变化时调用；两者都会改变文字宽度与轨道占用。
  void update({
    required List<DanmakuComment> comments,
    required AppSettings settings,
  }) {
    final commentsChanged = !identical(_comments, comments);
    final settingsChanged = _settings != settings;
    if (!commentsChanged && !settingsChanged) return;
    _comments = comments;
    _settings = settings;
    _clearPainters();
    // 字号/显示区域变化会改变轨道数与文字宽度，旧分配作废。
    _allocator.reset();
  }

  void setPosition(double seconds) {
    // seek / 切集造成的跳变：轨道状态已无意义，重新分配。
    if ((seconds - _lastPosition).abs() > 0.75) _allocator.reset();
    _lastPosition = seconds;
    _position = seconds;
  }

  void paint(Canvas canvas, Size size) {
    final settings = _settings;
    if (!visible || settings == null || _comments.isEmpty || size.isEmpty) {
      return;
    }
    final fontSize = settings.danmakuFontSize;
    final rowHeight = fontSize * 1.6;
    final maxArea = settings.danmakuArea.clamp(0.25, 1.0);
    final usableHeight =
        size.height * (0.85 * maxArea - 0.15).clamp(0.15, 0.70);
    final scrollRows = (usableHeight / rowHeight).floor().clamp(1, 18);
    final topRows = (size.height * 0.15 / rowHeight).floor().clamp(1, 3);
    final bottomRows = (size.height * 0.20 / rowHeight).floor().clamp(1, 4);
    _allocator.configure(
      scrollRows: scrollRows,
      topRows: topRows,
      bottomRows: bottomRows,
    );

    final window =
        (size.width / 220 / settings.danmakuSpeed).clamp(5.0, 14.0).toDouble();
    final fixedDuration = 4.5 / settings.danmakuSpeed;
    final gap = fontSize * 1.5;
    final limit = math.min(scrollRows * 2, maxPaintPerFrame);

    final startIndex = _lowerBound(_comments, _position - window);
    var painted = 0;
    for (var index = startIndex; index < _comments.length; index++) {
      if (painted >= limit) break;
      final comment = _comments[index];
      if (comment.time > _position + 0.5) break;
      final age = _position - comment.time;
      if (age < 0) continue;
      final span = comment.mode == DanmakuMode.scroll ? window : fixedDuration;
      if (age > span) continue;
      if (_isBlocked(comment.text, settings.blockedWords)) continue;

      final fill = _painterFor(
        comment,
        fontSize: fontSize,
        opacity: settings.danmakuOpacity,
        stroke: false,
      );
      final row = _allocator.allocate(
        key: _keyOf(comment),
        mode: comment.mode,
        time: comment.time,
        width: fill.width,
        screenWidth: size.width,
        window: window,
        fixedDuration: fixedDuration,
        gap: gap,
      );
      // 轨道全满 → 丢弃这条，宁缺毋滥（避免一屏叠成墙），并记住不要再放。
      if (row == null) {
        _allocator.reject(_keyOf(comment));
        continue;
      }

      final stroke = _painterFor(
        comment,
        fontSize: fontSize,
        opacity: settings.danmakuOpacity,
        stroke: true,
      );
      final offset = _offsetFor(comment, row, size, rowHeight, window, fill.width);
      stroke.paint(canvas, offset);
      fill.paint(canvas, offset);
      painted++;
    }
  }

  Offset _offsetFor(
    DanmakuComment comment,
    int row,
    Size size,
    double rowHeight,
    double window,
    double width,
  ) {
    switch (comment.mode) {
      case DanmakuMode.scroll:
        final progress = ((_position - comment.time) / window).clamp(0.0, 1.0);
        final x = size.width - progress * (size.width + width);
        return Offset(x, size.height * 0.15 + row * rowHeight);
      case DanmakuMode.top:
        return Offset((size.width - width) / 2, row * rowHeight + 8);
      case DanmakuMode.bottom:
        return Offset(
          (size.width - width) / 2,
          size.height - (row + 1) * rowHeight - 8,
        );
    }
  }

  String _keyOf(DanmakuComment comment) =>
      '${comment.source}|${comment.id}|${comment.time}|${comment.text}';

  TextPainter _painterFor(
    DanmakuComment comment, {
    required double fontSize,
    required double opacity,
    required bool stroke,
  }) {
    final cache = stroke ? _strokePainters : _fillPainters;
    // 影响渲染结果的参数全部进 key：透明度若不入 key，持久化缓存会导致
    // 「调了透明度没反应」。
    final key =
        '${comment.text}|$fontSize|${comment.color}|$opacity|${stroke ? 's' : 'f'}';
    final cached = cache[key];
    if (cached != null) return cached;
    final style = stroke
        // 用描边替代 blurRadius 阴影：省掉每帧的模糊采样。
        ? TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xCC000000),
          )
        : TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Color(comment.color).withValues(alpha: opacity),
          );
    final painter = TextPainter(
      text: TextSpan(text: comment.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    cache[key] = painter;
    return painter;
  }

  bool _isBlocked(String text, String blockedWords) {
    final blocked = blockedWords.trim();
    if (blocked.isEmpty) return false;
    for (final word in blocked.split(RegExp(r'[,，\n]'))) {
      final item = word.trim();
      if (item.isNotEmpty && text.contains(item)) return true;
    }
    return false;
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

  void _clearPainters() {
    for (final painter in _strokePainters.values) {
      painter.dispose();
    }
    for (final painter in _fillPainters.values) {
      painter.dispose();
    }
    _strokePainters.clear();
    _fillPainters.clear();
  }

  void dispose() => _clearPainters();
}
