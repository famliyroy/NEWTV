import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/utils/local_resume_store.dart';
import 'package:moontv_client/domain/models/media_item.dart';
import 'package:moontv_client/features/player/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItem _media({
  String id = '100',
  String source = 'ikun',
  int lastEpisodeIndex = 0,
  int playTimeSeconds = 0,
  int totalTimeSeconds = 0,
}) {
  return MediaItem(
    id: id,
    title: '沧元图',
    source: source,
    sourceName: 'iKun资源',
    episodes: const ['https://a/1.m3u8', 'https://a/2.m3u8'],
    lastEpisodeIndex: lastEpisodeIndex,
    playTimeSeconds: playTimeSeconds,
    totalTimeSeconds: totalTimeSeconds,
  );
}

Widget _buildHost({
  required ResumeSessionController session,
  required ValueNotifier<bool> controlsVisible,
  Duration position = Duration.zero,
  Duration duration = const Duration(minutes: 24),
  ValueChanged<Duration>? onSeekBar,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: controlsVisible,
        builder: (context, visible, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 24,
                right: 24,
                bottom: 76,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: PlayerProgressBar(
                    position: position,
                    duration: duration,
                    onDragStart: session.onUserManualSeek,
                    onSeek: (target) {
                      session.onUserManualSeek();
                      onSeekBar?.call(target);
                    },
                    onInteract: () {},
                  ),
                ),
              ),
              Positioned(
                left: 24,
                bottom: 50,
                child: AnimatedBuilder(
                  animation: session,
                  builder: (context, _) {
                    final mode = session.mode;
                    final seconds = session.targetSeconds;
                    final show = mode != null && seconds != null && visible;
                    return IgnorePointer(
                      ignoring: !show,
                      child: AnimatedOpacity(
                        opacity: show ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: mode == null || seconds == null
                            ? const SizedBox.shrink()
                            : ResumeCapsule(
                                mode: mode,
                                seconds: seconds,
                                onJump: session.jumpToResume,
                                onRestart: () =>
                                    unawaited(session.restartFromBeginning()),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('缓冲完成下降沿自动跳转到 12:00，展示「已跳到上次位置 · 从头看」且 6 秒后自动消失', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);
    await store.write(
      storageKey: 'ikun+100',
      episodeIndex: 0,
      positionSeconds: 720,
      totalSeconds: 1440,
      title: '沧元图',
      immediate: true,
    );

    final seeks = <Duration>[];
    final session = ResumeSessionController(store: store, onSeek: seeks.add);
    final controlsVisible = ValueNotifier<bool>(true);

    await session.loadFor(PlaybackContext(item: _media(), episodeIndex: 0));
    await tester.pumpWidget(
      _buildHost(session: session, controlsVisible: controlsVisible),
    );
    await tester.pump();

    // 缓冲完成前：显示「上次看到 12:00 ▸」，尚未触发 seek。
    expect(find.text('上次看到 12:00 ▸'), findsOneWidget);
    expect(seeks, isEmpty);

    // 1. 进入缓冲中（buffering = true）。
    session.onPlayerStateChanged(
      position: const Duration(seconds: 1),
      duration: const Duration(minutes: 24),
      buffering: true,
      playing: true,
    );
    await tester.pump();
    expect(seeks, isEmpty);

    // 2. 缓冲完成下降沿（buffering: true -> false，duration > 0，position < 5s）。
    final jumped = session.onPlayerStateChanged(
      position: const Duration(seconds: 1),
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    expect(jumped, isTrue);
    expect(seeks, [const Duration(seconds: 720)]);

    // 模拟播放器响应 seek 跳到 12:00。
    session.onPlayerStateChanged(
      position: const Duration(seconds: 720),
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    await tester.pump();

    expect(find.text('已跳到上次位置 12:00 · '), findsOneWidget);
    expect(find.text('从头看'), findsOneWidget);

    // 弱网再次缓冲并恢复：不许二次自动跳。
    session.onPlayerStateChanged(
      position: const Duration(seconds: 2),
      duration: const Duration(minutes: 24),
      buffering: true,
      playing: true,
    );
    session.onPlayerStateChanged(
      position: const Duration(seconds: 2),
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    expect(seeks.length, 1, reason: '弱网反复缓冲不得二次自动跳');

    // 6 秒不点自动消失。
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('从头看'), findsNothing);

    session.dispose();
  });

  testWidgets('点击「从头看」立即跳回 0:00 并清除本地记录与胶囊', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);
    await store.write(
      storageKey: 'ikun+100',
      episodeIndex: 0,
      positionSeconds: 720,
      totalSeconds: 1440,
      title: '沧元图',
      immediate: true,
    );

    final seeks = <Duration>[];
    final session = ResumeSessionController(store: store, onSeek: seeks.add);
    final controlsVisible = ValueNotifier<bool>(true);

    await session.loadFor(PlaybackContext(item: _media(), episodeIndex: 0));
    await tester.pumpWidget(
      _buildHost(session: session, controlsVisible: controlsVisible),
    );

    // 触发缓冲完成自动跳。
    session.onPlayerStateChanged(
      position: Duration.zero,
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    session.onPlayerStateChanged(
      position: const Duration(seconds: 720),
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    await tester.pump();

    expect(find.text('从头看'), findsOneWidget);
    await tester.tap(find.text('从头看'));
    await tester.pump();

    expect(seeks.last, Duration.zero, reason: '点从头看应 seek 到 0:00');
    expect(find.text('从头看'), findsNothing);
    expect(await store.read('ikun+100', 0), isNull, reason: '应同步移除本地断点记录');

    await tester.pump(const Duration(seconds: 6));
    session.dispose();
  });

  testWidgets('重新进入后不等缓冲、立刻手动拖动进度条：取消自动跳并隐藏胶囊', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);
    await store.write(
      storageKey: 'ikun+100',
      episodeIndex: 0,
      positionSeconds: 720,
      totalSeconds: 1440,
      title: '沧元图',
      immediate: true,
    );

    final autoSeeks = <Duration>[];
    final barSeeks = <Duration>[];
    final session = ResumeSessionController(store: store, onSeek: autoSeeks.add);
    final controlsVisible = ValueNotifier<bool>(true);

    await session.loadFor(PlaybackContext(item: _media(), episodeIndex: 0));
    await tester.pumpWidget(
      _buildHost(
        session: session,
        controlsVisible: controlsVisible,
        onSeekBar: barSeeks.add,
      ),
    );
    await tester.pump();
    expect(find.text('上次看到 12:00 ▸'), findsOneWidget);

    // 缓冲尚未完成时，用户直接开始拖动进度条。
    final sliderRect = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(sliderRect.left + sliderRect.width * 0.2, sliderRect.center.dy),
    );
    await tester.pump();
    await gesture.moveTo(
      Offset(sliderRect.left + sliderRect.width * 0.5, sliderRect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // 胶囊立即消失，且随后缓冲完成时不得再触发自动跳。
    expect(find.text('上次看到 12:00 ▸'), findsNothing);
    session.onPlayerStateChanged(
      position: const Duration(seconds: 1),
      duration: const Duration(minutes: 24),
      buffering: false,
      playing: true,
    );
    await tester.pump();
    expect(autoSeeks, isEmpty, reason: '用户已手动拖动进度条，自动跳必须取消');
    expect(barSeeks.length, 1);

    await tester.pump(const Duration(seconds: 2));
    session.dispose();
  });

  testWidgets('沉浸态（控制栏隐藏）时胶囊同步隐藏，唤出控制栏后恢复，手动点击胶囊跳转后消失', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);
    await store.write(
      storageKey: 'ikun+100',
      episodeIndex: 0,
      positionSeconds: 754,
      totalSeconds: 1800,
      title: '沧元图',
      immediate: true,
    );

    final seeks = <Duration>[];
    final session = ResumeSessionController(store: store, onSeek: seeks.add);
    final controlsVisible = ValueNotifier<bool>(true);

    await session.loadFor(PlaybackContext(item: _media(), episodeIndex: 0));
    // 假设进入时位置已在 6 秒（不满足 <5s 自动跳条件，停留在手动胶囊态）。
    session.onPlayerStateChanged(
      position: const Duration(seconds: 6),
      duration: const Duration(minutes: 30),
      buffering: false,
      playing: true,
    );
    await tester.pumpWidget(
      _buildHost(session: session, controlsVisible: controlsVisible),
    );
    await tester.pump();

    expect(find.text('上次看到 12:34 ▸'), findsOneWidget);

    // 3 秒无操作进入沉浸态。
    controlsVisible.value = false;
    await tester.pump(const Duration(milliseconds: 200));
    final hiddenOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(ResumeCapsule),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(hiddenOpacity.opacity, 0);

    // 用户唤出控制栏：胶囊重新可见。
    controlsVisible.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    final visibleOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(ResumeCapsule),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(visibleOpacity.opacity, 1);

    // 点击胶囊跳转：触发 seek(12:34) 且胶囊消失。
    await tester.tap(find.text('上次看到 12:34 ▸'));
    await tester.pump();
    expect(seeks, [const Duration(seconds: 754)]);
    expect(find.byType(ResumeCapsule), findsNothing);

    session.dispose();
  });
}
