import '../models/danmaku.dart';

final _chineseDigits = <String, int>{
  '零': 0,
  '〇': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

int? _parseChineseNumber(String input) {
  if (input.isEmpty) return null;
  if (!input.split('').every((char) =>
      _chineseDigits.containsKey(char) || char == '十' || char == '百' || char == '千')) {
    return null;
  }
  var total = 0;
  var section = 0;
  var number = 0;
  for (final char in input.split('')) {
    final digit = _chineseDigits[char];
    if (digit != null) {
      number = digit;
      continue;
    }
    final unit = switch (char) { '十' => 10, '百' => 100, '千' => 1000, _ => 0 };
    if (unit == 0) return null;
    if (number == 0) number = 1;
    section += number * unit;
    number = 0;
    if (unit == 1000) {
      total += section;
      section = 0;
    }
  }
  return total + section + number;
}

double? parseEpisodeNumber(String text) {
  final value = text.trim();
  if (value.isEmpty ||
      RegExp(r'(?:19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}').hasMatch(value)) {
    return null;
  }

  final chinese = RegExp(
    r'第\s*(\d+(?:\.\d+)?|[零〇一二三四五六七八九十百千两]+)\s*(?:话|集|話)',
    caseSensitive: false,
  ).firstMatch(value);
  if (chinese != null) {
    final token = chinese.group(1)!;
    final numeric = double.tryParse(token);
    if (numeric != null) return numeric;
    return _parseChineseNumber(token)?.toDouble();
  }

  final english = RegExp(
    r'\b(?:episode|ep|e)\s*(\d{1,4}(?:\.\d+)?)\b',
    caseSensitive: false,
  ).firstMatch(value);
  if (english != null) return double.tryParse(english.group(1)!);

  final labelled = RegExp(r'(?:^|[-–—#]\s*|\s#\s*)(\d{1,4}(?:\.\d+)?)\s*$')
      .firstMatch(value);
  if (labelled != null) {
    final candidate = double.tryParse(labelled.group(1)!);
    if (candidate != null && candidate < 1900) return candidate;
  }

  if (RegExp(r'^\d{1,3}(?:\.\d+)?$').hasMatch(value)) {
    return double.tryParse(value);
  }
  return null;
}

bool _isMovieLike(String title) =>
    RegExp(r'剧场版|劇場版|movie|ova|oad', caseSensitive: false).hasMatch(title);

DanmakuEpisode? matchEpisode({
  required List<DanmakuEpisode> episodes,
  required double episodeNumber,
  int? totalEpisodes,
  String sourceTitle = '',
  String targetTitle = '',
  bool isMovie = false,
}) {
  if (episodes.isEmpty) return null;

  for (final candidate in episodes) {
    if (parseEpisodeNumber(candidate.episodeTitle) == episodeNumber) {
      return candidate;
    }
  }

  if (isMovie || (_isMovieLike(sourceTitle) && _isMovieLike(targetTitle))) {
    if (episodes.length == 1) return episodes.first;
    for (final candidate in episodes) {
      if (_isMovieLike(candidate.episodeTitle)) return candidate;
    }
  }

  if (totalEpisodes == episodes.length && episodeNumber == episodeNumber.roundToDouble()) {
    final index = episodeNumber.toInt() - 1;
    if (index >= 0 && index < episodes.length) return episodes[index];
  }

  if (episodes.length == 1) return episodes.first;
  return null;
}
