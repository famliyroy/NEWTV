import '../../domain/models/media_item.dart';

/// 按标题把搜索结果聚成「多源」分组，组内按权重降序（权重高的作为默认源）。
///
/// 搜索页与详情页的「无 source 条目自动接源」共用同一套规则，
/// 保证两处点击行为一致。
List<List<MediaItem>> groupByTitle(Iterable<MediaItem> items) {
  final groups = <String, List<MediaItem>>{};
  for (final item in items) {
    final key = item.title.trim();
    if (key.isEmpty) continue;
    groups.putIfAbsent(key, () => []).add(item);
  }
  return groups.values.map((group) {
    return List<MediaItem>.of(group)
      ..sort((a, b) => b.weight.compareTo(a.weight));
  }).toList();
}

/// 为一条「没有可播放 source」的条目（豆瓣 / TMDB / 番剧表）挑选对应片源组。
///
/// 优先级：标题完全一致 → 标题互相包含 → 放弃。
/// 标题命中多个时，取年份与目标最接近的一组。
List<MediaItem>? pickBestGroup(MediaItem target, Iterable<MediaItem> candidates) {
  final all = candidates.where((item) => item.source.isNotEmpty).toList();
  if (all.isEmpty) return null;

  final wanted = target.title.trim();
  if (wanted.isEmpty) return null;

  final exact = groupByTitle(
    all.where((item) => item.title.trim() == wanted),
  );
  if (exact.isNotEmpty) return _closestYear(exact, target.year);

  // 片源站经常带后缀（如「狂飙之浴血玫瑰」），退一步用包含关系兜底。
  final loose = groupByTitle(
    all.where((item) {
      final title = item.title.trim();
      if (title.isEmpty) return false;
      return title.contains(wanted) || wanted.contains(title);
    }),
  );
  if (loose.isNotEmpty) return _closestYear(loose, target.year);

  return null;
}

List<MediaItem> _closestYear(List<List<MediaItem>> groups, String year) {
  final targetYear = int.tryParse(RegExp(r'\d{4}').firstMatch(year)?.group(0) ?? '');

  var best = groups.first;
  if (targetYear != null && groups.length > 1) {
    var bestDiff = 9999;
    for (final group in groups) {
      final diff = _yearDiff(group.first.year, targetYear);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = group;
      }
    }
  } else if (groups.length > 1) {
    // 无年份信息时取源数量最多的一组，多源通常更可靠。
    final sorted = List<List<MediaItem>>.of(groups)
      ..sort((a, b) => b.length.compareTo(a.length));
    best = sorted.first;
  }

  return _rankGroup(best, targetYear);
}

/// 组内排序：年份最接近的排最前（同名不同年份的剧很常见），
/// 其次比较权重，最后按原始顺序保持稳定。
List<MediaItem> _rankGroup(List<MediaItem> group, int? targetYear) {
  final indexed = group.asMap().entries.toList();
  indexed.sort((a, b) {
    final diffA = targetYear == null ? 0 : _yearDiff(a.value.year, targetYear);
    final diffB = targetYear == null ? 0 : _yearDiff(b.value.year, targetYear);
    if (diffA != diffB) return diffA.compareTo(diffB);
    final byWeight = b.value.weight.compareTo(a.value.weight);
    if (byWeight != 0) return byWeight;
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList();
}

/// 与目标年份的差值；缺失或非 4 位年份视为最不匹配。
int _yearDiff(String year, int targetYear) {
  final match = RegExp(r'\d{4}').firstMatch(year);
  final value = int.tryParse(match?.group(0) ?? '');
  if (value == null) return 999;
  return (value - targetYear).abs();
}
