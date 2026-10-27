import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moontv_client/core/auth/secure_cookie_storage.dart';
import 'package:moontv_client/core/auth/session_manager.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/core/config/server_config.dart';
import 'package:moontv_client/core/network/api_exception.dart';
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
  _FakeMediaApi({
    required this.detailItem,
    required this.records,
    this.detailHandler,
    this.searchResults = const [],
  }) : super(Dio());

  final MediaItem detailItem;
  final Future<MediaItem> Function(MediaItem item)? detailHandler;
  List<MediaItem> records;
  List<MediaItem> searchResults;
  var searchCalls = 0;

  /// 非空时 history() 会挂起，用来模拟「迟到的异步查询」。
  Completer<List<MediaItem>>? historyGate;

  @override
  Future<MediaItem> detail(MediaItem item) async {
    if (detailHandler != null) return detailHandler!(item);
    return detailItem;
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    searchCalls++;
    return searchResults;
  }

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

  testWidgets('历史单源详情 404 时自动搜索接源：原源搜索有集数则优先保留原源并恢复进度', (tester) async {
    const historyEntry = MediaItem(
      id: 'ikun-1',
      title: '沧元图',
      source: 'ikun',
      sourceName: 'iKun资源',
      episodes: [],
      lastEpisodeIndex: 1,
      playTimeSeconds: 73,
      totalTimeSeconds: 1500,
    );
    final searchIkun = historyEntry.copyWith(
      episodes: const ['https://ikun/1.m3u8', 'https://ikun/2.m3u8', 'https://ikun/3.m3u8'],
      weight: 50,
    );
    const searchOther = MediaItem(
      id: 'ff-9',
      title: '沧元图',
      source: 'ffzy',
      sourceName: '非凡资源',
      episodes: ['https://ff/1.m3u8', 'https://ff/2.m3u8', 'https://ff/3.m3u8'],
      weight: 90,
    );

    final api = _FakeMediaApi(
      detailItem: historyEntry,
      detailHandler: (item) async {
        if (item.source == 'ikun') {
          throw const ApiException(
            ApiErrorKind.business,
            '详情页请求失败: 404',
            statusCode: 404,
          );
        }
        return item;
      },
      searchResults: [searchOther, searchIkun],
      records: [historyEntry],
    );
    final dependencies = await _dependencies(api);

    await tester.pumpWidget(_host(dependencies, historyEntry));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();

    expect(api.searchCalls, 1, reason: '应自动触发一次按标题搜索接源');
    expect(find.text('iKun资源 · 共 3 集'), findsOneWidget, reason: '原源在搜索结果中有集数时应优先保留原源');
    expect(find.text('播放 第 2 集'), findsOneWidget);
    expect(find.text('上次看到 第 2 集 01:13'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('历史单源详情 404 且原源彻底失效时，自动切到命中组可用源并查新源记录', (tester) async {
    const deadHistory = MediaItem(
      id: 'dead-1',
      title: '沧元图',
      source: 'ikun',
      sourceName: 'iKun资源',
      episodes: [],
      lastEpisodeIndex: 0,
      playTimeSeconds: 45,
      totalTimeSeconds: 1500,
    );
    const backupSource = MediaItem(
      id: 'lz-88',
      title: '沧元图',
      source: 'lzi',
      sourceName: '量子资源',
      episodes: [
        'https://lz/1.m3u8',
        'https://lz/2.m3u8',
        'https://lz/3.m3u8',
        'https://lz/4.m3u8',
      ],
      weight: 80,
    );
    final backupRecord = backupSource.copyWith(
      lastEpisodeIndex: 2,
      playTimeSeconds: 125,
      totalTimeSeconds: 1500,
    );

    final api = _FakeMediaApi(
      detailItem: backupSource,
      detailHandler: (item) async {
        if (item.source == 'ikun') {
          throw const ApiException(
            ApiErrorKind.business,
            '详情页请求失败: 404',
            statusCode: 404,
          );
        }
        return backupSource;
      },
      searchResults: [backupSource],
      records: [deadHistory, backupRecord],
    );
    final dependencies = await _dependencies(api);

    await tester.pumpWidget(_host(dependencies, deadHistory));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();

    expect(api.searchCalls, 1);
    expect(find.text('量子资源 · 共 4 集'), findsOneWidget);
    expect(find.text('播放 第 3 集'), findsOneWidget, reason: '换源后应应用新源的播放记录');
    expect(find.text('上次看到 第 3 集 02:05'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('自动接源无结果时只试一轮（防抖），并提供重新搜索片源入口', (tester) async {
    const deadItem = MediaItem(
      id: 'dead-2',
      title: '不存在的测试番',
      source: 'ikun',
      sourceName: 'iKun资源',
      episodes: [],
    );
    final api = _FakeMediaApi(
      detailItem: deadItem,
      detailHandler: (_) async => throw const ApiException(
        ApiErrorKind.business,
        '详情页请求失败: 404',
        statusCode: 404,
      ),
      searchResults: const [],
      records: const [],
    );
    final dependencies = await _dependencies(api);

    await tester.pumpWidget(_host(dependencies, deadItem));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();

    expect(api.searchCalls, 1, reason: '自动接源失败后不得无限重试');
    expect(find.text('重新搜索片源'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('从播放页返回详情页时，自动刷新最新播放集数与进度', (tester) async {
    final item = _item(episodeCount: 5);
    final api = _FakeMediaApi(
      detailItem: item,
      records: [
        _item(episodeCount: 5, lastEpisodeIndex: 0, playTimeSeconds: 30, totalTimeSeconds: 1800),
      ],
    );
    final dependencies = await _dependencies(api);

    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (context, state) => DetailPage(initialItem: item),
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  // 模拟播放页退出前保存了第 4 集 03:20 的新进度。
                  api.records = [
                    _item(
                      episodeCount: 5,
                      lastEpisodeIndex: 3,
                      playTimeSeconds: 200,
                      totalTimeSeconds: 1800,
                    ),
                  ];
                  context.pop(item);
                },
                child: const Text('退出播放'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('播放 第 1 集'), findsOneWidget);
    expect(find.text('上次看到 第 1 集 00:30'), findsOneWidget);

    await tester.tap(find.text('播放 第 1 集'));
    await tester.pumpAndSettle();
    expect(find.text('退出播放'), findsOneWidget);

    await tester.tap(find.text('退出播放'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('播放 第 4 集'), findsOneWidget, reason: '返回详情页后应立即更新为第 4 集');
    expect(find.text('上次看到 第 4 集 03:20'), findsOneWidget);
  });
}
