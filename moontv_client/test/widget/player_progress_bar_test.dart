import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/features/player/player_page.dart';

void main() {
  testWidgets('拖拽期间只更新本地预览与时间气泡，松手才触发一次 seek', (tester) async {
    final seeks = <Duration>[];
    var interacts = 0;
    var livePosition = const Duration(seconds: 20);
    const totalDuration = Duration(seconds: 100);

    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 72,
                    child: PlayerProgressBar(
                      position: livePosition,
                      duration: totalDuration,
                      onSeek: seeks.add,
                      onInteract: () => interacts++,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);
    expect(find.textContaining(' / 01:40'), findsNothing);

    // 按下并拖动进度条：开始拖拽态。
    final rect = tester.getRect(sliderFinder);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.2, rect.center.dy),
    );
    await tester.pump();

    // 拖到约 60% 位置。
    await gesture.moveTo(Offset(rect.left + rect.width * 0.6, rect.center.dy));
    await tester.pump();

    // 拖动途中应展示预览时间气泡，且不应触发真实 seek。
    expect(find.textContaining(' / 01:40'), findsOneWidget);
    expect(seeks, isEmpty, reason: '拖动途中不得触发底层 seek');
    expect(interacts, greaterThan(0));

    final draggedValue = tester.widget<Slider>(sliderFinder).value;
    expect(draggedValue, greaterThan(45000));

    // 模拟播放器 20Hz 位置流在拖动途中继续推送旧位置（21s、22s）。
    updateHost(() => livePosition = const Duration(seconds: 21));
    await tester.pump();
    updateHost(() => livePosition = const Duration(seconds: 22));
    await tester.pump();

    // 拇指不得被位置流拉回 22s。
    expect(
      tester.widget<Slider>(sliderFinder).value,
      closeTo(draggedValue, 1.0),
      reason: '拖动期间 Slider 值必须锁定本地拖拽值，忽略实时位置流',
    );
    expect(seeks, isEmpty);

    // 松手：触发且仅触发一次 seek，预览气泡立即消失。
    await gesture.up();
    await tester.pump();

    expect(seeks.length, 1, reason: '松手时只能触发一次 seek');
    expect(seeks.single.inSeconds, closeTo(60, 5));
    expect(find.textContaining(' / 01:40'), findsNothing, reason: '松手后气泡消失');

    // 松手后、播放器位置尚未跳到新位置前的短暂窗口内，继续推送旧位置 23s 不得闪回。
    final targetMs = seeks.single.inMilliseconds.toDouble();
    updateHost(() => livePosition = const Duration(seconds: 23));
    await tester.pump();
    expect(
      tester.widget<Slider>(sliderFinder).value,
      closeTo(targetMs, 1.0),
      reason: 'seek 尚未完成前应保持落点，防止拇指闪回旧位置',
    );

    // 当位置流跳到落点附近（误差 <= 1s）时，交回实时位置流控制。
    updateHost(
      () => livePosition = Duration(milliseconds: targetMs.round() + 400),
    );
    await tester.pump();
    updateHost(
      () => livePosition = Duration(milliseconds: targetMs.round() + 2000),
    );
    await tester.pump();
    expect(
      tester.widget<Slider>(sliderFinder).value,
      closeTo(targetMs + 2000, 1.0),
      reason: '位置流收敛后应跟随后续播放进度推进',
    );
  });

  testWidgets('seek 超时未收敛时自动释放本地锁定', (tester) async {
    final seeks = <Duration>[];
    var livePosition = const Duration(seconds: 10);

    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return PlayerProgressBar(
                position: livePosition,
                duration: const Duration(seconds: 100),
                onSeek: seeks.add,
                onInteract: () {},
              );
            },
          ),
        ),
      ),
    );

    final sliderFinder = find.byType(Slider);
    final rect = tester.getRect(sliderFinder);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.1, rect.center.dy),
    );
    await tester.pump();
    await gesture.moveTo(Offset(rect.left + rect.width * 0.8, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeks.length, 1);
    // 超过 1.5s 收敛保护窗口后，即使播放器未跳过去也应释放锁定。
    await tester.pump(const Duration(milliseconds: 1600));
    updateHost(() => livePosition = const Duration(seconds: 15));
    await tester.pump();
    expect(tester.widget<Slider>(sliderFinder).value, 15000);
  });
}
