import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';

import '../config/server_config.dart';

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
    notifyListeners();
  }

  void markAuthenticated() {
    _status = SessionStatus.authenticated;
    notifyListeners();
  }

  Future<void> expire() async {
    await _cookieJar.deleteAll();
    _status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> clearSession() async {
    await _cookieJar.deleteAll();
    _status = SessionStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> clearServer() async {
    await _cookieJar.deleteAll();
    _server = null;
    _status = SessionStatus.unconfigured;
    notifyListeners();
  }
}
