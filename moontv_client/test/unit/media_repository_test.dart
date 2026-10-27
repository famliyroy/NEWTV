import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/data/api/media_api.dart';
import 'package:moontv_client/data/repositories/media_repository.dart';
import 'package:moontv_client/domain/models/media_item.dart';

/// 只覆盖播放记录相关的接口，其余走真实实现（测试里不会被调用）。
class _FakeMediaApi extends MediaApi {
  _FakeMediaApi(this.records) : super(Dio());

  List<MediaItem> records;
  var historyCalls = 0;
  var failNextHistory = false;

  @override
  Future<List<MediaItem>> history() async {
    historyCalls++;
    if (failNextHistory) {
      failNextHistory = false;
      throw StateError('network down');
    }
    return records;
  }

  @override
  Future<void> savePlayRecord(
    MediaItem item, {
    required int episodeIndex,
    required int playTimeSeconds,
    required int totalTimeSeconds,
  }) async {}
}

MediaItem _item({String id = '100', String source = 'cj', int index = 0, int play = 0}) {
  return MediaItem(
    id: id,
    title: '测试剧',
    source: source,
    sourceName: '量子',
    episodes: const ['https://a/1.m3u8', 'https://a/2.m3u8'],
    lastEpisodeIndex: index,
    playTimeSeconds: play,
    totalTimeSeconds: 2700,
  );
}

void main() {
  test('按 storageKey 建索引，并命中 5 分钟 TTL 缓存', () async {
    final api = _FakeMediaApi([_item(index: 4, play: 620)]);
    final repository = MediaRepository(api);

    final first = await repository.playRecordMap();
    expect(first.length, 1);
    expect(first['cj+100']!.lastEpisodeIndex, 4);
    expect(first['cj+100']!.playTimeSeconds, 620);

    await repository.playRecordMap();
    await repository.playRecordMap();
    expect(api.historyCalls, 1, reason: 'TTL 内不应重复拉取');
  });

  test('force 强制刷新', () async {
    final api = _FakeMediaApi([_item()]);
    final repository = MediaRepository(api);
    await repository.playRecordMap();
    await repository.playRecordMap(force: true);
    expect(api.historyCalls, 2);
  });

  test('忽略 source/id 缺失的记录', () async {
    final api = _FakeMediaApi([
      _item(),
      const MediaItem(id: '', title: '无源', source: '', sourceName: ''),
    ]);
    final repository = MediaRepository(api);
    final map = await repository.playRecordMap();
    expect(map.keys, ['cj+100']);
  });

  test('拉取失败时退回旧缓存，不抛异常', () async {
    final api = _FakeMediaApi([_item(index: 2, play: 30)]);
    final repository = MediaRepository(api);
    expect(await repository.playRecordFor(_item()), isNotNull);

    api.failNextHistory = true;
    final again = await repository.playRecordMap(force: true);
    expect(again['cj+100']!.lastEpisodeIndex, 2, reason: '失败应保留上一次结果');
  });

  test('保存记录后本地索引立即更新（不必等 TTL）', () async {
    final api = _FakeMediaApi([_item(index: 0, play: 5)]);
    final repository = MediaRepository(api);
    await repository.playRecordMap();

    await repository.savePlayRecord(
      _item(),
      episodeIndex: 1,
      playTimeSeconds: 900,
      totalTimeSeconds: 2700,
    );
    final record = await repository.playRecordFor(_item());
    expect(record!.lastEpisodeIndex, 1);
    expect(record.playTimeSeconds, 900);
    expect(api.historyCalls, 1, reason: '不应为了刷新而重新拉取');
  });
}
