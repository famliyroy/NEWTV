import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/utils/media_grouping.dart';
import 'package:moontv_client/domain/models/media_item.dart';

MediaItem item({
  required String title,
  String source = 'cj',
  String id = '1',
  String year = '',
  int weight = 0,
}) {
  return MediaItem(
    id: id,
    title: title,
    source: source,
    sourceName: source,
    year: year,
    weight: weight,
    episodes: const ['https://example.com/a.m3u8'],
  );
}

void main() {
  group('groupByTitle', () {
    test('同名条目合并并按权重降序', () {
      final groups = groupByTitle([
        item(title: '狂飙', source: 'a', weight: 1),
        item(title: '狂飙', source: 'b', weight: 9),
        item(title: '狂飙之浴血玫瑰', source: 'c'),
      ]);
      expect(groups.length, 2);
      final first = groups.firstWhere((group) => group.first.title == '狂飙');
      expect(first.map((e) => e.source), ['b', 'a']);
    });

    test('忽略空标题', () {
      final groups = groupByTitle([
        item(title: '  '),
        item(title: '狂飙'),
      ]);
      expect(groups.length, 1);
    });
  });

  group('pickBestGroup', () {
    test('标题完全一致时优先选该组', () {
      final target = const MediaItem(id: 'd1', title: '狂飙', source: '', sourceName: '');
      final picked = pickBestGroup(target, [
        item(title: '狂飙', source: 'a'),
        item(title: '狂飙之浴血玫瑰', source: 'b'),
      ]);
      expect(picked, isNotNull);
      expect(picked!.first.source, 'a');
    });

    test('多组同名时取年份最接近的一组', () {
      final target = const MediaItem(
        id: 'd2',
        title: '射雕英雄传',
        source: '',
        sourceName: '',
        year: '1983',
      );
      final picked = pickBestGroup(target, [
        item(title: '射雕英雄传', source: 'old', year: '2003'),
        item(title: '射雕英雄传', source: 'new', year: '1983'),
        item(title: '射雕英雄传', source: 'mid', year: '1994'),
      ]);
      expect(picked!.first.source, 'new');
    });

    test('无精确标题时退回包含匹配', () {
      final target = const MediaItem(id: 'd3', title: '狂飙', source: '', sourceName: '');
      final picked = pickBestGroup(target, [
        item(title: '狂飙之浴血玫瑰', source: 'only'),
      ]);
      expect(picked, isNotNull);
      expect(picked!.first.source, 'only');
    });

    test('完全没有匹配返回 null', () {
      final target = const MediaItem(id: 'd4', title: '不存在的片', source: '', sourceName: '');
      final picked = pickBestGroup(target, [
        item(title: '狂飙', source: 'a'),
      ]);
      expect(picked, isNull);
    });

    test('搜索结果里 source 为空的条目会被忽略', () {
      final target = const MediaItem(id: 'd5', title: '狂飙', source: '', sourceName: '');
      final picked = pickBestGroup(target, [
        const MediaItem(id: 'x', title: '狂飙', source: '', sourceName: ''),
      ]);
      expect(picked, isNull);
    });
  });
}
