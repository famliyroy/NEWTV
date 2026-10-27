import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/config/app_settings.dart';
import 'danmaku_controller.dart';
import 'danmaku_scene.dart';

/// 弹幕层。
///
/// 两处性能关键点：
/// 1. 位置由 [Ticker] 以 60fps 推进（播放器位置流只有 10~20Hz，
///    直接用它驱动会出现「步进式」顿挫）。播放器位置只作锚点。
/// 2. 位置更新只触发 [CustomPainter.repaint]，widget 不重建；外层
///    [RepaintBoundary] 让弹幕层与视频纹理解耦。
class DanmakuOverlay extends StatefulWidget {
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
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  final _scene = DanmakuScene();
  final _signal = _RepaintSignal();
  late final _painter = _DanmakuScenePainter(scene: _scene, signal: _signal);

  late final Ticker _ticker;

  /// 墙钟：锚点与帧推进共用同一个时基，避免 Duration 抖动累积。
  final _clock = Stopwatch()..start();

  /// 锚点「媒体位置」与「墙钟秒数」。
  double _anchorMedia = 0;
  double _anchorClock = 0;

  /// 媒体时间相对墙钟的倍速（1.0 正常，2.0 为 2 倍速）。
  double _slope = 1;
  var _anchored = false;

  /// 上一次播放器上报的位置与时刻，用于估计 [_slope]。
  double? _lastReported;
  double _lastReportTime = 0;

  /// 胶囊文字单独用 ValueNotifier 驱动：播放位置 20Hz 的通知不应该带动
  /// 一个 widget 子树重建（只有状态真正变化时才需要）。
  final _capsule = ValueNotifier<({String text, bool visible})>(
    (text: '', visible: false),
  );

  double get _now => _clock.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _scene.update(
      comments: widget.controller.comments,
      settings: widget.settings,
    );
    _resync();
    _syncCapsule();
    widget.controller.addListener(_handleControllerChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    _scene.update(
      comments: widget.controller.comments,
      settings: widget.settings,
    );
    _scene.visible = _visible;
    _syncCapsule();
    _syncTicker();
    _signal.tick();
  }

  bool get _visible =>
      widget.settings.danmakuEnabled && widget.controller.enabled;

  void _handleControllerChanged() {
    final controller = widget.controller;
    // 弹幕列表换了（加载完成/切集）才同步，纯位置更新只改锚点。
    if (!identical(_scene.comments, controller.comments)) {
      _scene.update(comments: controller.comments, settings: widget.settings);
      _scene.resetAllocation();
    }
    _scene.visible = _visible;
    if (!_visible) {
      _syncCapsule();
      _syncTicker();
      return;
    }
    _syncCapsule();
    _syncAnchor(controller.position);
    _syncTicker();
    // 暂停时没有 Ticker，位置变化（seek）也要出帧。
    if (!_ticker.isActive) _signal.tick();
  }

  /// 把插值位置对齐到播放器给出的真实位置。
  ///
  /// 注意不能用「直接跳到上报值」：播放器位置是按 PTS 量化的（几十到几百毫秒
  /// 一台阶），硬对齐会把台阶重新带回画面。这里只吃掉 20% 的误差，
  /// 收敛快且每步远小于一个像素，肉眼不可见。
  void _syncAnchor(double position) {
    final now = _now;
    if (!_anchored) {
      _anchorMedia = position;
      _anchorClock = now;
      _slope = 1;
      _anchored = true;
      _lastReported = position;
      _lastReportTime = now;
      _scene.setPosition(position);
      return;
    }

    // 用相邻两次上报估计「媒体时间 / 墙钟」比值，倍速 0.5x~3x 都能跟上。
    final dt = now - _lastReportTime;
    final delta = position - (_lastReported ?? position);
    if (dt > 0.02 && delta > 0 && delta < 3) {
      final measured = (delta / dt).clamp(0.1, 8.0);
      _slope = (_slope * 0.6 + measured * 0.4).clamp(0.1, 8.0);
    }
    _lastReported = position;
    _lastReportTime = now;

    final drift = position - _interpolatedAt(now);
    if (drift.abs() > 1.0) {
      // 真正的跳变（seek / 切集 / 长时间缓冲）：硬对锚并重建轨道。
      _anchorMedia = position;
      _anchorClock = now;
      _scene.setPosition(position);
      _scene.resetAllocation();
      return;
    }
    _anchorClock -= 0.2 * drift / _slope;
    // 暂停时没有 Ticker，这里顺手把场景位置刷到最新，保证暂停/慢帧也准确。
    _scene.setPosition(_interpolatedAt(now));
  }

  double _interpolatedAt(double now) =>
      _anchorMedia + (now - _anchorClock) * _slope;

  void _onTick(Duration _) {
    if (!_anchored) return;
    _scene.setPosition(_interpolatedAt(_now));
    _signal.tick();
  }

  void _syncTicker() {
    final shouldRun = _visible && widget.controller.playing;
    if (shouldRun) {
      if (!_ticker.isActive) {
        // 恢复播放：先对锚，避免把暂停期间的时间差算进去。
        _resync();
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _resync() {
    _anchored = false;
    _syncAnchor(widget.controller.position);
  }

  void _syncCapsule() {
    final controller = widget.controller;
    final text = controller.loading && controller.status.isEmpty
        ? '弹幕加载中…'
        : controller.status;
    final next = (text: text, visible: widget.showStatus && text.isNotEmpty);
    if (_capsule.value != next) _capsule.value = next;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _ticker.dispose();
    _scene.dispose();
    _signal.dispose();
    _capsule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _painter),
            ),
          ),
          // Positioned 必须是 Stack 的直接子节点，这里用 Align 定位。
          ValueListenableBuilder<({String text, bool visible})>(
            valueListenable: _capsule,
            builder: (context, value, child) {
              return Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 46),
                  child: IgnorePointer(
                    ignoring: !value.visible,
                    child: AnimatedOpacity(
                      opacity: value.visible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Text(
                            value.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RepaintSignal extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _DanmakuScenePainter extends CustomPainter {
  _DanmakuScenePainter({required this.scene, required this.signal})
      : super(repaint: signal);

  final DanmakuScene scene;
  final _RepaintSignal signal;

  @override
  void paint(Canvas canvas, Size size) => scene.paint(canvas, size);

  // 重绘由 [signal] 驱动，painter 实例本身不会替换。
  @override
  bool shouldRepaint(covariant _DanmakuScenePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
