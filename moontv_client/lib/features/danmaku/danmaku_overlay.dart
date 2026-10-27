import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/config/app_settings.dart';
import 'danmaku_clock.dart';
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
    this.scene,
    this.clock,
    super.key,
  });

  final DanmakuController controller;
  final AppSettings settings;

  /// 与控制栏同步隐藏：沉浸态下不保留任何 UI 元素。
  final bool showStatus;

  /// 仅测试注入：复用外部场景/时间轴，便于断言插值结果。
  @visibleForTesting
  final DanmakuScene? scene;

  /// 仅测试注入：用可控的假墙钟。
  @visibleForTesting
  final DanmakuClock? clock;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final DanmakuScene _scene = widget.scene ?? DanmakuScene();

  /// 时间轴：播放器位置只作锚点，帧位置 = 锚点 + 墙钟差 × 播放速率。
  late final DanmakuClock _clock = widget.clock ?? DanmakuClock();

  final _signal = _RepaintSignal();
  late final _painter = _DanmakuScenePainter(scene: _scene, signal: _signal);

  late final Ticker _ticker;

  /// 胶囊文字单独用 ValueNotifier 驱动：播放位置 20Hz 的通知不应该带动
  /// 一个 widget 子树重建（只有状态真正变化时才需要）。
  final _capsule = ValueNotifier<({String text, bool visible})>(
    (text: '', visible: false),
  );

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _scene.update(
      comments: widget.controller.comments,
      settings: widget.settings,
    );
    _clock
      ..setRate(widget.controller.rate)
      ..reset(widget.controller.position);
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
    }
    _scene.visible = _visible;
    _clock.setRate(controller.rate);
    if (!_visible) {
      _syncCapsule();
      _syncTicker();
      return;
    }

    if (controller.playing) {
      // 平滑跟随：偏差小时只吃 20%，大跳变才硬同步并重建轨道。
      if (_clock.report(controller.position)) _scene.resetAllocation();
    } else {
      // 暂停：不参与插值，时间轴直接钉在播放器位置（seek 也能立刻反映）。
      _clock.reset(controller.position);
    }
    _scene.setPosition(_clock.position);
    _syncCapsule();
    _syncTicker();
    // 暂停时没有 Ticker，位置变化（seek）也要出帧。
    if (!_ticker.isActive) _signal.tick();
  }

  void _onTick(Duration _) {
    if (!_clock.anchored) return;
    _scene.setPosition(_clock.position);
    _signal.tick();
  }

  void _syncTicker() {
    final shouldRun = _visible && widget.controller.playing;
    if (shouldRun) {
      if (!_ticker.isActive) {
        // 恢复播放：重新对锚，避免把暂停期间流逝的墙钟算进弹幕位置。
        _clock
          ..setRate(widget.controller.rate)
          ..reset(widget.controller.position);
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
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
