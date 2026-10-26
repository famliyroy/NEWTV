String cleanDanmakuTitle(String input) {
  final original = input.trim();
  if (original.isEmpty) return '';

  var value = original.replaceAll(
    RegExp(r'\.(mkv|mp4|avi|mov|wmv|flv|ts)$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]|（[^）]*）|\([^)]*\)'), ' ');
  value = value.replaceAll(
    RegExp(
      r'(?<![a-z0-9])(1080p|720p|2160p|4k|8k|hevc|avc|x264|x265|web[- ]?dl|webrip|blu[- ]?ray|dvdrip|aac|flac|10bit|8bit)(?![a-z0-9])',
      caseSensitive: false,
    ),
    ' ',
  );
  value = value.replaceAll(
    RegExp(
      r'(简中|繁中|简繁|字幕组|喵萌奶茶屋|喵萌|LoliHouse|ANi|桜都)',
      caseSensitive: false,
    ),
    ' ',
  );
  value = value.replaceAll(
    RegExp(
      r'第\s*(?:\d+(?:\.\d+)?|[零〇一二三四五六七八九十百千两]+)\s*(?:话|集|話)',
      caseSensitive: false,
    ),
    ' ',
  );
  value = value.replaceAll(
    RegExp(r'\b(?:episode|ep|e)\s*\d{1,4}(?:\.\d+)?\b', caseSensitive: false),
    ' ',
  );
  value = value.replaceAll(RegExp(r'[-_–—]\s*\d{1,4}(?:\.\d+)?\s*$'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ');
  value = value.replaceAll(RegExp(r'^[\s._\-–—#]+|[\s._\-–—#]+$'), '');
  return value.isEmpty ? original : value;
}
