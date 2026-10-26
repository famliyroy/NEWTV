import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_settings.dart';
import '../../data/repositories/danmaku_repository.dart';
import '../../domain/models/danmaku.dart';
import '../../domain/models/media_item.dart';

class DanmakuController extends ChangeNotifier {
  DanmakuController(this._repository, this._settings);

  final DanmakuRepository _repository;
  final SettingsController _settings;
  List<DanmakuComment> _comments = const [];
  double _position = 0;
  var _enabled = true;
  var _loadedSources = 0;
  var _totalSources = 0;
  String _status = '';
  Future<DanmakuLoadResult>? _operation;

  List<DanmakuComment> get comments => _comments;
  double get position => _position;
  bool get enabled => _enabled;
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
    _enabled = value;
    if (!value) clear();
    notifyListeners();
  }

  void clear() {
    _comments = const [];
    _loadedSources = 0;
    _totalSources = 0;
    _status = '';
    notifyListeners();
  }

  Future<void> loadFor(PlaybackContext context) async {
    if (!_enabled || !_settings.settings.danmakuEnabled) return;
    clear();
    final operation = _repository.load(
      title: context.item.title,
      episodeNumber: context.episodeIndex + 1,
      totalEpisodes: context.item.episodes.length,
      maxSources: _settings.settings.danmakuMaxSources,
      onProgress: (loaded, total, comments) {
        _loadedSources = loaded;
        _totalSources = total;
        _status = '弹幕 $loaded/$total 源 · $comments 条';
        notifyListeners();
      },
    );
    _operation = operation;
    notifyListeners();
    try {
      final result = await operation;
      _comments = result.comments;
      _loadedSources = result.loadedSources;
      _totalSources = result.totalSources;
      _status = result.fromCache
          ? '弹幕已缓存 · ${result.comments.length} 条'
          : result.message.isNotEmpty
              ? result.message
              : '弹幕 ${result.loadedSources}/${result.totalSources} 源 · ${result.comments.length} 条';
    } on Object {
      _status = '弹幕加载失败';
    } finally {
      _operation = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _operation?.ignore();
    super.dispose();
  }
}
