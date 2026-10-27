import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/secure_cookie_storage.dart';
import '../../core/auth/session_manager.dart';
import '../../core/config/app_settings.dart';
import '../../core/config/server_config.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/image_url.dart';
import 'api/auth_api.dart';
import 'api/media_api.dart';
import 'repositories/media_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.preferences,
    required this.secureStorage,
    required this.serverStore,
    required this.settings,
    required this.cookieJar,
    required this.session,
    required this.dioClient,
    required this.authApi,
    required this.mediaRepository,
  });

  final SharedPreferences preferences;
  final FlutterSecureStorage secureStorage;
  final ServerConfigStore serverStore;
  final SettingsController settings;
  final PersistCookieJar cookieJar;
  final SessionManager session;
  final DioClient dioClient;
  final AuthApi authApi;
  final MediaRepository mediaRepository;

  static Future<AppDependencies> create() async {
    final preferences = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final serverStore = ServerConfigStore(secureStorage);
    final settings = SettingsController(preferences);
    final cookieStorage = SecureCookieStorage(secureStorage);
    final cookieJar = PersistCookieJar(storage: cookieStorage, persistSession: true);
    final server = await serverStore.load();
    var hasCookies = false;
    if (server != null) {
      final cookies = await cookieJar.loadForRequest(Uri.parse(server.baseUrl));
      hasCookies = cookies.isNotEmpty;
      // 冷启动时已经登录的情况，海报同样需要带上 Cookie 才能走图片代理。
      ImageAuth.update(
        baseUrl: server.baseUrl,
        cookieHeader:
            cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
      );
    }
    late SessionManager session;
    final dioClient = DioClient(
      cookieJar: cookieJar,
      server: server,
      onSessionExpired: () => session.expire(),
    );
    session = SessionManager(cookieJar, server, hasCookies);
    final dio = dioClient.dio;
    return AppDependencies(
      preferences: preferences,
      secureStorage: secureStorage,
      serverStore: serverStore,
      settings: settings,
      cookieJar: cookieJar,
      session: session,
      dioClient: dioClient,
      authApi: AuthApi(dio),
      mediaRepository: MediaRepository(MediaApi(dio)),
    );
  }
}

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
