class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.source,
    required this.sourceName,
    this.poster = '',
    this.episodes = const [],
    this.episodeTitles = const [],
    this.year = '',
    this.description = '',
    this.remarks = '',
    this.typeName = '',
    this.doubanId = '',
    this.weight = 0,
    this.rate = '',
    this.lastEpisodeIndex = 0,
    this.playTimeSeconds = 0,
    this.totalTimeSeconds = 0,
    this.saveTime = 0,
    this.totalEpisodes = 0,
  });

  final String id;
  final String title;
  final String poster;
  final String source;
  final String sourceName;
  final List<String> episodes;
  final List<String> episodeTitles;
  final String year;
  final String description;
  final String remarks;
  final String typeName;
  final String doubanId;
  final int weight;
  final String rate;
  final int lastEpisodeIndex;
  final int playTimeSeconds;
  final int totalTimeSeconds;
  final int saveTime;
  final int totalEpisodes;

  String get storageKey => '$source+$id';

  static String _string(dynamic value) => value == null ? '' : '$value';

  static int _int(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(_string(value)) ?? fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map(_string).where((item) => item.isNotEmpty).toList();
    }
    if (value is String && value.isNotEmpty) return [value];
    return const [];
  }

  static String _year(dynamic value) {
    final raw = _string(value);
    final match = RegExp(r'\d{4}').firstMatch(raw);
    return match?.group(0) ?? raw;
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final rawIndex = _int(json['index'], 1);
    final episodes = _stringList(json['episodes'] ?? json['vod_play_url']);
    final mediaType = _string(json['media_type']);
    return MediaItem(
      id: _string(json['id'] ?? json['vod_id'] ?? json['detailId']),
      title: _string(json['title'] ?? json['vod_name'] ?? json['name'] ?? json['search_title']),
      poster: _string(json['poster'] ?? json['vod_pic'] ?? json['cover'] ?? json['pic'] ?? json['poster_path']),
      source: _string(json['source'] ?? json['source_code']),
      sourceName: _string(
        json['source_name'] ?? json['sourceName'] ?? json['source'],
      ),
      episodes: episodes,
      episodeTitles: _stringList(
        json['episodes_titles'] ?? json['episodeTitles'],
      ),
      year: _year(json['year'] ?? json['vod_year'] ?? json['release_date']),
      description: _string(json['desc'] ?? json['vod_content'] ?? json['description'] ?? json['overview']),
      remarks: _string(json['vod_remarks'] ?? json['remarks']),
      typeName: _string(json['type_name'] ?? json['class'] ?? json['weekday'] ?? mediaType),
      doubanId: _string(json['douban_id']),
      weight: _int(json['weight']),
      rate: _string(json['rate'] ?? json['vote_average']),
      lastEpisodeIndex: rawIndex > 0 ? rawIndex - 1 : 0,
      playTimeSeconds: _int(json['play_time']),
      totalTimeSeconds: _int(json['total_time']),
      saveTime: _int(json['save_time']),
      totalEpisodes: _int(json['total_episodes'], episodes.length),
    );
  }

  MediaItem copyWith({
    String? id,
    String? title,
    String? poster,
    String? source,
    String? sourceName,
    List<String>? episodes,
    List<String>? episodeTitles,
    String? year,
    String? description,
    String? remarks,
    String? typeName,
    String? doubanId,
    int? weight,
    String? rate,
    int? lastEpisodeIndex,
    int? playTimeSeconds,
    int? totalTimeSeconds,
    int? saveTime,
    int? totalEpisodes,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      source: source ?? this.source,
      sourceName: sourceName ?? this.sourceName,
      episodes: episodes ?? this.episodes,
      episodeTitles: episodeTitles ?? this.episodeTitles,
      year: year ?? this.year,
      description: description ?? this.description,
      remarks: remarks ?? this.remarks,
      typeName: typeName ?? this.typeName,
      doubanId: doubanId ?? this.doubanId,
      weight: weight ?? this.weight,
      rate: rate ?? this.rate,
      lastEpisodeIndex: lastEpisodeIndex ?? this.lastEpisodeIndex,
      playTimeSeconds: playTimeSeconds ?? this.playTimeSeconds,
      totalTimeSeconds: totalTimeSeconds ?? this.totalTimeSeconds,
      saveTime: saveTime ?? this.saveTime,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
    );
  }

  String episodeLabel(int index) {
    if (index >= 0 && index < episodeTitles.length && episodeTitles[index].isNotEmpty) {
      return episodeTitles[index];
    }
    return '第 ${index + 1} 集';
  }
}

class PlaybackContext {
  const PlaybackContext({
    required this.item,
    required this.episodeIndex,
    this.availableSources = const [],
    this.initialPositionSeconds = 0,
  });

  final MediaItem item;
  final int episodeIndex;
  final List<MediaItem> availableSources;
  final int initialPositionSeconds;
}
