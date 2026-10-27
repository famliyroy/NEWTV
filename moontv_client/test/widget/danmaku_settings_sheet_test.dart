import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:moontv_client/features/danmaku/danmaku_settings_sheet.dart';
import 'package:moontv_client/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打开方式与播放页保持一致，验证能渲染、能滚动、能关闭。
Widget _host(SettingsController storage) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith((ref) => storage)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.9,
                  minChildSize: 0.28,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) => DanmakuSettingsSheet(
                    scrollController: scrollController,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('弹幕设置面板可渲染、可下滑拖动，并可点「完成」关闭', (tester) async {
    final storage = SettingsController(await SharedPreferences.getInstance());
    await tester.pumpWidget(_host(storage));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('当前弹幕源'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 向下拖动内容区：DraggableScrollableSheet 收缩到最小并关闭。
    // 拖动距离要足以越过 minChildSize（0.28），否则只会停在最小高度。
    await tester.drag(find.text('字号'), const Offset(0, 560));
    await tester.pumpAndSettle();
    expect(find.text('弹幕设置'), findsNothing);

    // 再开一次，用「完成」按钮关闭。
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('弹幕设置'), findsNothing);
  });

  testWidgets('拖动滑块只在松手时提交，拖动过程不写设置', (tester) async {
    final storage = SettingsController(await SharedPreferences.getInstance());
    // 从一个已知值出发，避免依赖默认值。
    await storage.update(storage.settings.copyWith(danmakuOpacity: 0.8));
    await tester.pumpWidget(_host(storage));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(4));
    // 透明度是第 3 个滑块。
    final opacity = sliders.at(2);
    final before = storage.settings.danmakuOpacity;
    final gesture = await tester.startGesture(tester.getCenter(opacity));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    // 拖动中：UI 回显变了，但设置存储没变（不会触发全量重建）。
    expect(storage.settings.danmakuOpacity, before);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(storage.settings.danmakuOpacity, lessThan(before));
  });
}
