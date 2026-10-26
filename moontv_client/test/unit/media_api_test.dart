import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/data/api/media_api.dart';
import 'package:moontv_client/domain/models/media_item.dart';

void main() {
  test('proxy URL encodes the complete source URL and defaults to adblock', () {
    final result = MediaApi.buildProxyUrl(
      baseUrl: 'https://tv.example.com/',
      rawUrl: 'https://media.example.com/剧集 01.m3u8?a=1&b=2#part',
      source: 'source code',
    );
    expect(result, startsWith('https://tv.example.com/api/proxy-m3u8?'));
    expect(result, contains('url=https%3A%2F%2Fmedia.example.com%2F'));
    expect(result, contains('%23part'));
    expect(result, contains('source=source%20code'));
    expect(result, contains('adblock=true'));
    expect(result, contains('proxySegments=false'));
    expect(result, isNot(contains('token=')));
  });

  test('proxy URL includes a token only when configured', () {
    final result = MediaApi.buildProxyUrl(
      baseUrl: 'https://tv.example.com',
      rawUrl: 'https://media.example.com/a.m3u8',
      source: 's',
      playbackToken: 'a&b',
      adblock: false,
      proxySegments: true,
    );
    expect(result, contains('token=a%26b'));
    expect(result, contains('adblock=false'));
    expect(result, contains('proxySegments=true'));
  });

  test('media model tolerates alternate field names and empty lists', () {
    final item = MediaItem.fromJson({
      'vod_id': 12,
      'vod_name': '作品',
      'vod_pic': 'poster',
      'source_code': 'test',
      'episodes': ['a', 'b'],
      'vod_year': 2026,
      'index': 2,
      'play_time': 125,
      'total_time': 1400,
    });
    expect(item.id, '12');
    expect(item.title, '作品');
    expect(item.episodes, hasLength(2));
    expect(item.year, '2026');
    expect(item.episodeTitles, isEmpty);
    expect(item.episodeLabel(1), '第 2 集');
    expect(item.lastEpisodeIndex, 1);
    expect(item.playTimeSeconds, 125);
    expect(item.totalTimeSeconds, 1400);
    expect(item.storageKey, 'test+12');
  });
}
