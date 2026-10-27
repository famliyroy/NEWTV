import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/config/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _controller(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsController(await SharedPreferences.getInstance());
}

void main() {
  group('弹幕字号默认值与一次性迁移', () {
    test('全新安装默认 19', () async {
      final settings = await _controller({});
      expect(settings.settings.danmakuFontSize, 19);
      // 迁移标记应已写入，避免下次误判。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SettingsController.danmakuFontMigrationKey), isTrue);
    });

    test('老安装里持久化的旧默认值 25 会被改成 19', () async {
      final settings = await _controller({'danmakuFontSize': 25.0});
      expect(settings.settings.danmakuFontSize, 19);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('danmakuFontSize'), 19);
    });

    test('用户手动改过其它值不被覆盖', () async {
      final settings = await _controller({'danmakuFontSize': 32.0});
      expect(settings.settings.danmakuFontSize, 32);
    });

    test('已迁移过则不再改写（尊重之后手动调回 25）', () async {
      final settings = await _controller({
        'danmakuFontSize': 25.0,
        SettingsController.danmakuFontMigrationKey: true,
      });
      expect(settings.settings.danmakuFontSize, 25);
    });

    test('迁移后用户手动设回 25 不会被再次改写', () async {
      final first = await _controller({'danmakuFontSize': 25.0});
      expect(first.settings.danmakuFontSize, 19);
      // 用户随后手动调回 25（走 update，不经过迁移）。
      await first.update(first.settings.copyWith(danmakuFontSize: 25));
      final second = SettingsController(await SharedPreferences.getInstance());
      expect(second.settings.danmakuFontSize, 25);
    });
  });
}
