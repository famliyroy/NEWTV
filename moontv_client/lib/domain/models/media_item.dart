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

  static String _string(dynamic value) => value == null ? '' : '$value';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map(_string).where((item) => item.isNotEmpty).toList();
    }
    if (value is String && value.isNotEmpty) return [value];
    return const [];
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: _string(json['id'] ?? json['vod_id'] ?? json['detailId']),
      title: _string(json['title'] ?? json['vod_name'] ?? json['name']),
      poster: _string(json['poster'] ?? json['vod_pic'] ?? json['cover']),
      source: _string(json['source'] ?? json['source_code']),
      sourceName: _string(
        json['source_name'] ?? json['sourceName'] ?? json['source'],
      ),
      episodes: _stringList(json['episodes'] ?? json['vod_play_url']),
      episodeTitles: _stringList(
        json['episodes_titles'] ?? json['episodeTitles'],
      ),
      year: _string(json['year'] ?? json['vod_year']),
      description: _string(json['desc'] ?? json['vod_content'] ?? json['description']),
      remarks: _string(json['vod_remarks'] ?? json['remarks']),
      typeName: _string(json['type_name'] ?? json['class']),
      doubanId: _string(json['douban_id']),
      weight: json['weight'] is num
          ? (json['weight'] as num).toInt()
          : int.tryParse(_string(json['weight'])) ?? 0,
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
  });

  final MediaItem item;
  final int episodeIndex;
  final List<MediaItem> availableSources;
}
