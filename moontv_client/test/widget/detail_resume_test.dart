import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/auth/secure_cookie_storage.dart';
import 'package:moontv_client/core/auth/session_manager.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/core/config/server_config.dart';
import 'package:moontv_client/core/network/dio_client.dart';
import 'package:moontv_client/data/api/auth_api.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/data/api/media_api.dart';
import 'package:moontv_client/data/app_dependencies.dart';
import 'package:moontv_client/data/repositories/danmaku_repository.dart';
import 'package:moontv_client/data/repositories/media_repository.dart';
import 'package:moontv_client/domain/models/danmaku.dart';
import 'package:moontv_client/domain/models/media_item.dart';
import 'package:moontv_client/features/detail/detail_page.dart';
import 'package:moontv_client/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMediaApi extends MediaApi {
  _FakeMediaApi({required this.detailItem, required this.records}) : super(Dio());

  final MediaItem detailItem;
  List<MediaItem> records;

  /// 非空时 history() 会挂起，用来模拟「迟到的异步查询」。
  Completer<List<MediaItem>>? historyGate;

  @override
  Future<MediaItem> detail(MediaItem item) async => detailItem;

  @override
  Future<List<MediaItem>> history() async =>
      historyGate == null ? records : historyGate!.future;

  @override
  Future<List<MediaItem>> favorites() async => const [];
}

class _EmptyDanmakuSource implements DanmakuSource {
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

MediaItem _item({
  int episodeCount = 5,
  int lastEpisodeIndex = 0,
  int playTimeSeconds = 0,
  int totalTimeSeconds = 0,
}) {
  return MediaItem(
    id: '100',
    title: '测试剧',
    source: 'cj',
    sourceName: '量子',
    // 不给海报，避免测试里发起图片请求。
    episodes: List.generate(episodeCount, (index) => 'https://a/$index.m3u8'),
    lastEpisodeIndex: lastEpisodeIndex,
    playTimeSeconds: playTimeSeconds,
    totalTimeSeconds: totalTimeSeconds,
  );
}

Future<AppDependencies> _dependencies(_FakeMediaApi api) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage();
  final cookieJar = PersistCookieJar(
    storage: SecureCookieStorage(secureStorage),
    persistSession: true,
  );
  final settings = SettingsController(preferences);
  return AppDependencies(
    preferences: preferences,
    secureStorage: secureStorage,
    serverStore: ServerConfigStore(secureStorage),
    settings: settings,
    cookieJar: cookieJar,
    session: SessionManager(cookieJar, null, false),
    dioClient: DioClient(cookieJar: cookieJar, onSessionExpired: () async {}),
    authApi: AuthApi(Dio()),
    mediaRepository: MediaRepository(api),
    danmakuRepository: DanmakuRepository(_EmptyDanmakuSource()),
  );
}

Widget _host(AppDependencies dependencies, MediaItem initial) {
  return ProviderScope(
    overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
    child: MaterialApp(home: DetailPage(initialItem: initial)),
  );
}

void main() {
  testWidgets('从搜索结果进入也能恢复上次集数与断点', (tester) async {
    final api = _FakeMediaApi(
      detailItem: _item(),
      records: [
        _item(lastEpisodeIndex: 1, playTimeSeconds: 73, totalTimeSeconds: 2700),
      ],
    );
    final dependencies = await _dependencies(api);

    // 搜索结果条目本身没有播放记录信息。
    await tester.pumpWidget(_host(dependencies, _item()));
    // 详情 + 收藏 + 记录查询都是真实异步。
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('播放 第 2 集'), findsOneWidget, reason: '应定位到上次的集数');
    expect(find.text('上次看到 第 2 集 01:13'), findsOneWidget);
    // 记录所在集有「上次」角标。
    expect(find.text('上次'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('用户先手动选集，迟到的记录查询不得改回去', (tester) async {
    final gate = Completer<List<MediaItem>>();
    final api = _FakeMediaApi(detailItem: _item(), records: const [])
      ..historyGate = gate;
    final dependencies = await _dependencies(api);

    await tester.pumpWidget(_host(dependencies, _item()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    // 此时记录还没回来，用户先点了第 4 集。
    await tester.tap(find.text('第 4 集'));
    await tester.pump();
    expect(find.text('播放 第 4 集'), findsOneWidget);

    // 记录这时才到（指向第 2 集）。
    gate.complete([
      _item(lastEpisodeIndex: 1, playTimeSeconds: 73, totalTimeSeconds: 2700),
    ]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('播放 第 4 集'), findsOneWidget, reason: '手动选集优先');
    // 但仍应展示「上次看到」信息，方便用户自行回去。
    expect(find.text('上次看到 第 2 集 01:13'), findsOneWidget);
    expect(find.text('回到上次'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('片尾记录只定位集数，不显示续播进度', (tester) async {
    final api = _FakeMediaApi(
      detailItem: _item(),
      records: [
        _item(lastEpisodeIndex: 2, playTimeSeconds: 2690, totalTimeSeconds: 2700),
      ],
    );
    final dependencies = await _dependencies(api);

    await tester.pumpWidget(_host(dependencies, _item()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('播放 第 3 集'), findsOneWidget);
    expect(find.textContaining('上次看到'), findsNothing, reason: '看完的记录不再续播');
    await tester.pump(const Duration(seconds: 1));
  });
}
