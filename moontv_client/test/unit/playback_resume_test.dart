import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/utils/playback_resume.dart';
import 'package:moontv_client/domain/models/media_item.dart';

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
    episodes: List.generate(episodeCount, (index) => 'https://a/$index.m3u8'),
    lastEpisodeIndex: lastEpisodeIndex,
    playTimeSeconds: playTimeSeconds,
    totalTimeSeconds: totalTimeSeconds,
  );
}

void main() {
  group('resolveResumePoint', () {
    test('没有记录返回 null', () {
      expect(resolveResumePoint(item: _item(), record: null), isNull);
    });

    test('片源还没有集数时返回 null（等拿到集数再恢复）', () {
      final point = resolveResumePoint(
        item: _item(episodeCount: 0),
        record: _item(lastEpisodeIndex: 2, playTimeSeconds: 73),
      );
      expect(point, isNull);
    });

    test('记录全为 0（看过但没进度）返回 null', () {
      final point = resolveResumePoint(
        item: _item(),
        record: _item(lastEpisodeIndex: 0, playTimeSeconds: 0),
      );
      expect(point, isNull);
    });

    test('正常恢复：集数与秒数都还原', () {
      final point = resolveResumePoint(
        item: _item(),
        record: _item(lastEpisodeIndex: 2, playTimeSeconds: 73, totalTimeSeconds: 2700),
      )!;
      expect(point.episodeIndex, 2);
      expect(point.startSeconds, 73);
      expect(point.totalSeconds, 2700);
      expect(point.finished, isFalse);
      expect(point.hasProgress, isTrue);
    });

    test('记录集数超出当前片源集数时钳制到最后一集', () {
      final point = resolveResumePoint(
        item: _item(episodeCount: 3),
        record: _item(lastEpisodeIndex: 9, playTimeSeconds: 120),
      )!;
      expect(point.episodeIndex, 2);
      expect(point.startSeconds, 120);
    });

    test('片尾 30 秒内视为看完：定位集数但不续播', () {
      final point = resolveResumePoint(
        item: _item(),
        record: _item(lastEpisodeIndex: 1, playTimeSeconds: 2680, totalTimeSeconds: 2700),
      )!;
      expect(point.episodeIndex, 1);
      expect(point.startSeconds, 0);
      expect(point.finished, isTrue);
      expect(point.hasProgress, isFalse);
    });

    test('恰好差 30 秒也判定为看完', () {
      final point = resolveResumePoint(
        item: _item(),
        record: _item(lastEpisodeIndex: 1, playTimeSeconds: 2670, totalTimeSeconds: 2700),
      )!;
      expect(point.finished, isTrue);
      expect(point.startSeconds, 0);
    });

    test('总时长未知（0）时不判看完，照常续播', () {
      final point = resolveResumePoint(
        item: _item(),
        record: _item(lastEpisodeIndex: 3, playTimeSeconds: 5000),
      )!;
      expect(point.finished, isFalse);
      expect(point.startSeconds, 5000);
    });
  });

  group('resumeStartSeconds（起播位置）', () {
    test('选中集等于记录集数才续播', () {
      final item = _item(lastEpisodeIndex: 2, playTimeSeconds: 73);
      expect(resumeStartSeconds(item: item, selectedEpisode: 2), 73);
    });

    test('手动选择其它集必须从头播放', () {
      final item = _item(lastEpisodeIndex: 2, playTimeSeconds: 73);
      expect(resumeStartSeconds(item: item, selectedEpisode: 0), 0);
      expect(resumeStartSeconds(item: item, selectedEpisode: 3), 0);
    });

    test('没有进度记录时从头播放', () {
      final item = _item(lastEpisodeIndex: 0, playTimeSeconds: 0);
      expect(resumeStartSeconds(item: item, selectedEpisode: 0), 0);
    });

    test('片尾记录不续播末段', () {
      final item = _item(
        lastEpisodeIndex: 1,
        playTimeSeconds: 2690,
        totalTimeSeconds: 2700,
      );
      expect(resumeStartSeconds(item: item, selectedEpisode: 1), 0);
    });
  });
}
