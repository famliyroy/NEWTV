import 'media_item.dart';

/// 某一日的排期（周一…周日）。
class BangumiDay {
  const BangumiDay({
    required this.labelCn,
    required this.labelEn,
    required this.items,
  });

  final String labelCn;
  final String labelEn;
  final List<MediaItem> items;
}

/// `/api/bangumi/schedule` 与 `/api/bangumi/calendar` 的统一结构。
///
/// schedule：`{season, year, days: [{en, cn, slots: [{time, items: [...]}]}]}`
/// calendar：[{weekday: {en, cn}, items: [...]}]
class BangumiSchedule {
  const BangumiSchedule({
    required this.season,
    required this.year,
    required this.days,
  });

  final String season;
  final int year;
  final List<BangumiDay> days;

  List<MediaItem> get allItems => [for (final day in days) ...day.items];

  bool get isEmpty => days.every((day) => day.items.isEmpty);

  static const _seasonLabels = {
    'winter': '冬季',
    'spring': '春季',
    'summer': '夏季',
    'fall': '秋季',
    'autumn': '秋季',
  };

  String get seasonLabel => _seasonLabels[season.toLowerCase()] ?? season;

  static BangumiSchedule empty() =>
      const BangumiSchedule(season: '', year: 0, days: []);

  static BangumiSchedule? tryParse(dynamic data) {
    if (data is List) return _parseCalendar(data);
    if (data is! Map<String, dynamic>) return null;
    final days = data['days'];
    if (days is! List) return null;
    return BangumiSchedule(
      season: '${data['season'] ?? ''}',
      year: int.tryParse('${data['year'] ?? ''}') ?? 0,
      days: [
        for (final day in days.whereType<Map<String, dynamic>>())
          BangumiDay(
            labelCn: '${day['cn'] ?? day['en'] ?? ''}',
            labelEn: '${day['en'] ?? ''}',
            items: _collectItems(day),
          ),
      ],
    );
  }

  static BangumiSchedule? _parseCalendar(List<dynamic> data) {
    final days = <BangumiDay>[];
    for (final entry in data.whereType<Map<String, dynamic>>()) {
      final weekday = entry['weekday'];
      final items = entry['items'];
      days.add(
        BangumiDay(
          labelCn: weekday is Map ? '${weekday['cn'] ?? ''}' : '',
          labelEn: weekday is Map ? '${weekday['en'] ?? ''}' : '',
          items: items is List ? _mapItems(items) : const [],
        ),
      );
    }
    if (days.isEmpty) return null;
    return BangumiSchedule(season: '', year: 0, days: days);
  }

  /// schedule 接口把条目嵌在 `slots[].items` 里，这里拍平并按 id 去重。
  static List<MediaItem> _collectItems(Map<String, dynamic> day) {
    final raw = <dynamic>[];
    final slots = day['slots'];
    if (slots is List) {
      for (final slot in slots.whereType<Map<String, dynamic>>()) {
        final items = slot['items'];
        if (items is List) raw.addAll(items);
      }
    }
    final direct = day['items'];
    if (direct is List) raw.addAll(direct);
    return _mapItems(raw);
  }

  static List<MediaItem> _mapItems(List<dynamic> raw) {
    final seen = <String>{};
    final items = <MediaItem>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final images = entry['images'];
      final poster = images is Map
          ? '${images['common'] ?? images['medium'] ?? images['large'] ?? ''}'
          : '';
      final rating = entry['rating'];
      final item = MediaItem(
        id: '${entry['id'] ?? ''}',
        title: '${entry['name_cn'] ?? ''}'.trim().isEmpty
            ? '${entry['name'] ?? ''}'
            : '${entry['name_cn']}',
        source: '',
        sourceName: 'Bangumi',
        poster: poster,
        year: '${entry['air_date'] ?? ''}',
        remarks: rating == null ? '' : '$rating',
      );
      if (item.title.isEmpty || !seen.add(item.id)) continue;
      items.add(item);
    }
    return items;
  }
}
