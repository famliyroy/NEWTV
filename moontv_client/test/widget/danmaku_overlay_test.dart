import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/data/repositories/danmaku_repository.dart';
import 'package:moontv_client/domain/models/danmaku.dart';
import 'package:moontv_client/domain/models/media_item.dart';
import 'package:moontv_client/features/danmaku/danmaku_controller.dart';
import 'package:moontv_client/features/danmaku/danmaku_overlay.dart';
import 'package:moontv_client/features/danmaku/danmaku_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements DanmakuSource {
  _FakeSource(this._data);

  final List<DanmakuComment> _data;

  @override
  bool get aggregates => true;

  @override
  String get description => '测试源';

  @override
  Future<List<DanmakuAnime>> search(String keyword, {Duration? timeout}) async =>
      const [DanmakuAnime(animeId: 'a1', animeTitle: '测试番剧', source: 'dandan')];

  @override
  Future<List<DanmakuEpisode>> episodes(String animeId, {Duration? timeout}) async =>
      const [DanmakuEpisode(episodeId: 'e1', episodeTitle: '第1话')];

  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    required String source,
    Duration? timeout,
  }      ) async =>
      _data;
}

PlaybackContext _context() => const PlaybackContext(
      item: MediaItem(
        id: '1',
        title: '测试番剧',
        source: 'test',
        sourceName: '测试源',
        episodes: ['https://example.com/index.m3u8'],
      ),
      episodeIndex: 0,
    );

List<DanmakuComment> _comments(int count) {
  return List<DanmakuComment>.generate(
    count,
    (index) => DanmakuComment(
      time: index * 0.02,
      text: '弹幕内容 $index',
      source: 'dandan',
      id: '$index',
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('大量同屏弹幕可绘制且不抛异常', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences);
    final controller = DanmakuController(
      DanmakuRepository(_FakeSource(_comments(300))),
      settings,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: DanmakuOverlay(controller: controller, settings: settings.settings),
          ),
        ),
      ),
    );

    // loadFor 包含真实异步（缓存文件 IO），必须放在 runAsync 里，
    // 否则 testWidgets 的假时钟会让 await 永不返回。
    await tester.runAsync(() => controller.loadFor(_context()));
    await tester.pump();
    expect(controller.comments.length, 300);

    // 推进播放位置，逐帧重绘（此路径此前会每帧重建 painter）。
    for (var i = 1; i <= 30; i++) {
      controller.setPosition(i * 0.1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    // 让状态胶囊的 TTL 计时器跑完，避免残留 Timer。
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('弹幕开关关闭后不绘制且不报错', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences);
    final controller = DanmakuController(
      DanmakuRepository(_FakeSource(_comments(50))),
      settings,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DanmakuOverlay(controller: controller, settings: settings.settings),
      ),
    );
    await tester.runAsync(() => controller.loadFor(_context()));
    await tester.pump();

    await settings.update(settings.settings.copyWith(danmakuEnabled: false));
    await tester.pump();
    expect(controller.enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('渲染参数热更新不抛异常（字号/透明度/速度/显示区域）', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences);
    final controller = DanmakuController(
      DanmakuRepository(_FakeSource(_comments(200))),
      settings,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 400,
          child: DanmakuOverlay(
            controller: controller,
            settings: settings.settings,
          ),
        ),
      ),
    );
    await tester.runAsync(() => controller.loadFor(_context()));
    await tester.pump();
    controller.setPosition(1.2);
    await tester.pump(const Duration(milliseconds: 16));

    for (final next in [
      settings.settings.copyWith(danmakuOpacity: 0.4),
      settings.settings.copyWith(danmakuFontSize: 30),
      settings.settings.copyWith(danmakuSpeed: 1.6),
      settings.settings.copyWith(danmakuArea: 0.5),
      settings.settings.copyWith(blockedWords: '弹幕内容 1'),
    ]) {
      await settings.update(next);
      // 必须重建 Overlay 才能把新设置传下去（播放页就是 ref.watch 重建）。
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 400,
            child: DanmakuOverlay(
              controller: controller,
              settings: settings.settings,
            ),
          ),
        ),
      );
      controller.setPosition(1.4);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(seconds: 6));
  });

  test('加载完成后暴露数据源与命中信息', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = SettingsController(preferences);
    final controller = DanmakuController(
      DanmakuRepository(_FakeSource(_comments(3))),
      settings,
    );

    await controller.loadFor(_context());
    expect(controller.sourceDescription, '测试源');
    expect(controller.matchedTitle, '测试番剧');
    expect(controller.matchedEpisode, '第1话');
    expect(controller.providerName, 'dandan');
    expect(controller.comments.length, 3);
  });

  test('位置跳变（seek / 广告断层）后丢弃 reset 前已进场弹幕，不从屏幕中间闪现', () {
    final scene = DanmakuScene();
    addTearDown(scene.dispose);

    const comments = [
      DanmakuComment(
        time: 16.5,
        text: '跳变前滚动弹幕（应丢弃）',
        mode: DanmakuMode.scroll,
        source: 'dandan',
        id: 'old_scroll',
      ),
      DanmakuComment(
        time: 18.0,
        text: '跳变前顶部弹幕（应丢弃）',
        mode: DanmakuMode.top,
        source: 'dandan',
        id: 'old_top',
      ),
      DanmakuComment(
        time: 19.0,
        text: '跳变前底部弹幕（应丢弃）',
        mode: DanmakuMode.bottom,
        source: 'dandan',
        id: 'old_bottom',
      ),
      DanmakuComment(
        time: 19.8,
        text: '刚进场弹幕（保留）',
        mode: DanmakuMode.scroll,
        source: 'dandan',
        id: 'edge_scroll',
      ),
      DanmakuComment(
        time: 20.0,
        text: '新进场弹幕（保留）',
        mode: DanmakuMode.scroll,
        source: 'dandan',
        id: 'new_scroll',
      ),
    ];

    scene.update(comments: comments, settings: const AppSettings());
    expect(scene.resetAtPosition, isNull);

    // 从 0s 跳变到 20.0s（差值 > 0.75s），触发 reset 并记录 _resetAtPosition = 20.0。
    scene.setPosition(20.0);
    expect(scene.resetAtPosition, 20.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    scene.paint(canvas, const Size(800, 450));
    recorder.endRecording().dispose();

    final paintedIds =
        scene.debugLastPaintedComments.map((c) => c.id).toList();
    // comment.time < 20.0 - 0.3 (19.7) 的三条旧弹幕全部被跳过，不会闪现在屏幕中间。
    expect(paintedIds, isNot(contains('old_scroll')));
    expect(paintedIds, isNot(contains('old_top')));
    expect(paintedIds, isNot(contains('old_bottom')));
    // >= 19.7 的新弹幕正常从右缘进场绘制。
    expect(paintedIds, containsAll(['edge_scroll', 'new_scroll']));

    // 新一轮评论加载 update() 时清除 reset 状态。
    scene.update(
      comments: List<DanmakuComment>.from(comments),
      settings: const AppSettings(),
    );
    expect(scene.resetAtPosition, isNull);
  });
}
