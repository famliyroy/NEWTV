import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/player/hls_quality.dart';

const _master = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080,NAME="高清"
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1200000
mid/index.m3u8
''';

void main() {
  group('parseMasterPlaylist', () {
    test('解析变体并按码率降序排列', () {
      final variants = parseMasterPlaylist(
        _master,
        Uri.parse('https://cdn.example.com/vod/abc/index.m3u8'),
      );
      expect(variants.length, 3);
      expect(variants.map((v) => v.label).toList(), ['1080P', '1.2 Mbps', '720P']);
      expect(variants.first.bandwidth, 2800000);
      expect(
        variants.first.url,
        'https://cdn.example.com/vod/abc/1080/index.m3u8',
      );
      expect(variants.last.url, 'https://cdn.example.com/vod/abc/720/index.m3u8');
    });

    test('同名分辨率用码率后缀区分，避免菜单重复项', () {
      const text = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080
a.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4200000,RESOLUTION=1920x1080
b.m3u8
''';
      final variants = parseMasterPlaylist(
        text,
        Uri.parse('https://cdn.example.com/x/index.m3u8'),
      );
      expect(variants.map((v) => v.label).toSet().length, 2);
      expect(variants.first.label, startsWith('1080P'));
    });

    test('单码率 media playlist 返回空列表', () {
      const text = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg-1.ts
''';
      final variants = parseMasterPlaylist(
        text,
        Uri.parse('https://cdn.example.com/x/index.m3u8'),
      );
      expect(variants, isEmpty);
    });

    test('忽略缺失子播放列表地址的 STREAM-INF', () {
      const text = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080
#EXTINF:10.0,
seg.ts
''';
      final variants = parseMasterPlaylist(
        text,
        Uri.parse('https://cdn.example.com/x/index.m3u8'),
      );
      expect(variants, isEmpty);
    });
  });

  group('firstSegmentUri', () {
    test('跳过标签行取首个分片', () {
      const text = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:9.9,
seg-1.ts
#EXTINF:9.9,
seg-2.ts
''';
      final uri = firstSegmentUri(
        text,
        Uri.parse('https://cdn.example.com/vod/1080/index.m3u8'),
      );
      expect(uri.toString(), 'https://cdn.example.com/vod/1080/seg-1.ts');
    });

    test('绝对地址保持原样', () {
      final uri = firstSegmentUri(
        '#EXTINF:10,\nhttps://other.example.com/a.ts\n',
        Uri.parse('https://cdn.example.com/vod/index.m3u8'),
      );
      expect(uri.toString(), 'https://other.example.com/a.ts');
    });

    test('没有分片时返回 null', () {
      expect(firstSegmentUri('#EXTM3U\n', Uri.parse('https://a.com/i.m3u8')), isNull);
    });
  });

  group('sourceUriOf', () {
    test('从本站代理地址还原源站地址', () {
      final uri = sourceUriOf(
        'https://tv.example.com/api/proxy-m3u8?url=https%3A%2F%2Fcdn.a.com%2Fv%2F1080%2Findex.m3u8&source=x&adblock=false',
      );
      expect(uri.toString(), 'https://cdn.a.com/v/1080/index.m3u8');
    });

    test('普通地址与无效参数返回 null', () {
      expect(sourceUriOf('https://cdn.a.com/v/index.m3u8'), isNull);
      expect(sourceUriOf('https://tv.example.com/api/proxy-m3u8?url=%2Frel'), isNull);
      expect(sourceUriOf('not a url'), isNull);
    });
  });

  group('HlsVariant.speedLabel', () {
    test('未测速显示测速失败，有值按量级展示', () {
      const variant = HlsVariant(label: '1080P', bandwidth: 100, url: 'u');
      expect(variant.speedLabel, '测速失败');
      expect(variant.withSpeed(2 * 1024 * 1024).speedLabel, '2.0 MB/s');
      expect(variant.withSpeed(300 * 1024).speedLabel, '300 KB/s');
    });
  });
}
