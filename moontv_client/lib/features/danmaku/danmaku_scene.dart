import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/config/app_settings.dart';
import '../../domain/danmaku/track_allocator.dart';
import '../../domain/models/danmaku.dart';

/// 已光栅化的单条弹幕。
///
/// 文字布局 + 描边/填充两遍绘制只在**首次出现**时进行一次，录成 [ui.Picture]；
/// 之后每帧只需 `canvas.drawPicture`（纯显示列表回放，无文本布局）。
class _Glyph {
  const _Glyph({required this.picture, required this.width, required this.height});

  final ui.Picture picture;
  final double width;
  final double height;

  void dispose() => picture.dispose();
}

/// 弹幕绘制场景。
///
/// 生命周期与画布一致（由 Overlay 的 State 持有），**不在每帧重建**：
/// - 每条弹幕预渲染为 [ui.Picture] 缓存，绘制阶段零 layout、零文本光栅；
/// - 轨道由 [DanmakuTrackAllocator] 在弹幕进场时一次性分配，飞行中不换行；
/// - 位置由 Overlay 的 Ticker 以 60fps 推进，只触发重绘，不触发 widget 重建。
class DanmakuScene {
  /// 同屏绘制上限：超过轨道容量两倍没有意义，只会互相压字。
  static const maxPaintPerFrame = 40;

  /// 图形缓存上限。透明度/颜色变化会生成新 key，超过此值整体清空，
  /// 避免长时间播放 + 反复调参把内存撑爆。
  static const maxGlyphs = 1200;

  List<DanmakuComment> _comments = const [];
  AppSettings? _settings;
  double _position = 0;
  double _lastPosition = 0;

  /// 由 Overlay 根据「全局开关 + 播放页开关」设置。
  var visible = true;

  final _allocator = DanmakuTrackAllocator();
  final _glyphs = <String, _Glyph>{};

  /// 当前图形缓存对应的字号；字号变化才需要整体作废。
  double _glyphFontSize = -1;

  List<DanmakuComment> get comments => _comments;

  /// 当前绘制所使用的时间位置（秒）。由 Overlay 的 Ticker 每帧写入。
  double get position => _position;

  /// 弹幕列表或渲染设置变化时调用。
  ///
  /// 只对**影响布局**的字段（字号/速度/显示区域）作废轨道分配，
  /// 只有**字号**变化才清空图形缓存 —— 拖透明度滑块不再重建上千条弹幕。
  void update({
    required List<DanmakuComment> comments,
    required AppSettings settings,
  }) {
    final previous = _settings;
    final commentsChanged = !identical(_comments, comments);
    if (!commentsChanged && identical(previous, settings)) return;
    _comments = comments;
    _settings = settings;
    if (previous == null) return;
    if (previous.danmakuFontSize != settings.danmakuFontSize) {
      _clearGlyphs();
    }
    final layoutChanged = previous.danmakuFontSize != settings.danmakuFontSize ||
        previous.danmakuSpeed != settings.danmakuSpeed ||
        previous.danmakuArea != settings.danmakuArea;
    if (commentsChanged || layoutChanged) _allocator.reset();
  }

  void setPosition(double seconds) {
    // seek / 切集造成的跳变：轨道状态已无意义，重新分配。
    if ((seconds - _lastPosition).abs() > 0.75) _allocator.reset();
    _lastPosition = seconds;
    _position = seconds;
  }

  /// seek 后强制重新分配轨道（即使位置跳变未超过阈值）。
  void resetAllocation() => _allocator.reset();

  void paint(Canvas canvas, Size size) {
    final settings = _settings;
    if (!visible || settings == null || _comments.isEmpty || size.isEmpty) {
      return;
    }
    final fontSize = settings.danmakuFontSize;
    if (_glyphFontSize != fontSize) {
      _clearGlyphs();
      _glyphFontSize = fontSize;
    }
    // 清理放在绘制前：避免在同一帧里「画完立刻 dispose」，
    // 那会动到本帧显示列表可能仍在引用的 Picture。
    if (_glyphs.length > maxGlyphs) _clearGlyphs();
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
    // 透明度量化到 5%：拖动结束时只产生一个有意义的 key，
    // 拖动过程中滑块走本地 state，不会提交到这里。
    final opacityKey = (settings.danmakuOpacity.clamp(0.0, 1.0) * 20).round();

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

      final glyph = _glyphFor(
        comment,
        fontSize: fontSize,
        opacityKey: opacityKey,
        stroke: _needsStroke(comment.color),
      );
      final row = _allocator.allocate(
        key: _keyOf(comment),
        mode: comment.mode,
        time: comment.time,
        width: glyph.width,
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

      final offset =
          _offsetFor(comment, row, size, rowHeight, window, glyph.width);
      // Canvas.drawPicture 不接受偏移，只能 translate（save/restore 成本极低）。
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawPicture(glyph.picture);
      canvas.restore();
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

  /// 浅色（含白色）弹幕不描边：与网页版一致，靠字重保证可读性。
  /// 每帧少一半文本绘制，是 60fps 的关键之一。
  static bool _needsStroke(int color) {
    return Color(color).computeLuminance() < 0.62;
  }

  _Glyph _glyphFor(
    DanmakuComment comment, {
    required double fontSize,
    required int opacityKey,
    required bool stroke,
  }) {
    // 影响渲染结果的参数全部进 key；透明度取量化值，
    // 既能让调参生效，又不会因为浮点抖动产生大量近似缓存。
    final key = '${comment.text}|$fontSize|${comment.color}|$opacityKey'
        '${stroke ? 's' : 'f'}';
    final cached = _glyphs[key];
    if (cached != null) return cached;

    final alpha = (opacityKey / 20).clamp(0.0, 1.0);
    final fillStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: Color(comment.color).withValues(alpha: alpha),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (stroke) {
      // 细描边（1.8）替代旧的 2.6 + 模糊阴影：省掉模糊采样。
      final strokePainter = TextPainter(
        text: TextSpan(
          text: comment.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF000000).withValues(alpha: alpha * 0.72),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      strokePainter.paint(canvas, Offset.zero);
      strokePainter.dispose();
    }

    final fillPainter = TextPainter(
      text: TextSpan(text: comment.text, style: fillStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    fillPainter.paint(canvas, Offset.zero);
    final size = fillPainter.size;
    fillPainter.dispose();

    final glyph = _Glyph(
      picture: recorder.endRecording(),
      width: size.width,
      height: size.height,
    );
    _glyphs[key] = glyph;
    return glyph;
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

  void _clearGlyphs() {
    for (final glyph in _glyphs.values) {
      glyph.dispose();
    }
    _glyphs.clear();
  }

  void dispose() => _clearGlyphs();
}
