import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/domain/danmaku/episode_matcher.dart';
import 'package:moontv_client/domain/models/danmaku.dart';

void main() {
  DanmakuEpisode episode(num id, String title) =>
      DanmakuEpisode(episodeId: '$id', episodeTitle: title);

  group('parseEpisodeNumber', () {
    const cases = <String, double>{
      '第12话': 12,
      '第 12 集': 12,
      '第十二話': 12,
      '第二十五话': 25,
      '第一百零二集': 102,
      'EP12': 12,
      'ep 08': 8,
      'Episode 12.5': 12.5,
      'E07': 7,
      '作品 - 01': 1,
      '作品 #23': 23,
      '12': 12,
      '第两话': 2,
    };
    cases.forEach((input, expected) {
      test(input, () => expect(parseEpisodeNumber(input), expected));
    });

    for (final input in <String>[
      '无集号标题',
      '2023',
      '1080P',
      '2023-01-01',
      '第三季',
      '',
    ]) {
      test('rejects $input', () => expect(parseEpisodeNumber(input), isNull));
    }
  });

  group('matchEpisode', () {
    test('P0 matches a numeric episode', () {
      final episodes = [episode(1, '第1话'), episode(2, '第2话')];
      final result = matchEpisode(episodes: episodes, episodeNumber: 2);
      expect(result?.episodeId, '2');
    });

    test('P0 matches a decimal special episode', () {
      final episodes = [episode(1, 'EP12'), episode(2, 'EP12.5')];
      final result = matchEpisode(episodes: episodes, episodeNumber: 12.5);
      expect(result?.episodeId, '2');
    });

    test('P1 matches a movie with a non-numeric title', () {
      final result = matchEpisode(
        episodes: [episode(99, '剧场版 完整版')],
        episodeNumber: 1,
        isMovie: true,
      );
      expect(result?.episodeId, '99');
    });

    test('P1 matches OVA source and target', () {
      final result = matchEpisode(
        episodes: [episode(99, 'OVA 番外')],
        episodeNumber: 1,
        targetTitle: '某番 OVA',
      );
      expect(result?.episodeId, '99');
    });

    test('P2 uses same index only when totals align', () {
      final result = matchEpisode(
        episodes: [episode(11, '上'), episode(22, '下')],
        episodeNumber: 2,
        totalEpisodes: 2,
      );
      expect(result?.episodeId, '22');
    });

    test('P3 accepts a sole episode without a number', () {
      final result = matchEpisode(
        episodes: [episode(88, '特别篇')],
        episodeNumber: 1,
      );
      expect(result?.episodeId, '88');
    });

    test('P4 skips instead of guessing the first episode', () {
      final result = matchEpisode(
        episodes: [episode(1, '上'), episode(2, '下')],
        episodeNumber: 2,
      );
      expect(result, isNull);
    });

    test('does not use index fallback for a decimal episode', () {
      final result = matchEpisode(
        episodes: [episode(1, '甲'), episode(2, '乙')],
        episodeNumber: 1.5,
        totalEpisodes: 2,
      );
      expect(result, isNull);
    });

    test('returns null for an empty source', () {
      expect(matchEpisode(episodes: const [], episodeNumber: 1), isNull);
    });
  });
}
