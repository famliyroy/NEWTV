import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the complete cookie-jar payload without logging or exposing cookies.
class SecureCookieStorage implements Storage {
  SecureCookieStorage(this._secureStorage);

  static const _storageKey = 'newtv.cookie_jar.v1';
  final FlutterSecureStorage _secureStorage;
  final Map<String, String> _values = {};

  Future<void> _flush() async {
    await _secureStorage.write(key: _storageKey, value: jsonEncode(_values));
  }

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    final raw = await _secureStorage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _values
          ..clear()
          ..addAll(decoded.map((key, value) => MapEntry(key, '$value')));
      }
    } on FormatException {
      await _secureStorage.delete(key: _storageKey);
    }
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    await _flush();
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    await _flush();
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      _values.remove(key);
    }
    await _flush();
  }
}
