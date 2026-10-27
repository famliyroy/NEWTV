import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地断点续播记录（按 `source+id` 存储最新观看的一集及秒数）。
class LocalResumeRecord {
  const LocalResumeRecord({
    required this.storageKey,
    required this.episodeIndex,
    required this.positionSeconds,
    required this.totalSeconds,
    required this.title,
    required this.updatedAt,
  });

  /// 最小可续播秒数：前 10 秒内视为刚开播，不展示胶囊、不自动跳。
  static const minResumeSeconds = 10;

  /// 片尾阈值：距离总时长不足 15 秒视为已看完，不展示胶囊、不自动跳。
  static const tailThresholdSeconds = 15;

  final String storageKey;
  final int episodeIndex;
  final int positionSeconds;
  final int totalSeconds;
  final String title;
  final int updatedAt;

  /// 是否处于可续播的有效区间（`> 10s` 且非片尾 15s 内）。
  bool get isValidResume {
    if (positionSeconds <= minResumeSeconds) return false;
    if (totalSeconds > 0 &&
        positionSeconds >= totalSeconds - tailThresholdSeconds) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'episodeIndex': episodeIndex,
        'positionSeconds': positionSeconds,
        'totalSeconds': totalSeconds,
        'title': title,
        'updatedAt': updatedAt,
      };

  factory LocalResumeRecord.fromJson(
    String storageKey,
    Map<String, dynamic> json,
  ) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return LocalResumeRecord(
      storageKey: storageKey,
      episodeIndex: parseInt(json['episodeIndex']),
      positionSeconds: parseInt(json['positionSeconds']),
      totalSeconds: parseInt(json['totalSeconds']),
      title: (json['title'] ?? '').toString(),
      updatedAt: parseInt(json['updatedAt']),
    );
  }
}

/// 纯本地断点续播存储（`SharedPreferences` JSON 持久化 + 200ms 写防抖 + 300 条 LRU 淘汰）。
///
/// 不依赖后端 `playrecords`、不依赖详情页异步时序，离线可用。
class LocalResumeStore {
  LocalResumeStore([SharedPreferences? preferences])
      : _preferences = preferences;

  static const storagePreferenceKey = 'local_resume_records';
  static const maxEntries = 300;
  static const debounceDuration = Duration(milliseconds: 200);

  SharedPreferences? _preferences;
  Map<String, LocalResumeRecord>? _cache;
  Timer? _debounceTimer;
  Completer<void>? _pendingFlush;

  Future<SharedPreferences> _prefs() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<Map<String, LocalResumeRecord>> _ensureLoaded() async {
    if (_cache != null) return _cache!;
    final prefs = await _prefs();
    final raw = prefs.getString(storagePreferenceKey);
    final map = <String, LocalResumeRecord>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key.toString();
            final value = entry.value;
            if (key.isEmpty || value is! Map) continue;
            map[key] = LocalResumeRecord.fromJson(
              key,
              Map<String, dynamic>.from(value),
            );
          }
        }
      } on Object {
        // 损坏的本地 JSON 自动重置为空表，不阻塞播放。
      }
    }
    _cache = map;
    return map;
  }

  /// 读取指定片源与集数的有效续播记录。
  ///
  /// - 集数不匹配返回 `null`；
  /// - 位置 `<= 10s` 或处于片尾 15s 内返回 `null`。
  Future<LocalResumeRecord?> read(String storageKey, int episodeIndex) async {
    if (storageKey.isEmpty) return null;
    final map = await _ensureLoaded();
    final record = map[storageKey];
    if (record == null) return null;
    if (record.episodeIndex != episodeIndex) return null;
    if (!record.isValidResume) return null;
    return record;
  }

  /// 写入或更新某部作品当前集的播放位置。
  ///
  /// 内存缓存立即生效（保证紧接着 `read` 不会读到旧值），
  /// 磁盘持久化默认做 200ms 防抖合并；退出页面/退后台时可传 `immediate: true` 立即落盘。
  Future<void> write({
    required String storageKey,
    required int episodeIndex,
    required int positionSeconds,
    required int totalSeconds,
    required String title,
    int? updatedAt,
    bool immediate = false,
  }) async {
    if (storageKey.isEmpty || positionSeconds <= 0) return;
    final map = await _ensureLoaded();
    map[storageKey] = LocalResumeRecord(
      storageKey: storageKey,
      episodeIndex: episodeIndex < 0 ? 0 : episodeIndex,
      positionSeconds: positionSeconds,
      totalSeconds: totalSeconds < 0 ? 0 : totalSeconds,
      title: title,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    _evictIfNeeded(map);
    if (immediate) {
      await flush();
    } else {
      _schedulePersist();
    }
  }

  /// 某集播放完成（或已到片尾）时清除该集的未完播断点，确保下次重进从头播放。
  Future<void> markCompleted(
    String storageKey,
    int episodeIndex, {
    bool immediate = false,
  }) async {
    if (storageKey.isEmpty) return;
    final map = await _ensureLoaded();
    final existing = map[storageKey];
    if (existing == null || existing.episodeIndex != episodeIndex) return;
    map.remove(storageKey);
    if (immediate) {
      await flush();
    } else {
      _schedulePersist();
    }
  }

  /// 主动移除某个片源的本地续播记录。
  Future<void> remove(String storageKey, {bool immediate = true}) async {
    if (storageKey.isEmpty) return;
    final map = await _ensureLoaded();
    if (map.remove(storageKey) == null) return;
    if (immediate) {
      await flush();
    } else {
      _schedulePersist();
    }
  }

  /// 立即将内存中的记录写入 `SharedPreferences`。
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final pending = _pendingFlush;
    _pendingFlush = null;
    try {
      await _persistNow();
      pending?.complete();
    } on Object catch (error, stackTrace) {
      pending?.completeError(error, stackTrace);
      rethrow;
    }
  }

  void _evictIfNeeded(Map<String, LocalResumeRecord> map) {
    if (map.length <= maxEntries) return;
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => map[a]!.updatedAt.compareTo(map[b]!.updatedAt));
    final removeCount = map.length - maxEntries;
    for (var i = 0; i < removeCount; i++) {
      map.remove(sortedKeys[i]);
    }
  }

  void _schedulePersist() {
    _debounceTimer?.cancel();
    final completer = _pendingFlush ??= Completer<void>();
    _debounceTimer = Timer(debounceDuration, () async {
      _debounceTimer = null;
      _pendingFlush = null;
      try {
        await _persistNow();
        if (!completer.isCompleted) completer.complete();
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    });
  }

  Future<void> _persistNow() async {
    final map = _cache;
    if (map == null) return;
    final prefs = await _prefs();
    final encoded = jsonEncode({
      for (final entry in map.entries) entry.key: entry.value.toJson(),
    });
    await prefs.setString(storagePreferenceKey, encoded);
  }
}
