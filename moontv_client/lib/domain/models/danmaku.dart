enum DanmakuMode { scroll, bottom, top }

class DanmakuEpisode {
  const DanmakuEpisode({required this.episodeId, required this.episodeTitle});

  final String episodeId;
  final String episodeTitle;

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisode(
      episodeId: '${json['episodeId'] ?? ''}',
      episodeTitle: '${json['episodeTitle'] ?? ''}',
    );
  }
}

class DanmakuAnime {
  const DanmakuAnime({
    required this.animeId,
    required this.animeTitle,
    required this.source,
    this.episodeCount,
  });

  final String animeId;
  final String animeTitle;
  final String source;
  final int? episodeCount;

  factory DanmakuAnime.fromJson(Map<String, dynamic> json) {
    return DanmakuAnime(
      animeId: '${json['animeId'] ?? ''}',
      animeTitle: '${json['animeTitle'] ?? ''}',
      source: '${json['source'] ?? json['typeDescription'] ?? '未知来源'}',
      episodeCount: json['episodeCount'] is num
          ? (json['episodeCount'] as num).toInt()
          : int.tryParse('${json['episodeCount'] ?? ''}'),
    );
  }
}

class DanmakuComment {
  const DanmakuComment({
    required this.time,
    required this.text,
    required this.source,
    this.mode = DanmakuMode.scroll,
    this.fontSize = 25,
    this.color = 0xffffff,
    this.timestamp = 0,
    this.pool = '',
    this.userHash = '',
    this.id = '',
  });

  final double time;
  final DanmakuMode mode;
  final int fontSize;
  final int color;
  final int timestamp;
  final String pool;
  final String userHash;
  final String id;
  final String text;
  final String source;

  factory DanmakuComment.parse({
    required String p,
    required String text,
    required String source,
  }) {
    final parts = p.split(',');
    String at(int index) => index < parts.length ? parts[index] : '';
    final rawMode = int.tryParse(at(1)) ?? 1;
    return DanmakuComment(
      time: double.tryParse(at(0)) ?? 0,
      mode: switch (rawMode) {
        4 => DanmakuMode.bottom,
        5 => DanmakuMode.top,
        _ => DanmakuMode.scroll,
      },
      fontSize: int.tryParse(at(2)) ?? 25,
      color: int.tryParse(at(3)) ?? 0xffffff,
      timestamp: int.tryParse(at(4)) ?? 0,
      pool: at(5),
      userHash: at(6),
      id: at(7),
      text: text.trim(),
      source: source,
    );
  }

  factory DanmakuComment.fromJson(
    Map<String, dynamic> json, {
    required String source,
  }) {
    return DanmakuComment.parse(
      p: '${json['p'] ?? ''}',
      text: '${json['m'] ?? ''}',
      source: source,
    );
  }

  DanmakuComment copyWith({int? color}) {
    return DanmakuComment(
      time: time,
      mode: mode,
      fontSize: fontSize,
      color: color ?? this.color,
      timestamp: timestamp,
      pool: pool,
      userHash: userHash,
      id: id,
      text: text,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'mode': mode.index,
    'fontSize': fontSize,
    'color': color,
    'timestamp': timestamp,
    'pool': pool,
    'userHash': userHash,
    'id': id,
    'text': text,
    'source': source,
  };

  factory DanmakuComment.fromCacheJson(Map<String, dynamic> json) {
    return DanmakuComment(
      time: (json['time'] as num?)?.toDouble() ?? 0,
      mode: DanmakuMode.values[(json['mode'] as num?)?.toInt() ?? 0],
      fontSize: (json['fontSize'] as num?)?.toInt() ?? 25,
      color: (json['color'] as num?)?.toInt() ?? 0xffffff,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      pool: '${json['pool'] ?? ''}',
      userHash: '${json['userHash'] ?? ''}',
      id: '${json['id'] ?? ''}',
      text: '${json['text'] ?? ''}',
      source: '${json['source'] ?? ''}',
    );
  }
}

class DanmakuSourceComments {
  const DanmakuSourceComments({required this.source, required this.comments});

  final String source;
  final List<DanmakuComment> comments;
}
