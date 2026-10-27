/// 海报图片地址解析。
///
/// 豆瓣 / TMDB 图床有防盗链，客户端直连大概率拿到 403/占位图；
/// MoonTVPlus 后端提供 `/api/image-proxy?url=`，由服务端带 Referer 取图。
/// 该接口需要登录态（实测未带 Cookie 返回 401），因此这里同时缓存
/// 当前会话的 Cookie 头，供图片请求复用。
class ImageAuth {
  ImageAuth._();

  static String _baseUrl = '';
  static String _cookieHeader = '';

  static String get baseUrl => _baseUrl;

  static Map<String, String> get headers =>
      _cookieHeader.isEmpty ? const {} : {'Cookie': _cookieHeader};

  static void update({
    required String baseUrl,
    required String cookieHeader,
  }) {
    _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    _cookieHeader = cookieHeader;
  }

  static void clear() {
    _baseUrl = '';
    _cookieHeader = '';
  }
}

/// 一次图片请求所需的地址与请求头。
class ImageRequest {
  const ImageRequest(this.url, this.headers);

  final String url;
  final Map<String, String> headers;

  bool get isEmpty => url.isEmpty;
}

/// 需要走服务端代理的图床域名。
const _proxiedHosts = <String>[
  'doubanio.com',
  'douban.com',
  'image.tmdb.org',
  'tmdb.org',
];

bool _needsProxy(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http')) return false;
  return _proxiedHosts.any(lower.contains);
}

/// 解析图片地址：需要代理时改写为服务端 `/api/image-proxy`。
ImageRequest resolveImage(String rawUrl) {
  final url = rawUrl.trim();
  if (url.isEmpty) return const ImageRequest('', {});
  if (!_needsProxy(url) || ImageAuth.baseUrl.isEmpty) {
    return ImageRequest(url, const {});
  }
  return ImageRequest(
    '${ImageAuth.baseUrl}/api/image-proxy?url=${Uri.encodeComponent(url)}',
    ImageAuth.headers,
  );
}

/// 原图地址（不走代理），用于代理失败后的兜底。
ImageRequest directImage(String rawUrl) {
  final url = rawUrl.trim();
  if (url.isEmpty) return const ImageRequest('', {});
  return ImageRequest(url, const {});
}
