import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeModeIndex = 0,
    this.reduceMotion = false,
    this.danmakuEnabled = true,
    this.danmakuOpacity = 0.85,
    this.danmakuFontSize = 19,
    this.danmakuSpeed = 1,
    this.danmakuArea = 0.75,
    this.danmakuMaxSources = 12,
    this.blockedWords = '',
    this.autoplayNext = true,
    this.hardwareDecode = true,
    // 默认直连片源：服务器与片源常处于不同网络，经服务端中转反而容易失败。
    this.adblock = false,
    this.proxySegments = false,
    this.playbackToken = '',
    this.immersiveMiniProgress = false,
    this.danmakuApiMode = 0,
    this.danmakuApiBaseUrl = defaultDanmakuApiBaseUrl,
  });

  /// 自建 LogVar 弹幕服务的默认地址（路径令牌即鉴权）。
  static const defaultDanmakuApiBaseUrl = 'http://35.212.231.252:9321/87654321';

  final int themeModeIndex;
  final bool reduceMotion;
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuSpeed;
  final double danmakuArea;
  final int danmakuMaxSources;
  final String blockedWords;
  final bool autoplayNext;
  final bool hardwareDecode;
  final bool adblock;
  final bool proxySegments;
  final String playbackToken;

  /// 沉浸态（控制栏隐藏）时是否保留一条极细的进度指示。
  final bool immersiveMiniProgress;

  /// 弹幕数据源：0 = MoonTVPlus 后端，1 = 自定义 LogVar API。
  final int danmakuApiMode;
  final String danmakuApiBaseUrl;

  bool get useCustomDanmakuApi => danmakuApiMode == 1;

  AppSettings copyWith({
    int? themeModeIndex,
    bool? reduceMotion,
    bool? danmakuEnabled,
    double? danmakuOpacity,
    double? danmakuFontSize,
    double? danmakuSpeed,
    double? danmakuArea,
    int? danmakuMaxSources,
    String? blockedWords,
    bool? autoplayNext,
    bool? hardwareDecode,
    bool? adblock,
    bool? proxySegments,
    String? playbackToken,
    bool? immersiveMiniProgress,
    int? danmakuApiMode,
    String? danmakuApiBaseUrl,
  }) {
    return AppSettings(
      themeModeIndex: themeModeIndex ?? this.themeModeIndex,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
      danmakuFontSize: danmakuFontSize ?? this.danmakuFontSize,
      danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
      danmakuArea: danmakuArea ?? this.danmakuArea,
      danmakuMaxSources: danmakuMaxSources ?? this.danmakuMaxSources,
      blockedWords: blockedWords ?? this.blockedWords,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      hardwareDecode: hardwareDecode ?? this.hardwareDecode,
      adblock: adblock ?? this.adblock,
      proxySegments: proxySegments ?? this.proxySegments,
      playbackToken: playbackToken ?? this.playbackToken,
      immersiveMiniProgress:
          immersiveMiniProgress ?? this.immersiveMiniProgress,
      danmakuApiMode: danmakuApiMode ?? this.danmakuApiMode,
      danmakuApiBaseUrl: danmakuApiBaseUrl ?? this.danmakuApiBaseUrl,
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController(this._preferences) {
    _migrateDanmakuFont();
    _settings = AppSettings(
      themeModeIndex: _preferences.getInt('theme') ?? 0,
      reduceMotion: _preferences.getBool('reduceMotion') ?? false,
      danmakuEnabled: _preferences.getBool('danmakuEnabled') ?? true,
      danmakuOpacity: _preferences.getDouble('danmakuOpacity') ?? 0.85,
      danmakuFontSize: _preferences.getDouble('danmakuFontSize') ?? 19,
      danmakuSpeed: _preferences.getDouble('danmakuSpeed') ?? 1,
      danmakuArea: _preferences.getDouble('danmakuArea') ?? 0.75,
      danmakuMaxSources: _preferences.getInt('danmakuMaxSources') ?? 12,
      blockedWords: _preferences.getString('blockedWords') ?? '',
      autoplayNext: _preferences.getBool('autoplayNext') ?? true,
      hardwareDecode: _preferences.getBool('hardwareDecode') ?? true,
      adblock: _preferences.getBool('adblock') ?? false,
      proxySegments: _preferences.getBool('proxySegments') ?? false,
      playbackToken: _preferences.getString('playbackToken') ?? '',
      immersiveMiniProgress:
          _preferences.getBool('immersiveMiniProgress') ?? false,
      danmakuApiMode: _preferences.getInt('danmakuApiMode') ?? 0,
      danmakuApiBaseUrl: _preferences.getString('danmakuApiBaseUrl') ??
          AppSettings.defaultDanmakuApiBaseUrl,
    );
  }

  /// 一次性迁移标记：旧版本默认字号是 25，仅改默认值对老安装无效。
  static const danmakuFontMigrationKey = 'danmaku_font_migrated_v016';

  final SharedPreferences _preferences;
  late AppSettings _settings;
  AppSettings get settings => _settings;

  /// 老安装里持久化的 25 是旧默认值，改写成新默认 19；
  /// 用户手动调过的其它值一律不动。
  void _migrateDanmakuFont() {
    if (_preferences.getBool(danmakuFontMigrationKey) ?? false) return;
    final stored = _preferences.getDouble('danmakuFontSize');
    if (stored != null && (stored - 25).abs() < 0.01) {
      unawaited(_preferences.setDouble('danmakuFontSize', 19));
    }
    unawaited(_preferences.setBool(danmakuFontMigrationKey, true));
  }

  Future<void> update(AppSettings value) async {
    _settings = value;
    notifyListeners();
    await Future.wait([
      _preferences.setInt('theme', value.themeModeIndex),
      _preferences.setBool('reduceMotion', value.reduceMotion),
      _preferences.setBool('danmakuEnabled', value.danmakuEnabled),
      _preferences.setDouble('danmakuOpacity', value.danmakuOpacity),
      _preferences.setDouble('danmakuFontSize', value.danmakuFontSize),
      _preferences.setDouble('danmakuSpeed', value.danmakuSpeed),
      _preferences.setDouble('danmakuArea', value.danmakuArea),
      _preferences.setInt('danmakuMaxSources', value.danmakuMaxSources),
      _preferences.setString('blockedWords', value.blockedWords),
      _preferences.setBool('autoplayNext', value.autoplayNext),
      _preferences.setBool('hardwareDecode', value.hardwareDecode),
      _preferences.setBool('adblock', value.adblock),
      _preferences.setBool('proxySegments', value.proxySegments),
      _preferences.setString('playbackToken', value.playbackToken),
      _preferences.setBool('immersiveMiniProgress', value.immersiveMiniProgress),
      _preferences.setInt('danmakuApiMode', value.danmakuApiMode),
      _preferences.setString('danmakuApiBaseUrl', value.danmakuApiBaseUrl),
    ]);
  }
}
