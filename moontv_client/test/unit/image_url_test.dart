import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/utils/image_url.dart';

void main() {
  setUp(() {
    ImageAuth.clear();
  });

  tearDown(() {
    ImageAuth.clear();
  });

  group('resolveImage', () {
    test('豆瓣图床改写成服务端图片代理并带上 Cookie', () {
      ImageAuth.update(
        baseUrl: 'https://tv.example.com/',
        cookieHeader: 'auth=abc',
      );
      final request = resolveImage(
        'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p1.jpg',
      );
      expect(request.url, startsWith('https://tv.example.com/api/image-proxy?url='));
      expect(request.url, contains(Uri.encodeComponent('https://img9.doubanio.com')));
      expect(request.headers['Cookie'], 'auth=abc');
    });

    test('TMDB 图床同样走代理', () {
      ImageAuth.update(baseUrl: 'https://tv.example.com', cookieHeader: '');
      final request = resolveImage('https://image.tmdb.org/t/p/w500/a.jpg');
      expect(request.url, contains('/api/image-proxy'));
    });

    test('番剧图床保持直连，不额外消耗服务器带宽', () {
      ImageAuth.update(baseUrl: 'https://tv.example.com', cookieHeader: 'auth=abc');
      final request = resolveImage('https://lain.bgm.tv/pic/cover/l/1.jpg');
      expect(request.url, 'https://lain.bgm.tv/pic/cover/l/1.jpg');
      expect(request.headers, isEmpty);
    });

    test('未配置服务器时原样返回', () {
      final request = resolveImage('https://img1.doubanio.com/a.jpg');
      expect(request.url, 'https://img1.doubanio.com/a.jpg');
    });

    test('空地址返回空请求', () {
      expect(resolveImage('  ').isEmpty, isTrue);
    });
  });

  group('directImage', () {
    test('始终返回原图地址', () {
      ImageAuth.update(baseUrl: 'https://tv.example.com', cookieHeader: 'auth=abc');
      final request = directImage('https://img1.doubanio.com/a.jpg');
      expect(request.url, 'https://img1.doubanio.com/a.jpg');
      expect(request.headers, isEmpty);
    });
  });
}
