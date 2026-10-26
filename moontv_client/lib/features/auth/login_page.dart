import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cookieController = TextEditingController();
  final _turnstileController = TextEditingController();
  var _needsUsername = true;
  var _requireTurnstile = false;
  var _showCookieImport = false;
  var _remember = true;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadServerAuthConfig());
  }

  Future<void> _loadServerAuthConfig() async {
    final dependencies = ref.read(appDependenciesProvider);
    final storedType = await dependencies.serverStore.loadStorageType();
    final storedTurnstile =
        await dependencies.serverStore.loadLoginRequireTurnstile();
    if (mounted) {
      setState(() {
        _needsUsername = storedType.toLowerCase() != 'localstorage';
        _requireTurnstile = storedTurnstile;
        if (storedTurnstile) _showCookieImport = true;
      });
    }

    final server = dependencies.session.server;
    if (server == null) return;
    try {
      final probe = await dependencies.authApi.probe(server);
      await dependencies.serverStore.saveStorageType(probe.storageType);
      await dependencies.serverStore.saveLoginRequireTurnstile(
        probe.loginRequireTurnstile,
      );
      if (!mounted) return;
      setState(() {
        _needsUsername = probe.needsUsername;
        _requireTurnstile = probe.loginRequireTurnstile;
        if (probe.loginRequireTurnstile) _showCookieImport = true;
      });
    } catch (_) {
      // Keep cached or default (_needsUsername = true) when offline.
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _cookieController.dispose();
    _turnstileController.dispose();
    super.dispose();
  }

  static String _extractAuthCookieValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    for (final segment in trimmed.split(';')) {
      final part = segment.trim();
      if (part.startsWith('auth=')) {
        return part.substring('auth='.length).trim();
      }
    }
    return trimmed;
  }

  Future<void> _loginWithCookie() async {
    final authValue = _extractAuthCookieValue(_cookieController.text);
    if (authValue.isEmpty) {
      setState(() => _error = '请粘贴浏览器登录后的 auth Cookie 值');
      return;
    }
    final dependencies = ref.read(appDependenciesProvider);
    final server = dependencies.session.server;
    if (server == null) {
      setState(() => _error = '请先配置服务器地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(server.baseUrl);
      final cookie = Cookie('auth', authValue)
        ..path = '/'
        ..httpOnly = false;
      await dependencies.cookieJar.saveFromResponse(uri, [cookie]);
      await dependencies.authApi.verifyCookieSession();
      await dependencies.preferences.setBool('sessionOnly', !_remember);
      dependencies.session.markAuthenticated();
      if (mounted) context.go('/home');
    } catch (error) {
      await dependencies.cookieJar.deleteAll();
      if (mounted) setState(() => _error = readableError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final password = _passwordController.text;
    final username = _usernameController.text;
    final turnstileToken = _turnstileController.text;
    if (password.isEmpty || (_needsUsername && username.trim().isEmpty)) {
      setState(() => _error = _needsUsername ? '请输入用户名和密码' : '请输入密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dependencies = ref.read(appDependenciesProvider);
      await dependencies.authApi.login(
        username: _needsUsername ? username : null,
        password: password,
        turnstileToken: turnstileToken.trim().isEmpty ? null : turnstileToken,
      );
      if (!_remember) {
        await dependencies.preferences.setBool('sessionOnly', true);
      } else {
        await dependencies.preferences.setBool('sessionOnly', false);
      }
      dependencies.session.markAuthenticated();
      if (mounted) context.go('/home');
    } catch (error) {
      final message = readableError(error);
      if (mounted) {
        setState(() {
          _error = message;
          if (message.contains('人机验证')) {
            _requireTurnstile = true;
            _showCookieImport = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.lock_open_rounded, size: 64, color: scheme.primary),
              const SizedBox(height: 20),
              Text('登录', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_requireTurnstile) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.tertiary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '当前服务器已开启 Cloudflare Turnstile 登录人机验证。\n'
                          '• 推荐：在服务端后台关闭「登录人机验证」即可直接用账号密码登录；\n'
                          '• 不关闭：可在下方粘贴浏览器登录后的 auth Cookie 授权登录。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_needsUsername) ...[
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.password_outlined),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('保持登录'),
                      value: _remember,
                      onChanged: (value) => setState(() => _remember = value ?? true),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
                      ),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('登录'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _showCookieImport = !_showCookieImport),
                      icon: Icon(
                        _showCookieImport ? Icons.expand_less : Icons.verified_user_outlined,
                        size: 18,
                      ),
                      label: Text(_showCookieImport ? '收起 Cookie / 验证辅助登录' : '开启了 Cloudflare 验证？用 Cookie 辅助登录'),
                    ),
                    if (_showCookieImport) ...[
                      const Divider(height: 24),
                      TextField(
                        controller: _cookieController,
                        decoration: const InputDecoration(
                          labelText: '浏览器 auth Cookie（免关 Cloudflare 验证）',
                          hintText: '粘贴浏览器开发者工具中的 auth Cookie 值',
                          prefixIcon: Icon(Icons.cookie_outlined),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _loginWithCookie,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('使用 Cookie 授权登录'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _turnstileController,
                        decoration: const InputDecoration(
                          labelText: 'Turnstile Token（可选）',
                          hintText: 'cf-turnstile-response',
                          prefixIcon: Icon(Icons.shield_outlined),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: _loading ? null : () => context.go('/onboarding'),
                      child: const Text('更换服务器'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
