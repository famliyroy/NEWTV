import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/danmaku/danmaku_merger.dart';
import '../../domain/danmaku/episode_matcher.dart';
import '../../domain/danmaku/title_cleaner.dart';
import '../../domain/models/danmaku.dart';
import '../api/danmaku_api.dart';

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.comments,
    required this.loadedSources,
    required this.totalSources,
    required this.fromCache,
    this.message = '',
  });

  final List<DanmakuComment> comments;
  final int loadedSources;
  final int totalSources;
  final bool fromCache;
  final String message;
}

typedef DanmakuProgress = void Function(int loaded, int total, int comments);

abstract class DanmakuCache {
  Future<List<DanmakuComment>?> read(String title, double episode);
  Future<void> write(String title, double episode, List<DanmakuComment> comments);
}

class MemoryDanmakuCache implements DanmakuCache {
  final _values = <String, (DateTime, List<DanmakuComment>)>{};

  @override
  Future<List<DanmakuComment>?> read(String title, double episode) async {
    final key = '$title#$episode';
    final value = _values[key];
    if (value == null) return null;
    if (DateTime.now().difference(value.$1) > const Duration(days: 7)) {
      _values.remove(key);
      return null;
    }
    return value.$2;
  }

  @override
  Future<void> write(String title, double episode, List<DanmakuComment> comments) async {
    _values['$title#$episode'] = (DateTime.now(), comments);
  }
}

class FileDanmakuCache implements DanmakuCache {
  Future<File> _file(String title, double episode) async {
    final directory = await getApplicationSupportDirectory();
    final safe = base64Url.encode(utf8.encode('$title#$episode'));
    return File(p.join(directory.path, 'danmaku_cache', '$safe.json'));
  }

  @override
  Future<List<DanmakuComment>?> read(String title, double episode) async {
    try {
      final file = await _file(title, episode);
      if (!await file.exists()) return null;
      final modified = await file.lastModified();
      if (DateTime.now().difference(modified) > const Duration(days: 7)) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => DanmakuComment.fromCacheJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String title, double episode, List<DanmakuComment> comments) async {
    try {
      final file = await _file(title, episode);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(comments.map((e) => e.toJson()).toList()));
    } on Object {
      // Cache failure must not affect playback or danmaku display.
    }
  }
}

class DanmakuRepository {
  DanmakuRepository(this._api, {DanmakuCache? cache}) : _cache = cache ?? FileDanmakuCache();

  static const maxConcurrency = 6;
  static const sourceTimeout = Duration(seconds: 8);
  static const totalBudget = Duration(seconds: 12);
  final DanmakuApi _api;
  final DanmakuCache _cache;

  Future<DanmakuLoadResult> load({
    required String title,
    required double episodeNumber,
    int? totalEpisodes,
    int maxSources = 12,
    bool allowCache = true,
    DanmakuProgress? onProgress,
  }) async {
    final cleanTitle = cleanDanmakuTitle(title);
    if (cleanTitle.isEmpty) {
      return const DanmakuLoadResult(
        comments: [],
        loadedSources: 0,
        totalSources: 0,
        fromCache: false,
        message: '无法识别标题',
      );
    }
    if (allowCache) {
      final cached = await _cache.read(cleanTitle, episodeNumber);
      if (cached != null) {
        return DanmakuLoadResult(
          comments: cached,
          loadedSources: cached.map((e) => e.source).toSet().length,
          totalSources: cached.map((e) => e.source).toSet().length,
          fromCache: true,
        );
      }
    }

    final animes = (await _api.search(cleanTitle, timeout: sourceTimeout))
        .take(maxSources)
        .toList();
    if (animes.isEmpty) {
      return const DanmakuLoadResult(
        comments: [],
        loadedSources: 0,
        totalSources: 0,
        fromCache: false,
        message: '未找到该作品的弹幕',
      );
    }

    final episodeResults = List<({DanmakuAnime anime, DanmakuEpisode episode})?>.filled(animes.length, null);
    await _withConcurrency(animes, maxConcurrency, (anime) async {
      final episodes = await _api.episodes(anime.animeId, timeout: sourceTimeout);
      final matched = matchEpisode(
        episodes: episodes,
        episodeNumber: episodeNumber,
        totalEpisodes: totalEpisodes,
        sourceTitle: anime.animeTitle,
        targetTitle: title,
      );
      if (matched != null) return (anime: anime, episode: matched);
      return null;
    }, (index, value) => episodeResults[index] = value).timeout(totalBudget, onTimeout: () {});
    final matched = episodeResults.whereType<({DanmakuAnime anime, DanmakuEpisode episode})>().toList();
    if (matched.isEmpty) {
      return DanmakuLoadResult(
        comments: const [],
        loadedSources: 0,
        totalSources: animes.length,
        fromCache: false,
        message: '未能匹配当前集数',
      );
    }

    final sourceResults = List<DanmakuSourceComments?>.filled(matched.length, null);
    var loaded = 0;
    var commentCount = 0;
    await _withConcurrency(matched, maxConcurrency, (item) async {
      final comments = await _api.comments(
        item.episode.episodeId,
        source: item.anime.source,
        timeout: sourceTimeout,
      );
      return DanmakuSourceComments(source: item.anime.source, comments: comments);
    }, (index, value) {
      sourceResults[index] = value;
      if (value != null) {
        loaded++;
        commentCount += value.comments.length;
        onProgress?.call(loaded, matched.length, commentCount);
      }
    }).timeout(totalBudget, onTimeout: () {});

    final usable = sourceResults.whereType<DanmakuSourceComments>().toList();
    final merged = mergeDanmaku(usable);
    if (merged.isNotEmpty) {
      await _cache.write(cleanTitle, episodeNumber, merged);
    }
    return DanmakuLoadResult(
      comments: merged,
      loadedSources: usable.length,
      totalSources: animes.length,
      fromCache: false,
      message: usable.isEmpty ? '弹幕源暂时不可用' : '',
    );
  }

  Future<void> _withConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R?> Function(T item) worker,
    void Function(int index, R? value) onResult,
  ) async {
    var next = 0;
    Future<void> run() async {
      while (next < items.length) {
        final index = next++;
        R? value;
        try {
          value = await worker(items[index]);
        } on Object {
          value = null;
        }
        onResult(index, value);
      }
    }
    await Future.wait(List.generate(
      items.length < concurrency ? items.length : concurrency,
      (_) => run(),
    ));
  }
}
