import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeModeIndex = 0,
    this.reduceMotion = false,
    this.danmakuEnabled = true,
    this.danmakuOpacity = 0.85,
    this.danmakuFontSize = 25,
    this.danmakuSpeed = 1,
    this.danmakuArea = 0.75,
    this.danmakuMaxSources = 12,
    this.blockedWords = '',
    this.autoplayNext = true,
    this.hardwareDecode = true,
    this.adblock = true,
    this.proxySegments = false,
  });

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
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController(this._preferences) {
    _settings = AppSettings(
      themeModeIndex: _preferences.getInt('theme') ?? 0,
      reduceMotion: _preferences.getBool('reduceMotion') ?? false,
      danmakuEnabled: _preferences.getBool('danmakuEnabled') ?? true,
      danmakuOpacity: _preferences.getDouble('danmakuOpacity') ?? 0.85,
      danmakuFontSize: _preferences.getDouble('danmakuFontSize') ?? 25,
      danmakuSpeed: _preferences.getDouble('danmakuSpeed') ?? 1,
      danmakuArea: _preferences.getDouble('danmakuArea') ?? 0.75,
      danmakuMaxSources: _preferences.getInt('danmakuMaxSources') ?? 12,
      blockedWords: _preferences.getString('blockedWords') ?? '',
      autoplayNext: _preferences.getBool('autoplayNext') ?? true,
      hardwareDecode: _preferences.getBool('hardwareDecode') ?? true,
      adblock: _preferences.getBool('adblock') ?? true,
      proxySegments: _preferences.getBool('proxySegments') ?? false,
    );
  }

  final SharedPreferences _preferences;
  late AppSettings _settings;
  AppSettings get settings => _settings;

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
    ]);
  }
}
