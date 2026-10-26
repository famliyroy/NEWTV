import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/domain/danmaku/title_cleaner.dart';

void main() {
  group('cleanDanmakuTitle', () {
    const cases = <String, String>{
      '葬送的芙莉莲[简中][1080P]': '葬送的芙莉莲',
      '【喵萌奶茶屋】葬送的芙莉莲 - 01': '葬送的芙莉莲',
      '【LoliHouse】 药屋少女的呢喃 - 02 [WebRip 1080p HEVC-10bit AAC]': '药屋少女的呢喃',
      'Frieren: Beyond Journey\'s End EP12': 'Frieren: Beyond Journey\'s End',
      'Frieren - 12.5': 'Frieren',
      '进击的巨人 最终季 第12话': '进击的巨人 最终季',
      '进击的巨人 最终季 第十二集': '进击的巨人 最终季',
      'Movie.Name.2023.2160P.WEB-DL.x265.mkv': 'Movie.Name.2023',
      '剧场版 咒术回战 0 (2021)': '剧场版 咒术回战 0',
      '紫罗兰永恒花园（国语）': '紫罗兰永恒花园',
      '名侦探柯南 E12': '名侦探柯南',
      '某作品 Episode 08': '某作品',
      '  多部  作品  ': '多部 作品',
      '[ANi] 番剧名称 [简繁]': '番剧名称',
      '番剧名称[BluRay][HEVC]': '番剧名称',
    };

    cases.forEach((input, expected) {
      test('cleans $input', () {
        expect(cleanDanmakuTitle(input), expected);
      });
    });

    test('falls back to original when all content is bracketed', () {
      expect(cleanDanmakuTitle('[1080P]'), '[1080P]');
    });

    test('does not erase a meaningful season marker', () {
      expect(cleanDanmakuTitle('某番 第二季 第03话'), '某番 第二季');
    });

    test('does not erase numbers embedded in a title', () {
      expect(cleanDanmakuTitle('3年A班'), '3年A班');
    });

    test('returns an empty string for blank input', () {
      expect(cleanDanmakuTitle('  '), isEmpty);
    });
  });
}
