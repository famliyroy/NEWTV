import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/domain/danmaku/danmaku_merger.dart';
import 'package:moontv_client/domain/models/danmaku.dart';

void main() {
  DanmakuComment comment(
    double time,
    String text, {
    int color = 0xffffff,
    String source = 'a',
    DanmakuMode mode = DanmakuMode.scroll,
    String userHash = 'user',
  }) {
    return DanmakuComment(
      time: time,
      text: text,
      color: color,
      source: source,
      mode: mode,
      userHash: userHash,
    );
  }

  group('DanmakuComment.parse', () {
    test('parses all dandanplay attributes', () {
      final item = DanmakuComment.parse(
        p: '12.345,4,25,65535,1695555123,0,abc123,998877',
        text: ' 你好 ',
        source: 'b站',
      );
      expect(item.time, 12.345);
      expect(item.mode, DanmakuMode.bottom);
      expect(item.color, 65535);
      expect(item.text, '你好');
      expect(item.userHash, 'abc123');
      expect(item.id, '998877');
    });

    test('falls back safely for short or malformed attributes', () {
      final item = DanmakuComment.parse(p: 'bad', text: 'x', source: 's');
      expect(item.time, 0);
      expect(item.mode, DanmakuMode.scroll);
      expect(item.color, 0xffffff);
      expect(item.text, 'x');
    });

    test('maps top and unknown modes', () {
      expect(
        DanmakuComment.parse(p: '1,5', text: 'x', source: 's').mode,
        DanmakuMode.top,
      );
      expect(
        DanmakuComment.parse(p: '1,99', text: 'x', source: 's').mode,
        DanmakuMode.scroll,
      );
    });
  });

  group('mergeDanmaku', () {
    test('sorts merged comments by time', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(source: 'a', comments: [comment(4, 'later')]),
        DanmakuSourceComments(source: 'b', comments: [comment(1, 'first')]),
      ]);
      expect(result.map((e) => e.text), ['first', 'later']);
    });

    test('deduplicates by 0.1 second and whitespace-free text', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(source: 'a', comments: [comment(1.001, ' hello ')]),
        DanmakuSourceComments(source: 'b', comments: [comment(1.002, 'h e l l o')]),
      ]);
      expect(result, hasLength(1));
    });

    test('does not merge comments 0.2 seconds apart', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(source: 'a', comments: [comment(1.0, 'same')]),
        DanmakuSourceComments(source: 'b', comments: [comment(1.2, 'same')]),
      ]);
      expect(result, hasLength(2));
    });

    test('keeps different text at the same time', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(
          source: 'a',
          comments: [comment(1, 'one'), comment(1, 'two')],
        ),
      ]);
      expect(result, hasLength(2));
    });

    test('inherits a non-white color from a duplicate', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(source: 'a', comments: [comment(1, 'x')]),
        DanmakuSourceComments(
          source: 'b',
          comments: [comment(1, 'x', color: 0xff00ff)],
        ),
      ]);
      expect(result.single.color, 0xff00ff);
      expect(result.single.source, 'a');
    });

    test('does not overwrite an existing non-white color', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(
          source: 'a',
          comments: [comment(1, 'x', color: 0xff0000)],
        ),
        DanmakuSourceComments(
          source: 'b',
          comments: [comment(1, 'x', color: 0x00ff00)],
        ),
      ]);
      expect(result.single.color, 0xff0000);
    });

    test('source identity does not affect the dedup key', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(source: 'a', comments: [comment(1, 'x')]),
        DanmakuSourceComments(source: 'z', comments: [comment(1, 'x')]),
      ]);
      expect(result, hasLength(1));
    });

    test('uniform sampling preserves first and last items', () {
      final result = uniformSample(
        List.generate(10, (i) => comment(i.toDouble(), '$i')),
        3,
      );
      expect(result.map((e) => e.text), ['0', '5', '9']);
    });

    test('sampling limit of one keeps the first item', () {
      final result = uniformSample([comment(1, 'a'), comment(2, 'b')], 1);
      expect(result.single.text, 'a');
    });

    test('sampling zero returns an empty list', () {
      expect(uniformSample([comment(1, 'a')], 0), isEmpty);
    });

    test('sampling above input length returns a copy', () {
      final result = uniformSample([comment(1, 'a')], 20);
      expect(result, hasLength(1));
    });

    test('per-source limit is applied before merging', () {
      final result = mergeDanmaku(
        [
          DanmakuSourceComments(
            source: 'a',
            comments: List.generate(20, (i) => comment(i.toDouble(), '$i')),
          ),
        ],
        maxPerSource: 5,
      );
      expect(result, hasLength(5));
      expect(result.first.text, '0');
      expect(result.last.text, '19');
    });

    test('total limit is respected across sources', () {
      final result = mergeDanmaku(
        List.generate(
          3,
          (source) => DanmakuSourceComments(
            source: '$source',
            comments: List.generate(
              10,
              (i) => comment(i.toDouble(), '$source-$i', source: '$source'),
            ),
          ),
        ),
        maxTotal: 7,
      );
      expect(result, hasLength(7));
      expect(result.map((e) => e.source).toSet(), hasLength(3));
    });

    test('empty sources and empty comments are accepted', () {
      expect(mergeDanmaku(const []), isEmpty);
      expect(
        mergeDanmaku([const DanmakuSourceComments(source: 'a', comments: [])]),
        isEmpty,
      );
    });

    test('negative or zero time remains deterministic', () {
      final result = mergeDanmaku([
        DanmakuSourceComments(
          source: 'a',
          comments: [comment(-1, 'negative'), comment(0, 'zero')],
        ),
      ]);
      expect(result.map((e) => e.text), ['negative', 'zero']);
    });
  });
}
