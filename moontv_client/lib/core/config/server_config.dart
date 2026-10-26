import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerConfig {
  const ServerConfig({
    required this.baseUrl,
    this.allowSelfSigned = false,
    this.userAgent = 'NEWTV/0.1',
  });

  final String baseUrl;
  final bool allowSelfSigned;
  final String userAgent;

  bool get isSecure => Uri.parse(baseUrl).scheme == 'https';

  static String? normalize(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(path: path).toString();
  }
}

class ServerConfigStore {
  ServerConfigStore(this._storage);

  static const _urlKey = 'newtv.server.url';
  static const _selfSignedKey = 'newtv.server.self_signed';
  static const _storageTypeKey = 'newtv.server.storage_type';
  static const _turnstileKey = 'newtv.server.login_turnstile';
  final FlutterSecureStorage _storage;

  Future<ServerConfig?> load() async {
    final stored = await _storage.read(key: _urlKey);
    final value = stored ?? const String.fromEnvironment('NEWTV_SERVER_URL');
    if (value.isEmpty) return null;
    final normalized = ServerConfig.normalize(value);
    if (normalized == null || normalized.isEmpty) return null;
    final allowSelfSigned =
        await _storage.read(key: _selfSignedKey) == 'true';
    return ServerConfig(baseUrl: normalized, allowSelfSigned: allowSelfSigned);
  }

  Future<void> save(ServerConfig config) async {
    await _storage.write(key: _urlKey, value: config.baseUrl);
    await _storage.write(
      key: _selfSignedKey,
      value: config.allowSelfSigned.toString(),
    );
  }

  Future<String> loadStorageType() async {
    return await _storage.read(key: _storageTypeKey) ?? '';
  }

  Future<void> saveStorageType(String storageType) async {
    await _storage.write(key: _storageTypeKey, value: storageType);
  }

  Future<bool> loadLoginRequireTurnstile() async {
    return await _storage.read(key: _turnstileKey) == 'true';
  }

  Future<void> saveLoginRequireTurnstile(bool required) async {
    await _storage.write(key: _turnstileKey, value: required.toString());
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _selfSignedKey);
    await _storage.delete(key: _storageTypeKey);
    await _storage.delete(key: _turnstileKey);
  }
}
