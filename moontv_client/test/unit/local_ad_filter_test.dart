import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/core/config/server_config.dart';
import 'package:moontv_client/core/player/ad_filter/local_ad_filter.dart';
import 'package:moontv_client/core/player/player_controller.dart';
import 'package:moontv_client/domain/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _textResponse(
  String body, {
  int statusCode = 200,
  String contentType = 'application/vnd.apple.mpegurl',
}) {
  return ResponseBody.fromBytes(
    utf8.encode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );
}

void main() {
  group('LocalAdFilter.filterMediaPlaylist 纯函数规则', () {
    test('删除 DISCONTINUITY、命中 7 关键词分片与时长异常分片（<45% 或 >200% 中位数）', () {
      const m3u8 = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.000,
seg0.ts
#EXTINF:6.000,
seg1.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.500,
short_ad.ts
#EXTINF:15.000,
long_ad.ts
#EXTINF:6.000,
https://ad.example.com/sponsor/promo.ts
#EXTINF:6.000,
/ad/inline_clip.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.000,
seg2.ts
#EXTINF:6.000,
seg3.ts
#EXT-X-ENDLIST
''';

      final result = LocalAdFilter.filterMediaPlaylist(
        m3u8,
        baseUri: Uri.parse('https://cdn.example.com/vod/ep1/index.m3u8'),
      );

      expect(result, isNotNull);
      expect(result!.totalSegments, 8);
      expect(result.keptSegments, 4);
      expect(result.removedSegments, 4);
      expect(result.abandonedFilter, isFalse);
      expect(result.content, isNot(contains('#EXT-X-DISCONTINUITY')));
      expect(result.content, isNot(contains('short_ad.ts')));
      expect(result.content, isNot(contains('long_ad.ts')));
      expect(result.content, isNot(contains('promo.ts')));
      expect(result.content, isNot(contains('inline_clip.ts')));
      expect(
        result.content,
        contains('https://cdn.example.com/vod/ep1/seg0.ts'),
      );
      expect(
        result.content,
        contains('https://cdn.example.com/vod/ep1/seg3.ts'),
      );
      expect(result.content.trimRight().endsWith('#EXT-X-ENDLIST'), isTrue);
    });

    test('加密流 #EXT-X-KEY 与相对分片路径均被转为绝对 URL，且被删广告块的专属 KEY 不会残留', () {
      const m3u8 = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-KEY:METHOD=AES-128,URI="keys/enc.key",IV=0x00000000000000000000000000000001
#EXTINF:6.0,
sub/001.ts
#EXTINF:6.0,
/root/002.ts
#EXT-X-DISCONTINUITY
#EXT-X-KEY:METHOD=NONE
#EXTINF:1.2,
ad_unencrypted.ts
#EXT-X-DISCONTINUITY
#EXT-X-KEY:METHOD=AES-128,URI="keys/enc.key",IV=0x00000000000000000000000000000001
#EXTINF:6.0,
/api/video-proxy?url=https%3A%2F%2Fcdn.example.com%2F003.ts
#EXT-X-ENDLIST
''';

      final result = LocalAdFilter.filterMediaPlaylist(
        m3u8,
        baseUri: Uri.parse('https://cdn.example.com/2026/ep2/playlist.m3u8'),
        serverBaseUri: Uri.parse('https://tv.myserver.com'),
      );

      expect(result, isNotNull);
      expect(result!.keptSegments, 3);
      expect(
        result.content,
        contains('URI="https://cdn.example.com/2026/ep2/keys/enc.key"'),
      );
      expect(result.content, isNot(contains('METHOD=NONE')));
      expect(
        result.content,
        contains('https://cdn.example.com/2026/ep2/sub/001.ts'),
      );
      expect(
        result.content,
        contains('https://cdn.example.com/root/002.ts'),
      );
      expect(
        result.content,
        contains(
          'https://tv.myserver.com/api/video-proxy?url=https%3A%2F%2Fcdn.example.com%2F003.ts',
        ),
      );
    });

    test('直播流（EVENT 或缺少 VOD/ENDLIST 标记）跳过本地过滤', () {
      const eventStream = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:EVENT
#EXTINF:6.0,
live0.ts
#EXTINF:6.0,
live1.ts
''';
      const rollingLiveStream = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:1024
#EXTINF:6.0,
live0.ts
#EXTINF:6.0,
live1.ts
''';

      final base = Uri.parse('https://live.example.com/channel/index.m3u8');
      expect(LocalAdFilter.isLivePlaylist(eventStream), isTrue);
      expect(LocalAdFilter.isLivePlaylist(rollingLiveStream), isTrue);
      expect(
        LocalAdFilter.filterMediaPlaylist(eventStream, baseUri: base),
        isNull,
      );
      expect(
        LocalAdFilter.filterMediaPlaylist(rollingLiveStream, baseUri: base),
        isNull,
      );
    });

    test('过滤后分片不足 2 段时触发防误杀回退（保留原分片但仍去 DISCONTINUITY 与绝对化）', () {
      const m3u8 = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
/ad/only_seg1.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.0,
/ad/only_seg2.ts
#EXT-X-ENDLIST
''';

      final result = LocalAdFilter.filterMediaPlaylist(
        m3u8,
        baseUri: Uri.parse('https://cdn.example.com/video/index.m3u8'),
      );

      expect(result, isNotNull);
      expect(result!.abandonedFilter, isTrue);
      expect(result.keptSegments, 2);
      expect(result.content, isNot(contains('#EXT-X-DISCONTINUITY')));
      expect(
        result.content,
        contains('https://cdn.example.com/ad/only_seg1.ts'),
      );
    });
  });

  group('LocalAdFilter.prepare 与 PlayerController 候选链集成', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('newtv_ad_filter_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('代理失败自动回退直连拉取 Master Playlist、解析子流并生成本地 file:// m3u8，clearCache 可清理', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) {
        final uri = options.uri.toString();
        if (uri.contains('/api/proxy-m3u8')) {
          return _textResponse(
            '{"error":"源站连接超时"}',
            statusCode: 502,
            contentType: 'application/json',
          );
        }
        if (uri == 'https://cdn.example.com/master.m3u8') {
          expect(options.headers['Referer'], 'https://cdn.example.com/');
          return _textResponse('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080
1080p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720
720p/index.m3u8
''');
        }
        if (uri == 'https://cdn.example.com/1080p/index.m3u8') {
          return _textResponse('''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg1.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.2,
ad.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.0,
seg2.ts
#EXT-X-ENDLIST
''');
        }
        return _textResponse('Not Found', statusCode: 404);
      });

      final filter = LocalAdFilter(
        dio: dio,
        tempDirProvider: () async => tempDir,
      );
      final result = await filter.prepare(
        rawUrl: 'https://cdn.example.com/master.m3u8',
        proxyUrl:
            'https://tv.myserver.com/api/proxy-m3u8?url=https%3A%2F%2Fcdn.example.com%2Fmaster.m3u8',
        serverBaseUrl: 'https://tv.myserver.com',
        source: 'ikun',
        mediaId: '9988_0',
      );

      expect(result.isSuccess, isTrue);
      expect(result.fileUri, startsWith('file://'));
      expect(result.removedSegments, 1);
      expect(result.totalSegments, 3);
      expect(result.proxyError, isNotNull);

      final written = await File(result.filePath!).readAsString();
      expect(written, contains('https://cdn.example.com/1080p/seg1.ts'));
      expect(written, contains('https://cdn.example.com/1080p/seg2.ts'));
      expect(written, isNot(contains('ad.ts')));

      await LocalAdFilter.clearCache(tempDirProvider: () async => tempDir);
      expect(await File(result.filePath!).exists(), isFalse);
    });

    test('PlayerController 开启去广告时将本地过滤文件置于第一候选，候选切换与异常回零均保进度', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsController(prefs);
      await settings.update(settings.settings.copyWith(adblock: true));

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) {
        return _textResponse('''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg1.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.5,
ad.ts
#EXTINF:6.0,
seg2.ts
#EXT-X-ENDLIST
''');
      });

      final openedUrls = <String>[];
      final seekTargets = <Duration>[];
      final controller = PlayerController(
        server: const ServerConfig(baseUrl: 'https://tv.myserver.com'),
        settings: settings,
        dio: dio,
        adFilter: LocalAdFilter(
          dio: dio,
          tempDirProvider: () async => tempDir,
        ),
        debugUrlOpener: (url) async => openedUrls.add(url),
        debugSeekHandler: (target) async => seekTargets.add(target),
      );
      addTearDown(controller.dispose);

      const context = PlaybackContext(
        item: MediaItem(
          id: 'ep100',
          title: '测试剧集',
          source: 'ikun',
          sourceName: '爱坤',
          episodes: ['https://cdn.example.com/play/index.m3u8'],
        ),
        episodeIndex: 0,
      );

      await controller.open(context);

      // 候选顺序：[本地过滤文件, 服务端代理, 直连, 全量代理]
      expect(controller.candidates.length, 4);
      expect(controller.candidates.first, startsWith('file://'));
      expect(controller.activeRouteLabel, '本地过滤');
      expect(
        controller.activeRouteDescription,
        contains('已剔除 1/3 段广告切片'),
      );
      expect(openedUrls.single, startsWith('file://'));

      // 模拟已播放到 05:20（320s），随后切换候选链路：应记住 05:20 并在缓冲完成后自动恢复。
      controller
        ..handleDurationUpdate(const Duration(minutes: 24))
        ..handleBufferingUpdate(false)
        ..handlePlayingUpdate(true)
        ..handlePositionUpdate(const Duration(seconds: 320));

      final switched = await controller.switchToNextCandidate();
      expect(switched, isTrue);
      expect(controller.activeRouteLabel, '服务端代理');
      expect(seekTargets, isEmpty);

      // 新候选完成缓冲后自动触发保进度 seek(320s)。
      controller
        ..handleDurationUpdate(const Duration(minutes: 24))
        ..handleBufferingUpdate(false);
      expect(seekTargets, contains(const Duration(seconds: 320)));

      // 模拟用户快进到 10:00（600s），但底层流因断层回落到 0:01：应触发一次补跳兜底。
      seekTargets.clear();
      await controller.seek(const Duration(seconds: 600));
      expect(seekTargets, [const Duration(seconds: 600)]);
      controller.handlePositionUpdate(const Duration(seconds: 1));
      expect(
        seekTargets,
        [const Duration(seconds: 600), const Duration(seconds: 600)],
      );
    });

    test('起播后立即退出播放页：迟到的清晰度探测不得对已 dispose 的控制器发通知', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsController(prefs);

      final probeGate = Completer<void>();
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString().contains('/api/proxy-m3u8')) {
          // 代理探测快速失败 -> 走直连
          return _textResponse(
            '{"error":"源站不可达"}',
            statusCode: 502,
            contentType: 'application/json',
          );
        }
        // 清晰度探测被挂起，模拟用户此时已经退出播放页。
        await probeGate.future;
        return _textResponse('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720
720p/index.m3u8
''');
      });

      final controller = PlayerController(
        server: const ServerConfig(baseUrl: 'https://tv.myserver.com'),
        settings: settings,
        dio: dio,
        debugUrlOpener: (url) async {},
        debugSeekHandler: (target) async {},
      );

      const context = PlaybackContext(
        item: MediaItem(
          id: 'ep200',
          title: '测试剧集',
          source: 'ikun',
          sourceName: '爱坤',
          episodes: ['https://cdn.example.com/play/master.m3u8'],
        ),
        episodeIndex: 0,
      );

      await controller.open(context);
      // 用户立刻退出播放页。
      controller.dispose();
      // 挂起的探测此刻才返回；修复前这里会抛
      // "A PlayerController was used after being disposed"。
      probeGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.probingQuality, isFalse);
    });
  });
}
