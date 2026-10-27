import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/data/repositories/danmaku_repository.dart';
import 'package:moontv_client/domain/models/danmaku.dart';
import 'package:moontv_client/domain/models/media_item.dart';
import 'package:moontv_client/features/danmaku/danmaku_controller.dart';
import 'package:moontv_client/features/danmaku/danmaku_overlay.dart';
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
}
