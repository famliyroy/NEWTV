import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_settings.dart';
import '../../data/repositories/danmaku_repository.dart';
import '../../domain/models/danmaku.dart';
import '../../domain/models/media_item.dart';

class DanmakuController extends ChangeNotifier {
  DanmakuController(this._repository, this._settings) {
    final config = _settings.settings;
    _wasEnabled = config.danmakuEnabled;
    _captureLoadParams(config);
    _settings.addListener(_handleSettingsChanged);
  }

  static const _successTtl = Duration(seconds: 3);
  static const _errorTtl = Duration(seconds: 5);

  /// 加载期参数变化后的合并窗口：拖滑块/切源时避免连续重拉。
  static const reloadDebounce = Duration(milliseconds: 500);

  final DanmakuRepository _repository;

  /// 持有的 storage 会实时变更，弹幕开关/字号等都直接读它。
  final SettingsController _settings;

  List<DanmakuComment> _comments = const [];
  double _position = 0;
  var _loadedSources = 0;
  var _totalSources = 0;
  String _status = '';
  Timer? _statusTimer;
  Timer? _reloadTimer;
  Future<DanmakuLoadResult>? _operation;
  PlaybackContext? _lastContext;
  var _wasEnabled = true;
  var _playing = true;
  double _rate = 1.0;
  DanmakuLoadResult? _result;
  var _generation = 0;

  // 最近一次加载实际使用的「加载期参数」，用于判断是否需要自动重载。
  var _activeMaxSources = 12;
  var _activeApiMode = 0;
  var _activeApiBaseUrl = '';

  List<DanmakuComment> get comments => _comments;
  double get position => _position;
  bool get loaded => _comments.isNotEmpty;

  /// 单一事实来源：跟随全局设置，播放页的开关也写回设置。
  bool get enabled => _settings.settings.danmakuEnabled;

  int get loadedSources => _loadedSources;
  int get totalSources => _totalSources;
  String get status => _status;
  bool get loading => _operation != null;

  /// 数据源描述，如「MoonTVPlus 聚合」「自定义 LogVar (35.212.231.252:9321)」。
  String get sourceDescription =>
      _result?.providerDescription ?? _repository.description;

  /// 命中的作品名（数据源侧原始标题）。
  String get matchedTitle => _result?.matchedTitle ?? '';

  /// 命中的集标题。
  String get matchedEpisode => _result?.matchedEpisode ?? '';

  /// 提供方，如 dandan / animeko / bilibili。
  String get providerName => _result?.providerName ?? '';

  /// 最近一次加载的结论（未加载时为 null）。
  DanmakuLoadResult? get lastResult => _result;

  void setPosition(double seconds) {
    if ((_position - seconds).abs() < 0.05) return;
    _position = seconds;
    notifyListeners();
  }

  /// 播放器是否在推进。弹幕层据此启停 60fps Ticker：
  /// 暂停时停帧，既省电，也避免弹幕越过暂停画面。
  bool get playing => _playing;

  void setPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    notifyListeners();
  }

  /// 播放速率。弹幕位置 = 锚点 + 墙钟差 × 该倍速，0.5x~3x 都靠它对齐。
  double get rate => _rate;

  void setRate(double value) {
    if (value <= 0 || (_rate - value).abs() < 0.001) return;
    _rate = value;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (enabled == value) return;
    unawaited(_settings.update(_settings.settings.copyWith(danmakuEnabled: value)));
    if (!value) clear();
  }

  void _captureLoadParams(AppSettings config) {
    _activeMaxSources = config.danmakuMaxSources;
    _activeApiMode = config.danmakuApiMode;
    _activeApiBaseUrl = config.danmakuApiBaseUrl;
  }

  void _handleSettingsChanged() {
    final config = _settings.settings;
    final nowEnabled = config.danmakuEnabled;

    // 关闭 → 开启：内存里的弹幕已被 clear，按当前上下文补一次加载。
    if (nowEnabled && !_wasEnabled) _scheduleReload(immediate: true);
    _wasEnabled = nowEnabled;

    // 来源上限、数据源模式、自定义地址都是「加载期参数」，改了必须重载，
    // 否则用户得退出播放页再进来才生效。
    final loadParamsChanged = config.danmakuMaxSources != _activeMaxSources ||
        config.danmakuApiMode != _activeApiMode ||
        config.danmakuApiBaseUrl != _activeApiBaseUrl;
    if (loadParamsChanged && nowEnabled) _scheduleReload();

    notifyListeners();
  }

  void _scheduleReload({bool immediate = false}) {
    final context = _lastContext;
    if (context == null) return;
    _reloadTimer?.cancel();
    _reloadTimer = Timer(
      immediate ? Duration.zero : reloadDebounce,
      () => unawaited(loadFor(context)),
    );
  }

  void clear() {
    _comments = const [];
    _loadedSources = 0;
    _totalSources = 0;
    _result = null;
    _statusTimer?.cancel();
    _status = '';
    notifyListeners();
  }

  /// 提示胶囊只做瞬时反馈，不长期占位。
  void _setStatus(String value, {Duration? ttl}) {
    _statusTimer?.cancel();
    _status = value;
    if (value.isNotEmpty) {
      _statusTimer = Timer(ttl ?? _successTtl, () {
        _status = '';
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> loadFor(PlaybackContext context) async {
    _lastContext = context;
    final config = _settings.settings;
    _captureLoadParams(config);
    if (!config.danmakuEnabled) return;

    // 每次加载递增代号：旧的请求晚回来时直接丢弃，避免覆盖新结果。
    final generation = ++_generation;
    clear();
    final operation = _repository.load(
      title: context.item.title,
      episodeNumber: context.episodeIndex + 1,
      totalEpisodes: context.item.episodes.length,
      maxSources: config.danmakuMaxSources,
      onProgress: (loaded, total, comments) {
        if (generation != _generation) return;
        _loadedSources = loaded;
        _totalSources = total;
        _setStatus('弹幕 $loaded/$total 源 · $comments 条');
      },
    );
    _operation = operation;
    notifyListeners();
    try {
      final result = await operation;
      if (generation != _generation) return;
      _comments = result.comments;
      _loadedSources = result.loadedSources;
      _totalSources = result.totalSources;
      _result = result;
      final message = result.fromCache
          ? '弹幕已缓存 · ${result.comments.length} 条'
          : result.message.isNotEmpty
              ? result.message
              : '弹幕 ${result.loadedSources}/${result.totalSources} 源 · ${result.comments.length} 条';
      _setStatus(message, ttl: _ttlFor(message));
    } on Object {
      if (generation != _generation) return;
      _setStatus('弹幕加载失败', ttl: _errorTtl);
    } finally {
      if (generation == _generation) _operation = null;
      notifyListeners();
    }
  }

  static Duration _ttlFor(String message) {
    if (message.contains('失败') || message.contains('未找到') || message.contains('未能')) {
      return _errorTtl;
    }
    return _successTtl;
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    _statusTimer?.cancel();
    _reloadTimer?.cancel();
    _operation?.ignore();
    super.dispose();
  }
}
