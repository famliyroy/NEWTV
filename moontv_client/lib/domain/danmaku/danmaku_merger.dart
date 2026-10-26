import '../models/danmaku.dart';

List<T> uniformSample<T>(List<T> input, int limit) {
  if (limit <= 0) return <T>[];
  if (input.length <= limit) return List<T>.of(input);
  if (limit == 1) return <T>[input.first];
  return List<T>.generate(limit, (index) {
    final sourceIndex = (index * (input.length - 1) / (limit - 1)).round();
    return input[sourceIndex];
  });
}

String danmakuDedupKey(DanmakuComment comment) {
  final time = (comment.time * 10).round();
  final text = comment.text.replaceAll(RegExp(r'\s+'), '');
  return '$time|$text';
}

List<DanmakuComment> _applyTotalLimit(
  List<DanmakuComment> comments,
  int maxTotal,
) {
  if (comments.length <= maxTotal) return comments;
  if (maxTotal <= 0) return const [];

  final groups = <String, List<DanmakuComment>>{};
  for (final comment in comments) {
    groups.putIfAbsent(comment.source, () => []).add(comment);
  }
  final keys = groups.keys.toList()..sort();
  if (keys.length > maxTotal) keys.removeRange(maxTotal, keys.length);

  final quotas = <String, int>{for (final key in keys) key: 0};
  var remaining = maxTotal;
  while (remaining > 0) {
    var changed = false;
    for (final key in keys) {
      if (remaining == 0) break;
      if (quotas[key]! < groups[key]!.length) {
        quotas[key] = quotas[key]! + 1;
        remaining--;
        changed = true;
      }
    }
    if (!changed) break;
  }

  return [
    for (final key in keys)
      ...uniformSample(groups[key]!, quotas[key]!),
  ]..sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      if (byTime != 0) return byTime;
      final bySource = a.source.compareTo(b.source);
      return bySource != 0 ? bySource : a.text.compareTo(b.text);
    });
}

List<DanmakuComment> mergeDanmaku(
  Iterable<DanmakuSourceComments> sources, {
  int maxPerSource = 3000,
  int maxTotal = 12000,
}) {
  final merged = <String, DanmakuComment>{};
  for (final source in sources) {
    final ordered = List<DanmakuComment>.of(source.comments)
      ..sort((a, b) => a.time.compareTo(b.time));
    for (final candidate in uniformSample(ordered, maxPerSource)) {
      final key = danmakuDedupKey(candidate);
      final existing = merged[key];
      if (existing == null) {
        merged[key] = candidate;
      } else if (existing.color == 0xffffff && candidate.color != 0xffffff) {
        merged[key] = existing.copyWith(color: candidate.color);
      }
    }
  }
  final sorted = merged.values.toList()
    ..sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      if (byTime != 0) return byTime;
      final bySource = a.source.compareTo(b.source);
      return bySource != 0 ? bySource : a.text.compareTo(b.text);
    });
  return _applyTotalLimit(sorted, maxTotal);
}
