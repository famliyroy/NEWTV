import 'package:flutter/material.dart';

import '../../core/config/app_settings.dart';
import 'danmaku_controller.dart';
import 'danmaku_scene.dart';

/// 弹幕层。
///
/// 位置变化不再重建 widget：State 持久持有 [DanmakuScene]（内含 TextPainter
/// 缓存与轨道分配），通过 [CustomPainter.repaint] 的 Listenable 只触发重绘，
/// 外面再包 [RepaintBoundary] 与视频解耦。
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

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  final _scene = DanmakuScene();
  final _signal = _RepaintSignal();
  late final _painter = _DanmakuScenePainter(scene: _scene, signal: _signal);

  /// 胶囊文字单独用 ValueNotifier 驱动：播放位置 20Hz 的通知不应该带动
  /// 一个 widget 子树重建（只有状态真正变化时才需要）。
  final _capsule = ValueNotifier<({String text, bool visible})>(
    (text: '', visible: false),
  );

  @override
  void initState() {
    super.initState();
    _scene.update(
      comments: widget.controller.comments,
      settings: widget.settings,
    );
    _applyRuntimeState();
    _syncCapsule();
    widget.controller.addListener(_handleControllerChanged);
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
    _applyRuntimeState();
    _syncCapsule();
    _signal.tick();
  }

  void _handleControllerChanged() {
    final controller = widget.controller;
    // 弹幕列表换了（加载完成/切集）才同步，纯位置更新只改场景内部状态。
    if (!identical(_scene.comments, controller.comments)) {
      _scene.update(comments: controller.comments, settings: widget.settings);
    }
    _applyRuntimeState();
    _syncCapsule();
    _signal.tick();
  }

  void _applyRuntimeState() {
    _scene
      ..setPosition(widget.controller.position)
      ..visible = widget.settings.danmakuEnabled && widget.controller.enabled;
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
