import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';

import '../config/server_config.dart';
import '../utils/image_url.dart';

enum SessionStatus { unconfigured, unauthenticated, authenticated }

class SessionManager extends ChangeNotifier {
  SessionManager(this._cookieJar, ServerConfig? initialServer, bool hasCookies)
      : _server = initialServer,
        _status = initialServer == null
            ? SessionStatus.unconfigured
            : hasCookies
                ? SessionStatus.authenticated
                : SessionStatus.unauthenticated;

  final CookieJar _cookieJar;
  ServerConfig? _server;
  SessionStatus _status;

  ServerConfig? get server => _server;
  SessionStatus get status => _status;
  bool get isAuthenticated => _status == SessionStatus.authenticated;

  /// 把当前 Cookie 同步给图片代理：`/api/image-proxy` 需要登录态，
  /// 而 `CachedNetworkImage` 不走 dio 的 CookieManager。
  Future<void> refreshImageAuth() async {
    final current = _server;
    if (current == null) {
      ImageAuth.clear();
      return;
    }
    try {
      final cookies =
          await _cookieJar.loadForRequest(Uri.parse(current.baseUrl));
      ImageAuth.update(
        baseUrl: current.baseUrl,
        cookieHeader:
            cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
      );
    } on Object {
      ImageAuth.update(baseUrl: current.baseUrl, cookieHeader: '');
    }
  }

  Future<bool> hasCookies() async {
    final current = _server;
    if (current == null) return false;
    return (await _cookieJar.loadForRequest(Uri.parse(current.baseUrl))).isNotEmpty;
  }

  Future<void> configure(ServerConfig config, {required bool authenticated}) async {
    _server = config;
    _status = authenticated
        ? SessionStatus.authenticated
        : SessionStatus.unauthenticated;
    await refreshImageAuth();
    notifyListeners();
  }

  void markAuthenticated() {
    _status = SessionStatus.authenticated;
    notifyListeners();
    // 登录后 Cookie 才可用，刷新完成后通知一次让海报重新走代理。
    unawaited(
      refreshImageAuth().whenComplete(() {
        if (_status == SessionStatus.authenticated) notifyListeners();
      }),
    );
  }

  Future<void> expire() async {
    await _cookieJar.deleteAll();
    _status = SessionStatus.unauthenticated;
    ImageAuth.update(baseUrl: _server?.baseUrl ?? '', cookieHeader: '');
    notifyListeners();
  }

  Future<void> clearSession() async {
    await _cookieJar.deleteAll();
    _status = SessionStatus.unauthenticated;
    ImageAuth.update(baseUrl: _server?.baseUrl ?? '', cookieHeader: '');
    notifyListeners();
  }

  Future<void> clearServer() async {
    await _cookieJar.deleteAll();
    _server = null;
    _status = SessionStatus.unconfigured;
    ImageAuth.clear();
    notifyListeners();
  }
}
