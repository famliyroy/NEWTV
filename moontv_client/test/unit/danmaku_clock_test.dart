import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/features/danmaku/danmaku_clock.dart';

void main() {
  var t = 0.0;
  late DanmakuClock clock;

  setUp(() {
    t = 0;
    clock = DanmakuClock(now: () => t);
  });

  group('DanmakuClock 插值', () {
    test('首次上报即锚定，位置等于上报值', () {
      expect(clock.anchored, isFalse);
      expect(clock.position, 0);
      clock.report(10);
      expect(clock.anchored, isTrue);
      expect(clock.position, closeTo(10, 1e-9));
    });

    test('两次上报之间按墙钟连续推进（不是等上报才跳）', () {
      clock.report(10);
      // 播放器下一次上报前，中间帧也应该有位置。
      t = 0.016;
      expect(clock.position, closeTo(10.016, 1e-6));
      t = 0.05;
      expect(clock.position, closeTo(10.05, 1e-6));
      t = 0.1;
      expect(clock.position, closeTo(10.1, 1e-6));
      // 再来一次上报，位置连续、不跳变。
      clock.report(10.1);
      expect(clock.position, closeTo(10.1, 1e-6));
    });

    test('位置单调递增，逐帧步长恒定（无台阶）', () {
      clock.report(100);
      var previous = clock.position;
      final steps = <double>[];
      for (var i = 0; i < 10; i++) {
        t += 1 / 60;
        final next = clock.position;
        steps.add(next - previous);
        previous = next;
      }
      final expected = 1 / 60;
      for (final step in steps) {
        expect(step, closeTo(expected, 1e-6));
      }
    });

    test('2 倍速：墙钟 0.1s 对应媒体 0.2s', () {
      clock.report(50);
      clock.setRate(2);
      t = 0.1;
      expect(clock.position, closeTo(50.2, 1e-6));
    });

    test('0.5 倍速：墙钟 0.2s 对应媒体 0.1s', () {
      clock.report(50);
      clock.setRate(0.5);
      t = 0.2;
      expect(clock.position, closeTo(50.1, 1e-6));
    });

    test('速率被钳制在 0.1x~4x，非法值忽略', () {
      clock.setRate(0);
      expect(clock.rate, 1);
      clock.setRate(-2);
      expect(clock.rate, 1);
      clock.setRate(99);
      expect(clock.rate, 4);
      clock.setRate(0.5);
      expect(clock.rate, 0.5);
    });
  });

  group('DanmakuClock 误差校正', () {
    test('小偏差只吃 20%，不跳到真值', () {
      clock.report(10);
      t = 1.0;
      // 插值到 11.0，真实位置 11.4（偏差 0.4 < 硬同步阈值）。
      final hard = clock.report(11.4);
      expect(hard, isFalse, reason: '小偏差不应硬同步');
      // 只修正 20%：11.0 + 0.4*0.2 = 11.08
      expect(clock.position, closeTo(11.08, 1e-6));
      expect(clock.position, lessThan(11.4));
    });

    test('连续上报逐步收敛，且单次校正不可见', () {
      clock.report(10);
      t = 1.0;
      // 真实位置比插值超前 0.4s（例如播放器上报有量化偏差）。
      var truth = 11.4;
      clock.report(truth);
      var previousError = (truth - clock.position).abs();
      expect(previousError, lessThan(0.4), reason: '第一次只应吃掉 20% 偏差');

      for (var i = 0; i < 15; i++) {
        t += 0.05;
        truth += 0.05;
        final before = clock.position;
        clock.report(truth);
        final after = clock.position;
        // 扣掉正常推进量，剩下的才是「校正位移」，必须小到看不见。
        final correction = (after - before).abs() - 0.05;
        expect(correction, lessThan(0.1));
        final error = (truth - after).abs();
        expect(error, lessThan(previousError), reason: '误差必须单调收敛');
        previousError = error;
      }
      expect(previousError, lessThan(0.02), reason: '多次校正后应基本对齐');
    });

    test('大幅前进（seek 向前）硬同步并返回 true', () {
      clock.report(10);
      t = 0.5;
      final hard = clock.report(300);
      expect(hard, isTrue);
      expect(clock.position, closeTo(300, 1e-9));
    });

    test('大幅后退（seek 回退/切集）硬同步并返回 true', () {
      clock.report(600);
      t = 0.2;
      final hard = clock.report(0);
      expect(hard, isTrue);
      expect(clock.position, closeTo(0, 1e-9));
    });

    test('硬同步后继续按新锚点匀速推进', () {
      clock.report(10);
      t = 1;
      expect(clock.report(300), isTrue);
      t = 1.5;
      expect(clock.position, closeTo(300.5, 1e-6));
    });

    test('reset 可强制对锚（暂停恢复/切集用）', () {
      clock.report(10);
      t = 5;
      clock.reset(20);
      expect(clock.position, closeTo(20, 1e-9));
      t = 5.5;
      expect(clock.position, closeTo(20.5, 1e-6));
    });
  });
}
