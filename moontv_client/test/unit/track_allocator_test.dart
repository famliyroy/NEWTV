import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/domain/danmaku/track_allocator.dart';
import 'package:moontv_client/domain/models/danmaku.dart';

DanmakuTrackAllocator _allocator({int scrollRows = 2}) {
  final allocator = DanmakuTrackAllocator();
  allocator.configure(scrollRows: scrollRows, topRows: 1, bottomRows: 1);
  return allocator;
}

int? _scroll(
  DanmakuTrackAllocator allocator, {
  required String key,
  required double time,
  double width = 200,
  double screenWidth = 1000,
  double window = 10,
  double gap = 0,
}) {
  return allocator.allocate(
    key: key,
    mode: DanmakuMode.scroll,
    time: time,
    width: width,
    screenWidth: screenWidth,
    window: window,
    fixedDuration: 4.5,
    gap: gap,
  );
}

void main() {
  group('DanmakuTrackAllocator 滚动轨道', () {
    test('同一时刻的多条弹幕分到不同轨道', () {
      final allocator = _allocator(scrollRows: 3);
      expect(_scroll(allocator, key: 'a', time: 0), 0);
      expect(_scroll(allocator, key: 'b', time: 0), 1);
      expect(_scroll(allocator, key: 'c', time: 0), 2);
    });

    test('轨道未空出时新弹幕换轨，全部占满则丢弃', () {
      final allocator = _allocator(scrollRows: 1);
      // speed = (1000+200)/10 = 120px/s → 200px 文字尾巴进场需 1.667s
      expect(_scroll(allocator, key: 'a', time: 0), 0);
      expect(_scroll(allocator, key: 'b', time: 1), isNull);
      expect(_scroll(allocator, key: 'c', time: 1.7), 0);
    });

    test('间距计入占用时长', () {
      final allocator = _allocator(scrollRows: 1);
      expect(_scroll(allocator, key: 'a', time: 0, gap: 240), 0);
      // (200+240)/120 ≈ 3.667s 才空出
      expect(_scroll(allocator, key: 'b', time: 3), isNull);
      expect(_scroll(allocator, key: 'c', time: 3.7), 0);
    });

    test('同一条弹幕重复分配行号不变（飞行中不跳行）', () {
      final allocator = _allocator(scrollRows: 4);
      final first = _scroll(allocator, key: 'a', time: 0);
      expect(first, 0);
      // 后续时刻再次询问（模拟逐帧绘制）仍是同一行
      expect(_scroll(allocator, key: 'a', time: 2), first);
      // 另一条在 a 的尾部尚未完全进场时到来 → 换到下一轨，不会叠在 a 上
      expect(_scroll(allocator, key: 'b', time: 1), 1);
      // a 的尾部进场（1.667s）之后，0 轨可以复用
      expect(_scroll(allocator, key: 'c', time: 1.8), 0);
    });

    test('被标记丢弃的弹幕不会中途重新冒出来', () {
      final allocator = _allocator(scrollRows: 1);
      expect(_scroll(allocator, key: 'x', time: 0), 0);
      expect(_scroll(allocator, key: 'y', time: 0), isNull);
      allocator.reject('y');
      // 轨道已空也不再放它，否则弹幕会在画面中间突然出现
      expect(_scroll(allocator, key: 'y', time: 10), isNull);
      allocator.reset();
      expect(_scroll(allocator, key: 'y', time: 10), 0);
    });

    test('reset 后重新从第一条轨道开始分配', () {
      final allocator = _allocator(scrollRows: 2);
      expect(_scroll(allocator, key: 'a', time: 0), 0);
      expect(_scroll(allocator, key: 'b', time: 0), 1);
      allocator.reset();
      expect(_scroll(allocator, key: 'c', time: 0), 0);
    });

    test('轨道数变化会清空旧分配', () {
      final allocator = _allocator(scrollRows: 1);
      expect(_scroll(allocator, key: 'a', time: 0), 0);
      allocator.configure(scrollRows: 3, topRows: 1, bottomRows: 1);
      expect(allocator.rowOf('a'), isNull);
      expect(_scroll(allocator, key: 'a', time: 0), 0);
      expect(_scroll(allocator, key: 'b', time: 0), 1);
    });
  });

  group('DanmakuTrackAllocator 固定弹幕', () {
    int? fixed(
      DanmakuTrackAllocator allocator, {
      required String key,
      required double time,
      required DanmakuMode mode,
    }) {
      return allocator.allocate(
        key: key,
        mode: mode,
        time: time,
        width: 100,
        screenWidth: 1000,
        window: 10,
        fixedDuration: 4,
        gap: 20,
      );
    }

    test('顶部与底部各用独立轨道', () {
      final allocator = _allocator();
      expect(fixed(allocator, key: 't1', time: 0, mode: DanmakuMode.top), 0);
      expect(fixed(allocator, key: 'b1', time: 0, mode: DanmakuMode.bottom), 0);
      // 同一轨道被占用到 4s
      expect(fixed(allocator, key: 't2', time: 3, mode: DanmakuMode.top), isNull);
      expect(fixed(allocator, key: 't3', time: 4.1, mode: DanmakuMode.top), 0);
    });
  });

  test('没有可用轨道时返回 null 而不是抛异常', () {
    final allocator = DanmakuTrackAllocator();
    allocator.configure(scrollRows: 0, topRows: 0, bottomRows: 0);
    expect(_scroll(allocator, key: 'a', time: 0), isNull);
  });
}
