import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/data/repositories/danmaku_repository.dart';
import 'package:moontv_client/domain/models/danmaku.dart';
import 'package:moontv_client/features/danmaku/danmaku_clock.dart';
import 'package:moontv_client/features/danmaku/danmaku_controller.dart';
import 'package:moontv_client/features/danmaku/danmaku_overlay.dart';
import 'package:moontv_client/features/danmaku/danmaku_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptySource implements DanmakuSource {
  @override
  bool get aggregates => true;

  @override
  String get description => '测试源';

  @override
  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) async =>
      const [];

  @override
  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) async =>
      const [];

  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  }) async =>
      const [];
}

/// 可控墙钟 + 注入的 scene，用来断言 Ticker 推进出来的位置。
class _Harness {
  _Harness(this.controller, this.settings, this.scene, this.clock);

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs);
    final controller = DanmakuController(
      DanmakuRepository(_EmptySource()),
      settings,
    );
    var now = 0.0;
    final clock = DanmakuClock(now: () => now);
    final scene = DanmakuScene();
    final harness = _Harness(controller, settings, scene, clock);
    harness._readNow = () => now;
    harness._writeNow = (value) => now = value;
    return harness;
  }

  final DanmakuController controller;
  final SettingsController settings;
  final DanmakuScene scene;
  final DanmakuClock clock;

  late double Function() _readNow;
  late void Function(double) _writeNow;

  double get now => _readNow();

  void advance(double seconds) => _writeNow(_readNow() + seconds);

  Widget get widget => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: DanmakuOverlay(
              controller: controller,
              settings: settings.settings,
              scene: scene,
              clock: clock,
            ),
          ),
        ),
      );
}

void main() {
  testWidgets('播放中按墙钟连续推进，不等到下一次上报', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(10);
    await tester.pump();
    expect(h.scene.position, closeTo(10, 0.05));

    for (var i = 1; i <= 3; i++) {
      h.advance(0.1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(h.scene.position, closeTo(10 + i * 0.1, 0.02));
    }
  });

  testWidgets('暂停后弹幕完全停止，恢复后从暂停处继续（不追赶）', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(30);
    await tester.pump();
    h.advance(0.1);
    await tester.pump(const Duration(milliseconds: 16));
    // 播放器又上报一次：此时锚点与插值一致，便于断言「暂停后原地不动」。
    h.controller.setPosition(h.scene.position);
    await tester.pump();
    final paused = h.scene.position;
    expect(paused, closeTo(30.1, 0.02));

    h.controller.setPlaying(false);
    await tester.pump();
    expect(h.scene.position, closeTo(paused, 0.02));

    // 暂停期间墙钟继续走 5 秒，弹幕位置不得变化。
    h.advance(5);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(paused, 0.02));

    // 恢复：重新对锚，不把暂停的 5 秒算进去。
    h.controller.setPlaying(true);
    await tester.pump();
    expect(h.scene.position, closeTo(paused, 0.02));
    h.advance(0.2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(paused + 0.2, 0.02));
  });

  testWidgets('seek 后硬同步到新位置，不出现追赶', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(60);
    await tester.pump();
    h.advance(0.1);
    await tester.pump(const Duration(milliseconds: 16));

    h.controller.setPosition(600);
    await tester.pump();
    expect(h.scene.position, closeTo(600, 0.05));

    h.advance(0.1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(600.1, 0.02));

    // 回退 seek（例如拖动进度条往回）
    h.controller.setPosition(20);
    await tester.pump();
    expect(h.scene.position, closeTo(20, 0.05));
  });

  testWidgets('2 倍速时弹幕按 2 倍速度推进', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(100);
    await tester.pump();
    h.controller.setRate(2);
    await tester.pump();

    h.advance(0.1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(100.2, 0.03));

    h.advance(0.1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(100.4, 0.03));
  });

  testWidgets('暂停中 seek：位置立即更新且仍保持静止', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(10);
    await tester.pump();
    h.controller.setPlaying(false);
    await tester.pump();

    h.controller.setPosition(120);
    await tester.pump();
    expect(h.scene.position, closeTo(120, 0.05));

    h.advance(2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.scene.position, closeTo(120, 0.05));
  });

  testWidgets('dispose 后没有残留 Ticker（无帧回调泄漏）', (tester) async {
    final h = await _Harness.create();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(h.widget);

    h.controller.setPosition(5);
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
