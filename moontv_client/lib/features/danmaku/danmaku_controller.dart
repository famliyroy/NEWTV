import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_settings.dart';
import '../../data/repositories/danmaku_repository.dart';
import '../../domain/models/danmaku.dart';
import '../../domain/models/media_item.dart';

class DanmakuController extends ChangeNotifier {
  DanmakuController(this._repository, this._settings) {
    _wasEnabled = _settings.settings.danmakuEnabled;
    _settings.addListener(_handleSettingsChanged);
  }

  static const _successTtl = Duration(seconds: 3);
  static const _errorTtl = Duration(seconds: 5);

  final DanmakuRepository _repository;

  /// 持有的 storage 会实时变更，弹幕开关/字号等都直接读它。
  final SettingsController _settings;

  List<DanmakuComment> _comments = const [];
  double _position = 0;
  var _loadedSources = 0;
  var _totalSources = 0;
  String _status = '';
  Timer? _statusTimer;
  Future<DanmakuLoadResult>? _operation;
  PlaybackContext? _lastContext;
  var _wasEnabled = true;

  List<DanmakuComment> get comments => _comments;
  double get position => _position;
  bool get loaded => _comments.isNotEmpty;

  /// 单一事实来源：跟随全局设置，播放页的开关也写回设置。
  bool get enabled => _settings.settings.danmakuEnabled;

  int get loadedSources => _loadedSources;
  int get totalSources => _totalSources;
  String get status => _status;
  bool get loading => _operation != null;

  void setPosition(double seconds) {
    if ((_position - seconds).abs() < 0.05) return;
    _position = seconds;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (enabled == value) return;
    unawaited(_settings.update(_settings.settings.copyWith(danmakuEnabled: value)));
    if (!value) clear();
  }

  void _handleSettingsChanged() {
    final nowEnabled = enabled;
    // 只在「关闭 → 开启」这一刻补加载：内存里的弹幕已被 clear 掉了。
    if (nowEnabled && !_wasEnabled && _lastContext != null && _operation == null) {
      unawaited(loadFor(_lastContext!));
    }
    _wasEnabled = nowEnabled;
    notifyListeners();
  }

  void clear() {
    _comments = const [];
    _loadedSources = 0;
    _totalSources = 0;
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
    if (!enabled) return;
    clear();
    final operation = _repository.load(
      title: context.item.title,
      episodeNumber: context.episodeIndex + 1,
      totalEpisodes: context.item.episodes.length,
      maxSources: _settings.settings.danmakuMaxSources,
      onProgress: (loaded, total, comments) {
        _loadedSources = loaded;
        _totalSources = total;
        _setStatus('弹幕 $loaded/$total 源 · $comments 条');
      },
    );
    _operation = operation;
    notifyListeners();
    try {
      final result = await operation;
      _comments = result.comments;
      _loadedSources = result.loadedSources;
      _totalSources = result.totalSources;
      final message = result.fromCache
          ? '弹幕已缓存 · ${result.comments.length} 条'
          : result.message.isNotEmpty
              ? result.message
              : '弹幕 ${result.loadedSources}/${result.totalSources} 源 · ${result.comments.length} 条';
      _setStatus(message, ttl: _ttlFor(message));
    } on Object {
      _setStatus('弹幕加载失败', ttl: _errorTtl);
    } finally {
      _operation = null;
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
    _operation?.ignore();
    super.dispose();
  }
}
